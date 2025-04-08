// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {Intent} from "../src/intent.sol";
import {MockGateway} from "./mocks/MockGateway.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {PayloadUtils} from "../src/utils/PayloadUtils.sol";
import {IGateway} from "../src/interfaces/IGateway.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract IntentTest is Test {
    Intent public intent;
    Intent public intentImplementation;
    MockGateway public gateway;
    MockERC20 public token;
    address public owner;
    address public user1;
    address public user2;
    address public router;

    // Define the event to match the one in Intent contract
    event IntentInitiated(
        bytes32 indexed intentId,
        address indexed asset,
        uint256 amount,
        uint256 targetChain,
        bytes receiver,
        uint256 tip,
        uint256 salt
    );

    // Define the event for intent fulfillment
    event IntentFulfilled(
        bytes32 indexed intentId,
        address indexed asset,
        uint256 amount,
        address indexed receiver
    );

    // Define the event for intent settlement
    event IntentSettled(
        bytes32 indexed intentId,
        address indexed asset,
        uint256 amount,
        address indexed receiver,
        bool fulfilled,
        address fulfiller,
        uint256 actualAmount,
        uint256 paidTip
    );

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        router = makeAddr("router");

        // Deploy mock contracts
        gateway = new MockGateway();
        token = new MockERC20("Test Token", "TEST");

        // Deploy implementation
        intentImplementation = new Intent();

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            Intent.initialize.selector,
            address(gateway),
            router
        );

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(intentImplementation),
            initData
        );
        intent = Intent(address(proxy));

        // Setup test tokens - We'll mint specific amounts in each test rather than here
    }

    function test_Initialization() public {
        assertEq(intent.owner(), owner);
        assertEq(intent.gateway(), address(gateway));
        assertEq(intent.router(), router);
    }

    function test_ComputeIntentId() public {
        // Test parameters
        uint256 counter = 42;
        uint256 salt = 123;
        uint256 chainId = 1337;
        
        // Expected result (manually computed)
        bytes32 expectedId = keccak256(abi.encodePacked(counter, salt, chainId));
        
        // Call the function and verify result
        bytes32 actualId = intent.computeIntentId(counter, salt, chainId);
        
        assertEq(actualId, expectedId, "Intent ID computation does not match expected value");
    }
    
    function test_ComputeIntentId_Uniqueness() public {
        // Different counters
        bytes32 id1 = intent.computeIntentId(1, 100, 1);
        bytes32 id2 = intent.computeIntentId(2, 100, 1);
        assertTrue(id1 != id2, "IDs should be different with different counters");
        
        // Different salts
        bytes32 id3 = intent.computeIntentId(1, 100, 1);
        bytes32 id4 = intent.computeIntentId(1, 200, 1);
        assertTrue(id3 != id4, "IDs should be different with different salts");
        
        // Different chain IDs
        bytes32 id5 = intent.computeIntentId(1, 100, 1);
        bytes32 id6 = intent.computeIntentId(1, 100, 2);
        assertTrue(id5 != id6, "IDs should be different with different chain IDs");
    }

    function test_GetNextIntentId() public {
        uint256 salt = 789;
        uint256 currentChainId = block.chainid;
        
        // Get the initial counter value
        uint256 initialCounter = intent.intentCounter();
        
        // Get the next intent ID
        bytes32 nextIntentId = intent.getNextIntentId(salt);
        
        // Verify it matches the expected computation
        assertEq(nextIntentId, intent.computeIntentId(initialCounter, salt, currentChainId));
        
        // Mint tokens for initiate
        uint256 amount = 50 ether;
        uint256 tip = 5 ether;
        token.mint(user1, amount + tip);
        vm.prank(user1);
        token.approve(address(intent), amount + tip);
        
        // Initiate an intent which should increment the counter
        uint256 targetChain = 2;
        bytes memory receiver = abi.encodePacked(user2);
        
        vm.prank(user1);
        bytes32 actualIntentId = intent.initiate(
            address(token),
            amount,
            targetChain,
            receiver,
            tip,
            salt
        );
        
        // Verify the intent ID matches what we predicted
        assertEq(actualIntentId, nextIntentId);
        
        // Verify counter was incremented
        assertEq(intent.intentCounter(), initialCounter + 1);
        
        // Get the next intent ID again
        bytes32 nextIntentId2 = intent.getNextIntentId(salt);
        
        // Verify it's different than the previous one
        assertTrue(nextIntentId2 != nextIntentId);
    }

    function test_GetFulfillmentIndex() public {
        // Test parameters
        bytes32 intentId = bytes32(uint256(123));
        address asset = address(token);
        uint256 amount = 50 ether;
        address receiver = user2;
        
        // Expected result calculated using PayloadUtils directly
        bytes32 expectedIndex = PayloadUtils.computeFulfillmentIndex(
            intentId,
            asset,
            amount,
            receiver
        );
        
        // Call the function and verify result
        bytes32 actualIndex = intent.getFulfillmentIndex(
            intentId,
            asset,
            amount,
            receiver
        );
        
        // Verify the computed index matches what we expect
        assertEq(actualIndex, expectedIndex, "Fulfillment index computation does not match expected value");
        
        // Verify it matches with the internal computation too
        assertEq(actualIndex, keccak256(abi.encodePacked(
            intentId,
            asset,
            amount,
            receiver
        )), "Index doesn't match raw computation");
    }

    function test_Initiate() public {
        // Test parameters
        uint256 amount = 100 ether;
        uint256 tip = 10 ether;
        uint256 targetChain = 1;
        bytes memory receiver = abi.encodePacked(user2);
        uint256 salt = 123;
        uint256 currentChainId = block.chainid;

        // Mint tokens for initiate
        token.mint(user1, amount + tip);
        vm.prank(user1);
        token.approve(address(intent), amount + tip);

        // Expect the IntentInitiated event
        vm.expectEmit(true, true, false, false);
        emit IntentInitiated(
            intent.computeIntentId(0, salt, currentChainId), // First intent ID with chainId
            address(token),
            amount,
            targetChain,
            receiver,
            tip,
            salt
        );

        // Call initiate
        vm.prank(user1);
        bytes32 intentId = intent.initiate(
            address(token),
            amount,
            targetChain,
            receiver,
            tip,
            salt
        );

        // Verify intent ID
        assertEq(intentId, intent.computeIntentId(0, salt, currentChainId));

        // Verify gateway received the correct amount
        assertEq(token.balanceOf(address(gateway)), amount + tip);

        // Verify gateway call data
        (address callReceiver, uint256 callAmount, address callAsset, bytes memory callPayload, IGateway.RevertOptions memory callRevertOptions) = gateway.lastCall();
        assertEq(callReceiver, router);
        assertEq(callAmount, amount + tip);
        assertEq(callAsset, address(token));

        // Verify payload
        PayloadUtils.IntentPayload memory payload = PayloadUtils.decodeIntentPayload(callPayload);
        assertEq(payload.intentId, intentId);
        assertEq(payload.amount, amount);
        assertEq(payload.tip, tip);
        assertEq(payload.targetChain, targetChain);
        assertEq(keccak256(payload.receiver), keccak256(receiver));
    }

    function test_InitiateInsufficientBalance() public {
        // Test parameters
        uint256 amount = 1000 ether;
        uint256 tip = 10 ether;
        uint256 targetChain = 1;
        bytes memory receiver = abi.encodePacked(user2);
        uint256 salt = 123;

        // Mint tokens for initiate, but not enough
        token.mint(user1, amount); // Not enough for amount + tip
        vm.prank(user1);
        token.approve(address(intent), amount + tip);

        // Call initiate and expect revert with ERC20InsufficientBalance error
        vm.prank(user1);
        vm.expectRevert();
        intent.initiate(
            address(token),
            amount,
            targetChain,
            receiver,
            tip,
            salt
        );
    }

    function test_Fulfill() public {
        // First create an intent
        uint256 amount = 100 ether;
        uint256 tip = 10 ether;
        uint256 targetChain = 1;
        bytes memory receiver = abi.encodePacked(user2);
        uint256 salt = 123;

        // Mint tokens for initiate
        token.mint(user1, amount + tip);
        vm.prank(user1);
        token.approve(address(intent), amount + tip);

        vm.prank(user1);
        bytes32 intentId = intent.initiate(
            address(token),
            amount,
            targetChain,
            receiver,
            tip,
            salt
        );

        // Mint tokens to the fulfiller (user1) and approve them for the intent contract
        token.mint(user1, amount);
        vm.prank(user1);
        token.approve(address(intent), amount);

        // Expect the IntentFulfilled event
        vm.expectEmit(true, true, false, true);
        emit IntentFulfilled(
            intentId,
            address(token),
            amount,
            user2
        );

        // Call fulfill
        vm.prank(user1);
        intent.fulfill(
            intentId,
            address(token),
            amount,
            user2
        );

        // Verify fulfillment was registered
        bytes32 fulfillmentIndex = PayloadUtils.computeFulfillmentIndex(
            intentId,
            address(token),
            amount,
            user2
        );
        assertEq(intent.fulfillments(fulfillmentIndex), user1);

        // Verify tokens were transferred from user1 to user2
        assertEq(token.balanceOf(user2), amount);
    }

    function test_FulfillAlreadyFulfilled() public {
        // First create and fulfill an intent
        uint256 amount = 100 ether;
        uint256 tip = 10 ether;
        uint256 targetChain = 1;
        bytes memory receiver = abi.encodePacked(user2);
        uint256 salt = 123;

        // Mint tokens for initiate
        token.mint(user1, amount + tip);
        vm.prank(user1);
        token.approve(address(intent), amount + tip);

        vm.prank(user1);
        bytes32 intentId = intent.initiate(
            address(token),
            amount,
            targetChain,
            receiver,
            tip,
            salt
        );

        // Mint tokens to the fulfiller (user1) and approve them for the intent contract
        token.mint(user1, amount);
        vm.prank(user1);
        token.approve(address(intent), amount);

        // First fulfillment
        vm.prank(user1);
        intent.fulfill(
            intentId,
            address(token),
            amount,
            user2
        );

        // Try to fulfill again with same parameters and expect revert
        // First need to mint and approve more tokens
        token.mint(user1, amount);
        vm.prank(user1);
        token.approve(address(intent), amount);
        
        vm.prank(user1);
        vm.expectRevert("Intent already fulfilled with these parameters");
        intent.fulfill(
            intentId,
            address(token),
            amount,
            user2
        );
    }

    function test_FulfillWithDifferentParameters() public {
        // First create and fulfill an intent
        uint256 amount = 100 ether;
        uint256 tip = 10 ether;
        uint256 targetChain = 1;
        bytes memory receiver = abi.encodePacked(user2);
        uint256 salt = 123;

        // Mint tokens for initiate
        token.mint(user1, amount + tip);
        vm.prank(user1);
        token.approve(address(intent), amount + tip);

        vm.prank(user1);
        bytes32 intentId = intent.initiate(
            address(token),
            amount,
            targetChain,
            receiver,
            tip,
            salt
        );

        // Mint tokens to the fulfiller (user1) and approve them for both fulfillments
        token.mint(user1, amount + (amount + 1 ether));
        vm.prank(user1);
        token.approve(address(intent), amount + (amount + 1 ether));

        // First fulfillment
        vm.prank(user1);
        intent.fulfill(
            intentId,
            address(token),
            amount,
            user2
        );

        // Try to fulfill with different amount
        vm.prank(user1);
        intent.fulfill(
            intentId,
            address(token),
            amount + 1 ether,
            user2
        );

        // Verify both fulfillments were registered
        bytes32 fulfillmentIndex1 = PayloadUtils.computeFulfillmentIndex(
            intentId,
            address(token),
            amount,
            user2
        );
        bytes32 fulfillmentIndex2 = PayloadUtils.computeFulfillmentIndex(
            intentId,
            address(token),
            amount + 1 ether,
            user2
        );
        assertEq(intent.fulfillments(fulfillmentIndex1), user1);
        assertEq(intent.fulfillments(fulfillmentIndex2), user1);

        // Verify tokens were transferred for both fulfillments
        assertEq(token.balanceOf(user2), amount + (amount + 1 ether));
    }

    function test_OnCallWithFulfillment() public {
        // First create and fulfill an intent
        uint256 amount = 100 ether;
        uint256 tip = 10 ether;
        uint256 targetChain = 1;
        bytes memory receiver = abi.encodePacked(user2);
        uint256 salt = 123;

        // Mint tokens for initiate
        token.mint(user1, amount + tip);
        vm.prank(user1);
        token.approve(address(intent), amount + tip);

        // Initiate the intent
        vm.prank(user1);
        bytes32 intentId = intent.initiate(
            address(token),
            amount,
            targetChain,
            receiver,
            tip,
            salt
        );

        // Mint additional tokens for fulfillment
        token.mint(user1, amount);
        vm.prank(user1);
        token.approve(address(intent), amount);

        // Fulfill the intent
        vm.prank(user1);
        intent.fulfill(
            intentId,
            address(token),
            amount,
            user2
        );

        // Prepare settlement payload
        bytes memory settlementPayload = PayloadUtils.encodeSettlementPayload(
            intentId,
            amount,
            address(token),
            user2,
            tip,
            amount  // actualAmount same as amount in the test case
        );

        // Transfer tokens to gateway for settlement
        token.mint(address(gateway), amount + tip);
        vm.prank(address(gateway));
        token.approve(address(intent), amount + tip);

        // Call onCall through gateway
        vm.prank(address(gateway));
        intent.onCall(
            Intent.MessageContext({
                sender: router
            }),
            settlementPayload
        );

        // Verify settlement record
        bytes32 fulfillmentIndex = PayloadUtils.computeFulfillmentIndex(
            intentId,
            address(token),
            amount,
            user2
        );
        (bool settled, bool fulfilled, uint256 paidTip, address fulfiller) = intent.settlements(fulfillmentIndex);
        assertTrue(settled, "Settlement should be marked as settled");
        assertTrue(fulfilled, "Settlement should be marked as fulfilled");
        assertEq(paidTip, tip, "Paid tip should match the input tip");
        assertEq(fulfiller, user1, "Fulfiller should be user1");

        // Verify tokens were transferred to fulfiller (amount + tip)
        assertEq(token.balanceOf(user1), amount + tip, "User1 should receive amount + tip");
    }

    function test_OnCallWithoutFulfillment() public {
        // Create an intent
        uint256 amount = 100 ether;
        uint256 tip = 10 ether;
        uint256 targetChain = 1;
        bytes memory receiver = abi.encodePacked(user2);
        uint256 salt = 123;

        // Reset user2 balance for clean testing
        vm.prank(user2);
        token.transfer(address(this), token.balanceOf(user2));
        assertEq(token.balanceOf(user2), 0, "Initial balance should be 0");

        // Mint tokens for initiate
        token.mint(user1, amount + tip);
        vm.prank(user1);
        token.approve(address(intent), amount + tip);

        vm.prank(user1);
        bytes32 intentId = intent.initiate(
            address(token),
            amount,
            targetChain,
            receiver,
            tip,
            salt
        );

        // Prepare settlement payload
        bytes memory settlementPayload = PayloadUtils.encodeSettlementPayload(
            intentId,
            amount,
            address(token),
            user2,
            tip,
            amount  // actualAmount same as amount in the test case
        );

        // Transfer tokens to gateway for settlement
        token.mint(address(gateway), amount + tip);
        vm.prank(address(gateway));
        token.approve(address(intent), amount + tip);

        // Call onCall through gateway
        vm.prank(address(gateway));
        intent.onCall(
            Intent.MessageContext({
                sender: router
            }),
            settlementPayload
        );

        // Verify settlement record
        bytes32 fulfillmentIndex = PayloadUtils.computeFulfillmentIndex(
            intentId,
            address(token),
            amount,
            user2
        );
        (bool settled, bool fulfilled, uint256 paidTip, address fulfiller) = intent.settlements(fulfillmentIndex);
        assertTrue(settled);
        assertFalse(fulfilled);
        assertEq(paidTip, 0);
        assertEq(fulfiller, address(0));

        // Verify tokens were transferred to receiver (amount + tip)
        assertEq(token.balanceOf(user2), amount + tip, "User2 should receive amount + tip");
    }

    function test_OnCallInvalidSender() public {
        // Create an intent
        uint256 amount = 100 ether;
        uint256 tip = 10 ether;
        uint256 targetChain = 1;
        bytes memory receiver = abi.encodePacked(user2);
        uint256 salt = 123;

        // Mint tokens for initiate
        token.mint(user1, amount + tip);
        vm.prank(user1);
        token.approve(address(intent), amount + tip);

        vm.prank(user1);
        bytes32 intentId = intent.initiate(
            address(token),
            amount,
            targetChain,
            receiver,
            tip,
            salt
        );

        // Prepare settlement payload
        bytes memory settlementPayload = PayloadUtils.encodeSettlementPayload(
            intentId,
            amount,
            address(token),
            user2,
            tip,
            amount  // actualAmount same as amount in the test case
        );

        // Transfer tokens to gateway for settlement
        token.mint(address(gateway), amount + tip);
        vm.prank(address(gateway));
        token.approve(address(intent), amount + tip);

        // Call onCall through gateway with invalid sender
        vm.prank(address(gateway));
        vm.expectRevert("Invalid sender");
        intent.onCall(
            Intent.MessageContext({
                sender: address(0x123) // Invalid sender
            }),
            settlementPayload
        );
    }

    function test_OnCallWithActualAmountDifferent() public {
        // Create an intent
        uint256 amount = 100 ether;
        uint256 actualAmount = 93 ether; // Simulating 7 ether reduction due to insufficient tip
        uint256 tip = 3 ether;
        uint256 targetChain = 1;
        bytes memory receiver = abi.encodePacked(user2);
        uint256 salt = 123;

        // Mint tokens for initiate
        token.mint(user1, amount + tip);
        vm.prank(user1);
        token.approve(address(intent), amount + tip);

        // Initiate an intent from user1
        vm.prank(user1);
        bytes32 intentId = intent.initiate(
            address(token),
            amount,
            targetChain,
            receiver,
            tip,
            salt
        );
        
        // Mint additional tokens for fulfillment
        token.mint(user1, amount);
        vm.prank(user1);
        token.approve(address(intent), amount);

        // Fulfill the intent with the original amount (for indexing purposes)
        vm.prank(user1);
        intent.fulfill(
            intentId,
            address(token),
            amount,
            user2
        );

        // Prepare settlement payload with different actualAmount
        bytes memory settlementPayload = PayloadUtils.encodeSettlementPayload(
            intentId,
            amount,            // Original amount (for index calculation)
            address(token),
            user2,
            tip,
            actualAmount       // Reduced actual amount to transfer
        );

        // Transfer tokens to gateway for settlement
        token.mint(address(gateway), actualAmount + tip);
        vm.prank(address(gateway));
        token.approve(address(intent), actualAmount + tip);

        // Call onCall through gateway
        vm.prank(address(gateway));
        intent.onCall(
            Intent.MessageContext({
                sender: router
            }),
            settlementPayload
        );

        // Verify settlement record
        bytes32 fulfillmentIndex = PayloadUtils.computeFulfillmentIndex(
            intentId,
            address(token),
            amount,            // Original amount for index calculation
            user2
        );
        (bool settled, bool fulfilled, uint256 paidTip, address fulfiller) = intent.settlements(fulfillmentIndex);
        assertTrue(settled, "Settlement should be marked as settled");
        assertTrue(fulfilled, "Settlement should be marked as fulfilled");
        assertEq(paidTip, tip, "Paid tip should match the input tip");
        assertEq(fulfiller, user1, "Fulfiller should be user1");

        // Verify tokens were transferred to fulfiller
        // User1 should receive actualAmount (93 ether) + tip (3 ether) = 96 ether
        assertEq(token.balanceOf(user1), actualAmount + tip, "User1 should receive actualAmount + tip");
        
        // Additional check: the payment should be actualAmount + tip
        // rather than amount + tip that would have been sent with the original amount
        assertEq(actualAmount + tip, 96 ether, "Payment amount should be actualAmount + tip");
        assertLt(actualAmount, amount, "Actual amount should be less than original amount");
    }

    function test_FulfillAlreadySettled() public {
        // First create an intent
        uint256 amount = 100 ether;
        uint256 tip = 10 ether;
        uint256 targetChain = 1;
        bytes memory receiver = abi.encodePacked(user2);
        uint256 salt = 123;

        // Mint tokens for initiate
        token.mint(user1, amount + tip);
        vm.prank(user1);
        token.approve(address(intent), amount + tip);

        vm.prank(user1);
        bytes32 intentId = intent.initiate(
            address(token),
            amount,
            targetChain,
            receiver,
            tip,
            salt
        );

        // Prepare settlement payload
        bytes memory settlementPayload = PayloadUtils.encodeSettlementPayload(
            intentId,
            amount,
            address(token),
            user2,
            tip,
            amount  // actualAmount same as amount in the test case
        );

        // Transfer tokens to gateway for settlement
        token.mint(address(gateway), amount + tip);
        vm.prank(address(gateway));
        token.approve(address(intent), amount + tip);

        // Call onCall through gateway to settle the intent
        vm.prank(address(gateway));
        intent.onCall(
            Intent.MessageContext({
                sender: router
            }),
            settlementPayload
        );

        // Verify settlement was recorded
        bytes32 fulfillmentIndex = PayloadUtils.computeFulfillmentIndex(
            intentId,
            address(token),
            amount,
            user2
        );
        (bool settled, ,, ) = intent.settlements(fulfillmentIndex);
        assertTrue(settled, "Settlement should be marked as settled");
        
        // Now try to fulfill the already settled intent
        // Mint tokens to the fulfiller (user1) and approve them for the intent contract
        token.mint(user1, amount);
        vm.prank(user1);
        token.approve(address(intent), amount);
        
        // Expect revert with "Intent already settled" error
        vm.prank(user1);
        vm.expectRevert("Intent already settled");
        intent.fulfill(
            intentId,
            address(token),
            amount,
            user2
        );
    }

    function test_SettleAlreadySettled() public {
        // First create an intent
        uint256 amount = 100 ether;
        uint256 tip = 10 ether;
        uint256 targetChain = 1;
        bytes memory receiver = abi.encodePacked(user2);
        uint256 salt = 123;

        // Mint tokens for initiate
        token.mint(user1, amount + tip);
        vm.prank(user1);
        token.approve(address(intent), amount + tip);

        vm.prank(user1);
        bytes32 intentId = intent.initiate(
            address(token),
            amount,
            targetChain,
            receiver,
            tip,
            salt
        );

        // Prepare settlement payload
        bytes memory settlementPayload = PayloadUtils.encodeSettlementPayload(
            intentId,
            amount,
            address(token),
            user2,
            tip,
            amount  // actualAmount same as amount in the test case
        );

        // Transfer tokens to gateway for settlement
        token.mint(address(gateway), amount + tip);
        vm.prank(address(gateway));
        token.approve(address(intent), amount + tip);

        // Call onCall through gateway to settle the intent the first time
        vm.prank(address(gateway));
        intent.onCall(
            Intent.MessageContext({
                sender: router
            }),
            settlementPayload
        );

        // Verify settlement was recorded
        bytes32 fulfillmentIndex = PayloadUtils.computeFulfillmentIndex(
            intentId,
            address(token),
            amount,
            user2
        );
        (bool settled, ,, ) = intent.settlements(fulfillmentIndex);
        assertTrue(settled, "Settlement should be marked as settled");
        
        // Now try to settle the already settled intent again
        // Transfer more tokens to gateway for the second settlement attempt
        token.mint(address(gateway), amount + tip);
        vm.prank(address(gateway));
        token.approve(address(intent), amount + tip);
        
        // Expect revert with "Intent already settled" error
        vm.prank(address(gateway));
        vm.expectRevert("Intent already settled");
        intent.onCall(
            Intent.MessageContext({
                sender: router
            }),
            settlementPayload
        );
    }

    function test_OnCallEmitsSettlementEvent() public {
        // First create an intent
        uint256 amount = 100 ether;
        uint256 tip = 10 ether;
        uint256 targetChain = 1;
        bytes memory receiver = abi.encodePacked(user2);
        uint256 salt = 123;

        // Mint tokens for initiate
        token.mint(user1, amount + tip);
        vm.prank(user1);
        token.approve(address(intent), amount + tip);

        vm.prank(user1);
        bytes32 intentId = intent.initiate(
            address(token),
            amount,
            targetChain,
            receiver,
            tip,
            salt
        );

        // Prepare settlement payload
        bytes memory settlementPayload = PayloadUtils.encodeSettlementPayload(
            intentId,
            amount,
            address(token),
            user2,
            tip,
            amount  // actualAmount same as amount in the test case
        );

        // Transfer tokens to gateway for settlement
        token.mint(address(gateway), amount + tip);
        vm.prank(address(gateway));
        token.approve(address(intent), amount + tip);
        
        // Test case 1: Settle without fulfillment
        // Expect the IntentSettled event (with fulfilled=false)
        vm.expectEmit(true, true, false, true);
        emit IntentSettled(
            intentId,
            address(token),
            amount,
            user2,
            false,  // fulfilled
            address(0),  // fulfiller
            amount,  // actualAmount
            0  // paidTip
        );

        // Call onCall through gateway to settle the intent
        vm.prank(address(gateway));
        intent.onCall(
            Intent.MessageContext({
                sender: router
            }),
            settlementPayload
        );
        
        // Test case 2: Intent with fulfillment
        // Create another intent
        uint256 amount2 = 150 ether;
        uint256 tip2 = 15 ether;
        uint256 salt2 = 456;
        
        // Mint tokens for the second initiate
        token.mint(user1, amount2 + tip2);
        vm.prank(user1);
        token.approve(address(intent), amount2 + tip2);
        
        vm.prank(user1);
        bytes32 intentId2 = intent.initiate(
            address(token),
            amount2,
            targetChain,
            receiver,
            tip2,
            salt2
        );
        
        // Fulfill the intent first
        token.mint(user1, amount2);
        vm.prank(user1);
        token.approve(address(intent), amount2);
        
        vm.prank(user1);
        intent.fulfill(
            intentId2,
            address(token),
            amount2,
            user2
        );
        
        // Prepare settlement payload for the second intent
        bytes memory settlementPayload2 = PayloadUtils.encodeSettlementPayload(
            intentId2,
            amount2,
            address(token),
            user2,
            tip2,
            amount2  // actualAmount
        );
        
        // Transfer tokens to gateway for settlement
        token.mint(address(gateway), amount2 + tip2);
        vm.prank(address(gateway));
        token.approve(address(intent), amount2 + tip2);
        
        // Expect the IntentSettled event (with fulfilled=true)
        vm.expectEmit(true, true, false, true);
        emit IntentSettled(
            intentId2,
            address(token),
            amount2,
            user2,
            true,  // fulfilled
            user1,  // fulfiller
            amount2,  // actualAmount
            tip2  // paidTip
        );
        
        // Call onCall through gateway to settle the second intent
        vm.prank(address(gateway));
        intent.onCall(
            Intent.MessageContext({
                sender: router
            }),
            settlementPayload2
        );
    }

    // TODO: Add more tests for:
    // - complete
    // - onCall
    // - onRevert
} 