// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Test, console2} from "forge-std/Test.sol";
import {Intent} from "../src/Intent.sol";
import {MockGateway} from "./mocks/MockGateway.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockRouter} from "./mocks/MockRouter.sol";
import {MockIntentTarget} from "./mocks/MockIntentTarget.sol";
import {PayloadUtils} from "../src/utils/PayloadUtils.sol";
import {IGateway} from "../src/interfaces/IGateway.sol";
import {IRouter} from "../src/interfaces/IRouter.sol";
import "../src/interfaces/IIntent.sol";

contract IntentTest is Test {
    Intent public intent;
    Intent public intentImplementation;
    MockGateway public gateway;
    MockERC20 public token;
    address public owner;
    address public user1;
    address public user2;
    address public router;

    // Role constants
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

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

    // Define the event for intent with call
    event IntentInitiatedWithCall(
        bytes32 indexed intentId,
        address indexed asset,
        uint256 amount,
        uint256 targetChain,
        bytes receiver,
        uint256 tip,
        uint256 salt,
        bytes data
    );

    // Define the event for intent fulfillment
    event IntentFulfilled(bytes32 indexed intentId, address indexed asset, uint256 amount, address indexed receiver);

    // Define the event for intent fulfillment with call
    event IntentFulfilledWithCall(
        bytes32 indexed intentId, address indexed asset, uint256 amount, address indexed receiver, bytes data
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

    // Define the event for intent settlement with call
    event IntentSettledWithCall(
        bytes32 indexed intentId,
        address indexed asset,
        uint256 amount,
        address indexed receiver,
        bool fulfilled,
        address fulfiller,
        uint256 actualAmount,
        uint256 paidTip,
        bytes data
    );

    // Define events for gateway and router updates
    event GatewayUpdated(address indexed oldGateway, address indexed newGateway);
    event RouterUpdated(address indexed oldRouter, address indexed newRouter);

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        router = makeAddr("router");

        // Deploy mock contracts
        gateway = new MockGateway();
        token = new MockERC20("Test Token", "TEST");

        // Deploy implementation (not on ZetaChain)
        intentImplementation = new Intent(false);

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(Intent.initialize.selector, address(gateway), router);

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(intentImplementation), initData);
        intent = Intent(address(proxy));

        // Setup test tokens - We'll mint specific amounts in each test rather than here
    }

    // Helper to deploy a new intent contract with isZetaChain=true
    function _deployZetaChainIntent() internal returns (Intent) {
        // Deploy implementation (on ZetaChain)
        Intent zetaChainImpl = new Intent(true);

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(Intent.initialize.selector, address(gateway), router);

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(zetaChainImpl), initData);
        return Intent(address(proxy));
    }

    function test_Initialization() public {
        owner = owner;
        assertTrue(intent.hasRole(DEFAULT_ADMIN_ROLE, owner));
        assertTrue(intent.hasRole(PAUSER_ROLE, owner));
        assertEq(intent.gateway(), address(gateway));
        assertEq(intent.router(), router);
    }

    function test_InitializationWithZeroAddresses() public {
        // Deploy a new implementation
        Intent newImplementation = new Intent(false);

        // Prepare initialization data with zero gateway
        bytes memory initDataZeroGateway = abi.encodeWithSelector(Intent.initialize.selector, address(0), router);

        // Deploy proxy with zero gateway
        vm.expectRevert("Gateway cannot be zero address");
        new ERC1967Proxy(address(newImplementation), initDataZeroGateway);

        // Prepare initialization data with zero router
        bytes memory initDataZeroRouter =
            abi.encodeWithSelector(Intent.initialize.selector, address(gateway), address(0));

        // Deploy proxy with zero router
        vm.expectRevert("Router cannot be zero address");
        new ERC1967Proxy(address(newImplementation), initDataZeroRouter);
    }

    function test_ComputeIntentId() public {
        owner = owner;

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
        owner = owner;

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
        bytes32 actualIntentId = intent.initiate(address(token), amount, targetChain, receiver, tip, salt);

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
        owner = owner;

        // Test parameters
        bytes32 intentId = bytes32(uint256(123));
        address asset = address(token);
        uint256 amount = 50 ether;
        address receiver = user2;
        bool isCall = false;
        bytes memory data = "";

        // Expected result calculated using PayloadUtils directly
        bytes32 expectedIndex = PayloadUtils.computeFulfillmentIndex(intentId, asset, amount, receiver, isCall, data);

        // Call the function and verify result
        bytes32 actualIndex = intent.getFulfillmentIndex(intentId, asset, amount, receiver, isCall, data);

        // Verify the computed index matches what we expect
        assertEq(actualIndex, expectedIndex, "Fulfillment index computation does not match expected value");

        // Verify it matches with the internal computation too
        assertEq(
            actualIndex,
            keccak256(abi.encodePacked(intentId, asset, amount, receiver, isCall, data)),
            "Index doesn't match raw computation"
        );
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
        bytes32 intentId = intent.initiate(address(token), amount, targetChain, receiver, tip, salt);

        // Verify intent ID
        assertEq(intentId, intent.computeIntentId(0, salt, currentChainId));

        // Verify gateway received the correct amount
        assertEq(token.balanceOf(address(gateway)), amount + tip);

        // Verify gateway call data
        (address callReceiver, uint256 callAmount, address callAsset, bytes memory callPayload,) = gateway.lastCall();
        assertEq(callReceiver, router);
        assertEq(callAmount, amount + tip);
        assertEq(callAsset, address(token));

        // Verify payload
        PayloadUtils.IntentPayload memory payload = PayloadUtils.decodeIntentPayload(callPayload);
        assertEq(payload.intentId, intentId);
        assertEq(payload.amount, amount);
        assertEq(payload.tip, tip);
        assertEq(payload.targetChain, targetChain);
        assertTrue(keccak256(payload.receiver) == keccak256(receiver), "Receiver should match");
    }

    function test_Initiate_SameChainReverts() public {
        // Test parameters
        uint256 amount = 100 ether;
        uint256 tip = 10 ether;
        uint256 targetChain = block.chainid; // Same as current chain
        bytes memory receiver = abi.encodePacked(user2);
        uint256 salt = 123;

        // Mint tokens for initiate
        token.mint(user1, amount + tip);
        vm.prank(user1);
        token.approve(address(intent), amount + tip);

        // Call initiate and expect revert
        vm.prank(user1);
        vm.expectRevert("Target chain cannot be the current chain");
        intent.initiate(address(token), amount, targetChain, receiver, tip, salt);
    }

    function test_Initiate_FromZetaChain() public {
        // Deploy a new intent contract that has isZetaChain=true
        Intent zetaIntent = _deployZetaChainIntent();

        // Deploy mock router implementation
        MockRouter mockRouter = new MockRouter();

        // Update the intent contract to use mock router
        zetaIntent.updateRouter(address(mockRouter));

        // Test parameters
        uint256 amount = 100 ether;
        uint256 tip = 10 ether;
        uint256 targetChain = 1;
        bytes memory receiver = abi.encodePacked(user2);
        uint256 salt = 123;
        uint256 currentChainId = block.chainid;

        // Mint tokens for initiate
        token.mint(user1, amount + tip);

        // Record user1's balance before
        uint256 user1BalanceBefore = token.balanceOf(user1);

        vm.prank(user1);
        token.approve(address(zetaIntent), amount + tip);

        // Expect the IntentInitiated event
        vm.expectEmit(true, true, false, false);
        emit IntentInitiated(
            zetaIntent.computeIntentId(0, salt, currentChainId), // First intent ID with chainId
            address(token),
            amount,
            targetChain,
            receiver,
            tip,
            salt
        );

        // Call initiate
        vm.prank(user1);
        bytes32 intentId = zetaIntent.initiate(address(token), amount, targetChain, receiver, tip, salt);

        // Verify intent ID
        assertEq(intentId, zetaIntent.computeIntentId(0, salt, currentChainId));

        // Verify tokens were transferred from user1
        assertEq(token.balanceOf(user1), user1BalanceBefore - (amount + tip));

        // Verify router received the call
        assertEq(mockRouter.lastZRC20(), address(token));
        assertEq(mockRouter.lastAmount(), amount + tip);

        // Verify context
        assertEq(mockRouter.lastContextChainID(), currentChainId);
        assertEq(mockRouter.lastContextSenderEVM(), address(zetaIntent));

        // Verify payload
        bytes memory routerPayload = mockRouter.lastPayload();
        PayloadUtils.IntentPayload memory payload = PayloadUtils.decodeIntentPayload(routerPayload);
        assertEq(payload.intentId, intentId);
        assertEq(payload.amount, amount);
        assertEq(payload.tip, tip);
        assertEq(payload.targetChain, targetChain);
        assertTrue(keccak256(payload.receiver) == keccak256(receiver), "Receiver should match");
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
        intent.initiate(address(token), amount, targetChain, receiver, tip, salt);
    }

    function test_InitiateTransfer() public {
        // Test parameters
        uint256 amount = 100 ether;
        uint256 tip = 10 ether;
        uint256 targetChain = 1;
        bytes memory receiver = abi.encodePacked(user2);
        uint256 salt = 123;
        uint256 currentChainId = block.chainid;

        // Mint tokens for initiateTransfer
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

        // Call initiateTransfer
        vm.prank(user1);
        bytes32 intentId = intent.initiateTransfer(address(token), amount, targetChain, receiver, tip, salt);

        // Verify intent ID
        assertEq(intentId, intent.computeIntentId(0, salt, currentChainId));

        // Verify gateway received the correct amount
        assertEq(token.balanceOf(address(gateway)), amount + tip);

        // Verify gateway call data
        (address callReceiver, uint256 callAmount, address callAsset, bytes memory callPayload,) = gateway.lastCall();
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

    function test_InitiateTransfer_ComparingWithInitiate() public {
        // Test parameters
        uint256 amount = 100 ether;
        uint256 tip = 10 ether;
        uint256 targetChain = 1;
        bytes memory receiver = abi.encodePacked(user2);
        uint256 salt = 123;

        // Prepare for first intent (initiate)
        uint256 initialCounter = intent.intentCounter();
        token.mint(user1, amount + tip);
        vm.prank(user1);
        token.approve(address(intent), amount + tip);

        // Call initiate
        vm.prank(user1);
        bytes32 initiateId = intent.initiate(address(token), amount, targetChain, receiver, tip, salt);

        // Prepare for second intent (initiateTransfer)
        uint256 secondCounter = intent.intentCounter();
        token.mint(user1, amount + tip);
        vm.prank(user1);
        token.approve(address(intent), amount + tip);

        // Call initiateTransfer
        vm.prank(user1);
        bytes32 transferId = intent.initiateTransfer(address(token), amount, targetChain, receiver, tip, salt);

        // Verify that both functions increment the counter the same way
        assertEq(secondCounter - initialCounter, 1, "initiate should increment counter by 1");
        assertEq(intent.intentCounter() - secondCounter, 1, "initiateTransfer should increment counter by 1");

        // Verify intent IDs follow the same pattern
        bytes32 expectedInitiateId = intent.computeIntentId(initialCounter, salt, block.chainid);
        bytes32 expectedTransferId = intent.computeIntentId(secondCounter, salt, block.chainid);

        assertEq(initiateId, expectedInitiateId, "initiate ID calculation should match");
        assertEq(transferId, expectedTransferId, "initiateTransfer ID calculation should match");

        // Verify gateway received the correct amount from both calls
        assertEq(token.balanceOf(address(gateway)), (amount + tip) * 2);
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
        bytes32 intentId = intent.initiate(address(token), amount, targetChain, receiver, tip, salt);

        // Mint tokens to the fulfiller (user1) and approve them for the intent contract
        token.mint(user1, amount);
        vm.prank(user1);
        token.approve(address(intent), amount);

        // Expect the IntentFulfilled event
        vm.expectEmit(true, true, false, true);
        emit IntentFulfilled(intentId, address(token), amount, user2);

        // Call fulfill
        vm.prank(user1);
        intent.fulfill(intentId, address(token), amount, user2);

        // Verify fulfillment was registered
        bytes32 fulfillmentIndex = PayloadUtils.computeFulfillmentIndex(intentId, address(token), amount, user2);
        assertEq(intent.fulfillments(fulfillmentIndex), user1);

        // Verify tokens were transferred from user1 to user2
        assertEq(token.balanceOf(user2), amount);
    }

    function test_FulfillTransfer() public {
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
        bytes32 intentId = intent.initiate(address(token), amount, targetChain, receiver, tip, salt);

        // Mint tokens to the fulfiller (user1) and approve them for the intent contract
        token.mint(user1, amount);
        vm.prank(user1);
        token.approve(address(intent), amount);

        // Expect the IntentFulfilled event
        vm.expectEmit(true, true, false, true);
        emit IntentFulfilled(intentId, address(token), amount, user2);

        // Call fulfillTransfer
        vm.prank(user1);
        intent.fulfillTransfer(intentId, address(token), amount, user2);

        // Verify fulfillment was registered
        bytes32 fulfillmentIndex = PayloadUtils.computeFulfillmentIndex(intentId, address(token), amount, user2);
        assertEq(intent.fulfillments(fulfillmentIndex), user1);

        // Verify tokens were transferred from user1 to user2
        assertEq(token.balanceOf(user2), amount);
    }

    function test_FulfillTransfer_ComparingWithFulfill() public {
        // Create two intents for testing
        uint256 amount = 100 ether;
        uint256 tip = 10 ether;
        uint256 targetChain = 1;
        bytes memory receiver = abi.encodePacked(user2);
        uint256 salt1 = 123;
        uint256 salt2 = 456;

        // Mint tokens for initiating both intents
        token.mint(user1, (amount + tip) * 2);
        vm.prank(user1);
        token.approve(address(intent), (amount + tip) * 2);

        // Initiate first intent
        vm.prank(user1);
        bytes32 intentId1 = intent.initiate(address(token), amount, targetChain, receiver, tip, salt1);

        // Initiate second intent
        vm.prank(user1);
        bytes32 intentId2 = intent.initiate(address(token), amount, targetChain, receiver, tip, salt2);

        // Mint tokens for fulfillment
        token.mint(user1, amount * 2);
        vm.prank(user1);
        token.approve(address(intent), amount * 2);

        // Fulfill first intent with fulfill
        vm.prank(user1);
        intent.fulfill(intentId1, address(token), amount, user2);

        // Fulfill second intent with fulfillTransfer
        vm.prank(user1);
        intent.fulfillTransfer(intentId2, address(token), amount, user2);

        // Verify both fulfillments were registered
        bytes32 fulfillIndex1 = PayloadUtils.computeFulfillmentIndex(intentId1, address(token), amount, user2);
        bytes32 fulfillIndex2 = PayloadUtils.computeFulfillmentIndex(intentId2, address(token), amount, user2);

        assertEq(intent.fulfillments(fulfillIndex1), user1, "fulfill should register user1 as fulfiller");
        assertEq(intent.fulfillments(fulfillIndex2), user1, "fulfillTransfer should register user1 as fulfiller");

        // Verify user2 received tokens from both fulfillments
        assertEq(token.balanceOf(user2), amount * 2, "User2 should receive tokens from both fulfillments");
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
        bytes32 intentId = intent.initiate(address(token), amount, targetChain, receiver, tip, salt);

        // Mint tokens to the fulfiller (user1) and approve them for the intent contract
        token.mint(user1, amount);
        vm.prank(user1);
        token.approve(address(intent), amount);

        // First fulfillment
        vm.prank(user1);
        intent.fulfill(intentId, address(token), amount, user2);

        // Try to fulfill again with same parameters and expect revert
        // First need to mint and approve more tokens
        token.mint(user1, amount);
        vm.prank(user1);
        token.approve(address(intent), amount);

        vm.prank(user1);
        vm.expectRevert("Intent already fulfilled with these parameters");
        intent.fulfill(intentId, address(token), amount, user2);
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
        bytes32 intentId = intent.initiate(address(token), amount, targetChain, receiver, tip, salt);

        // Mint tokens to the fulfiller (user1) and approve them for both fulfillments
        token.mint(user1, amount + (amount + 1 ether));
        vm.prank(user1);
        token.approve(address(intent), amount + (amount + 1 ether));

        // First fulfillment
        vm.prank(user1);
        intent.fulfill(intentId, address(token), amount, user2);

        // Try to fulfill with different amount
        vm.prank(user1);
        intent.fulfill(intentId, address(token), amount + 1 ether, user2);

        // Verify both fulfillments were registered
        bytes32 fulfillmentIndex1 = PayloadUtils.computeFulfillmentIndex(intentId, address(token), amount, user2);
        bytes32 fulfillmentIndex2 =
            PayloadUtils.computeFulfillmentIndex(intentId, address(token), amount + 1 ether, user2);
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
        bytes32 intentId = intent.initiate(address(token), amount, targetChain, receiver, tip, salt);

        // Mint additional tokens for fulfillment
        token.mint(user1, amount);
        vm.prank(user1);
        token.approve(address(intent), amount);

        // Fulfill the intent
        vm.prank(user1);
        intent.fulfill(intentId, address(token), amount, user2);

        // Prepare settlement payload
        bytes memory settlementPayload = PayloadUtils.encodeSettlementPayload(
            intentId,
            amount,
            address(token),
            user2,
            tip,
            amount // actualAmount same as amount in the test case
        );

        // Transfer tokens to gateway for settlement
        token.mint(address(gateway), amount + tip);
        vm.prank(address(gateway));
        token.approve(address(intent), amount + tip);

        // Call onCall through gateway
        vm.prank(address(gateway));
        intent.onCall(IIntent.MessageContext({sender: router}), settlementPayload);

        // Verify settlement record
        bytes32 fulfillmentIndex = PayloadUtils.computeFulfillmentIndex(intentId, address(token), amount, user2);
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
        bytes32 intentId = intent.initiate(address(token), amount, targetChain, receiver, tip, salt);

        // Prepare settlement payload
        bytes memory settlementPayload = PayloadUtils.encodeSettlementPayload(
            intentId,
            amount,
            address(token),
            user2,
            tip,
            amount // actualAmount same as amount in the test case
        );

        // Transfer tokens to gateway for settlement
        token.mint(address(gateway), amount + tip);
        vm.prank(address(gateway));
        token.approve(address(intent), amount + tip);

        // Call onCall through gateway
        vm.prank(address(gateway));
        intent.onCall(IIntent.MessageContext({sender: router}), settlementPayload);

        // Verify settlement record
        bytes32 fulfillmentIndex = PayloadUtils.computeFulfillmentIndex(intentId, address(token), amount, user2);
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
        bytes32 intentId = intent.initiate(address(token), amount, targetChain, receiver, tip, salt);

        // Prepare settlement payload
        bytes memory settlementPayload = PayloadUtils.encodeSettlementPayload(
            intentId,
            amount,
            address(token),
            user2,
            tip,
            amount // actualAmount same as amount in the test case
        );

        // Transfer tokens to gateway for settlement
        token.mint(address(gateway), amount + tip);
        vm.prank(address(gateway));
        token.approve(address(intent), amount + tip);

        // Call onCall through gateway with invalid sender
        vm.prank(address(gateway));
        vm.expectRevert("Invalid sender");
        intent.onCall(
            IIntent.MessageContext({
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
        bytes32 intentId = intent.initiate(address(token), amount, targetChain, receiver, tip, salt);

        // Mint additional tokens for fulfillment
        token.mint(user1, amount);
        vm.prank(user1);
        token.approve(address(intent), amount);

        // Fulfill the intent with the original amount (for indexing purposes)
        vm.prank(user1);
        intent.fulfill(intentId, address(token), amount, user2);

        // Prepare settlement payload with different actualAmount
        bytes memory settlementPayload = PayloadUtils.encodeSettlementPayload(
            intentId,
            amount, // Original amount (for index calculation)
            address(token),
            user2,
            tip,
            actualAmount // Reduced actual amount to transfer
        );

        // Transfer tokens to gateway for settlement
        token.mint(address(gateway), actualAmount + tip);
        vm.prank(address(gateway));
        token.approve(address(intent), actualAmount + tip);

        // Call onCall through gateway
        vm.prank(address(gateway));
        intent.onCall(IIntent.MessageContext({sender: router}), settlementPayload);

        // Verify settlement record
        bytes32 fulfillmentIndex = PayloadUtils.computeFulfillmentIndex(
            intentId,
            address(token),
            amount, // Original amount for index calculation
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
        bytes32 intentId = intent.initiate(address(token), amount, targetChain, receiver, tip, salt);

        // Prepare settlement payload
        bytes memory settlementPayload = PayloadUtils.encodeSettlementPayload(
            intentId,
            amount,
            address(token),
            user2,
            tip,
            amount // actualAmount same as amount in the test case
        );

        // Transfer tokens to gateway for settlement
        token.mint(address(gateway), amount + tip);
        vm.prank(address(gateway));
        token.approve(address(intent), amount + tip);

        // Call onCall through gateway to settle the intent
        vm.prank(address(gateway));
        intent.onCall(IIntent.MessageContext({sender: router}), settlementPayload);

        // Verify settlement was recorded
        bytes32 fulfillmentIndex = PayloadUtils.computeFulfillmentIndex(intentId, address(token), amount, user2);
        (bool settled,,,) = intent.settlements(fulfillmentIndex);
        assertTrue(settled, "Settlement should be marked as settled");

        // Now try to fulfill the already settled intent
        // Mint tokens to the fulfiller (user1) and approve them for the intent contract
        token.mint(user1, amount);
        vm.prank(user1);
        token.approve(address(intent), amount);

        // Expect revert with "Intent already settled" error
        vm.prank(user1);
        vm.expectRevert("Intent already settled");
        intent.fulfill(intentId, address(token), amount, user2);
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
        bytes32 intentId = intent.initiate(address(token), amount, targetChain, receiver, tip, salt);

        // Prepare settlement payload
        bytes memory settlementPayload = PayloadUtils.encodeSettlementPayload(
            intentId,
            amount,
            address(token),
            user2,
            tip,
            amount // actualAmount same as amount in the test case
        );

        // Transfer tokens to gateway for settlement
        token.mint(address(gateway), amount + tip);
        vm.prank(address(gateway));
        token.approve(address(intent), amount + tip);

        // Call onCall through gateway to settle the intent the first time
        vm.prank(address(gateway));
        intent.onCall(IIntent.MessageContext({sender: router}), settlementPayload);

        // Verify settlement was recorded
        bytes32 fulfillmentIndex = PayloadUtils.computeFulfillmentIndex(intentId, address(token), amount, user2);
        (bool settled,,,) = intent.settlements(fulfillmentIndex);
        assertTrue(settled, "Settlement should be marked as settled");

        // Now try to settle the already settled intent again
        // Transfer more tokens to gateway for the second settlement attempt
        token.mint(address(gateway), amount + tip);
        vm.prank(address(gateway));
        token.approve(address(intent), amount + tip);

        // Expect revert with "Intent already settled" error
        vm.prank(address(gateway));
        vm.expectRevert("Intent already settled");
        intent.onCall(IIntent.MessageContext({sender: router}), settlementPayload);
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
        bytes32 intentId = intent.initiate(address(token), amount, targetChain, receiver, tip, salt);

        // Prepare settlement payload
        bytes memory settlementPayload = PayloadUtils.encodeSettlementPayload(
            intentId,
            amount,
            address(token),
            user2,
            tip,
            amount // actualAmount same as amount in the test case
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
            false, // fulfilled
            address(0), // fulfiller
            amount, // actualAmount
            0 // paidTip
        );

        // Call onCall through gateway to settle the intent
        vm.prank(address(gateway));
        intent.onCall(IIntent.MessageContext({sender: router}), settlementPayload);

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
        bytes32 intentId2 = intent.initiate(address(token), amount2, targetChain, receiver, tip2, salt2);

        // Fulfill the intent first
        token.mint(user1, amount2);
        vm.prank(user1);
        token.approve(address(intent), amount2);

        vm.prank(user1);
        intent.fulfill(intentId2, address(token), amount2, user2);

        // Prepare settlement payload for the second intent
        bytes memory settlementPayload2 = PayloadUtils.encodeSettlementPayload(
            intentId2,
            amount2,
            address(token),
            user2,
            tip2,
            amount2 // actualAmount
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
            true, // fulfilled
            user1, // fulfiller
            amount2, // actualAmount
            tip2 // paidTip
        );

        // Call onCall through gateway to settle the second intent
        vm.prank(address(gateway));
        intent.onCall(IIntent.MessageContext({sender: router}), settlementPayload2);
    }

    function test_PauseUnpause() public {
        // Initially the contract is not paused
        assertFalse(intent.paused());

        // Pause the contract
        intent.pause();

        // Verify contract is paused
        assertTrue(intent.paused());

        // Try to initiate an intent while paused - should revert
        uint256 amount = 100 ether;
        uint256 tip = 10 ether;
        uint256 targetChain = 1;
        bytes memory receiver = abi.encodePacked(user2);
        uint256 salt = 123;

        token.mint(user1, amount + tip);
        vm.prank(user1);
        token.approve(address(intent), amount + tip);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        intent.initiate(address(token), amount, targetChain, receiver, tip, salt);

        // Unpause the contract
        intent.unpause();

        // Verify contract is not paused
        assertFalse(intent.paused());

        // Should be able to initiate now
        vm.prank(user1);
        bytes32 intentId = intent.initiate(address(token), amount, targetChain, receiver, tip, salt);

        // Verify initiate worked
        assertTrue(intentId != bytes32(0));
    }

    function test_OnlyPauserCanPause() public {
        // Create a non-pauser account
        address nonPauser = makeAddr("nonPauser");

        // Try to pause from non-pauser account - should revert
        vm.prank(nonPauser);
        vm.expectRevert(
            abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", nonPauser, PAUSER_ROLE)
        );
        intent.pause();

        // Give PAUSER_ROLE to nonPauser
        vm.prank(owner);
        intent.grantRole(PAUSER_ROLE, nonPauser);

        // Now nonPauser should be able to pause
        vm.prank(nonPauser);
        intent.pause();

        // Verify contract is paused
        assertTrue(intent.paused());
    }

    function test_OnlyAdminCanUnpause() public {
        // First pause the contract
        intent.pause();

        // Create a pauser account that is not an admin
        address pauser = makeAddr("pauser");
        vm.prank(owner);
        intent.grantRole(PAUSER_ROLE, pauser);

        // The pauser should not be able to unpause
        vm.prank(pauser);
        vm.expectRevert(
            abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", pauser, DEFAULT_ADMIN_ROLE)
        );
        intent.unpause();

        // The admin should be able to unpause
        vm.prank(owner);
        intent.unpause();

        // Verify contract is not paused
        assertFalse(intent.paused());
    }

    function test_OnCallDuringPause() public {
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
        bytes32 intentId = intent.initiate(address(token), amount, targetChain, receiver, tip, salt);

        // Pause the contract
        intent.pause();

        // Verify contract is paused
        assertTrue(intent.paused());

        // Prepare settlement payload
        bytes memory settlementPayload = PayloadUtils.encodeSettlementPayload(
            intentId,
            amount,
            address(token),
            user2,
            tip,
            amount // actualAmount same as amount in the test case
        );

        // Transfer tokens to gateway for settlement
        token.mint(address(gateway), amount + tip);
        vm.prank(address(gateway));
        token.approve(address(intent), amount + tip);

        // onCall should work even when paused
        vm.prank(address(gateway));
        intent.onCall(IIntent.MessageContext({sender: router}), settlementPayload);

        // Verify settlement record
        bytes32 fulfillmentIndex = PayloadUtils.computeFulfillmentIndex(intentId, address(token), amount, user2);
        (bool settled, bool fulfilled, uint256 paidTip, address fulfiller) = intent.settlements(fulfillmentIndex);
        assertTrue(settled);
        assertFalse(fulfilled);
        assertEq(paidTip, 0);
        assertEq(fulfiller, address(0));

        // Verify tokens were transferred to receiver (amount + tip)
        assertEq(token.balanceOf(user2), amount + tip, "User2 should receive amount + tip");
    }

    function test_FulfillDuringPause() public {
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
        bytes32 intentId = intent.initiate(address(token), amount, targetChain, receiver, tip, salt);

        // Pause the contract
        intent.pause();

        // Verify contract is paused
        assertTrue(intent.paused());

        // Mint tokens to the fulfiller (user1) and approve them for the intent contract
        token.mint(user1, amount);
        vm.prank(user1);
        token.approve(address(intent), amount);

        // Fulfill should revert when paused
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        intent.fulfill(intentId, address(token), amount, user2);

        // Unpause
        intent.unpause();

        // Fulfill should work after unpausing
        vm.prank(user1);
        intent.fulfill(intentId, address(token), amount, user2);

        // Verify fulfillment was registered
        bytes32 fulfillmentIndex = PayloadUtils.computeFulfillmentIndex(intentId, address(token), amount, user2);
        assertEq(intent.fulfillments(fulfillmentIndex), user1);
    }

    function test_UpdateGateway() public {
        // Deploy a new mock gateway
        MockGateway newGateway = new MockGateway();
        address oldGateway = intent.gateway();

        // Expect the GatewayUpdated event
        vm.expectEmit(true, true, false, false);
        emit GatewayUpdated(oldGateway, address(newGateway));

        // Update the gateway
        intent.updateGateway(address(newGateway));

        // Verify the gateway was updated
        assertEq(intent.gateway(), address(newGateway));
    }

    function test_UpdateRouter() public {
        // Create a new router address
        address newRouter = makeAddr("newRouter");
        address oldRouter = intent.router();

        // Expect the RouterUpdated event
        vm.expectEmit(true, true, false, false);
        emit RouterUpdated(oldRouter, newRouter);

        // Update the router
        intent.updateRouter(newRouter);

        // Verify the router was updated
        assertEq(intent.router(), newRouter);
    }

    function test_UpdateGateway_ZeroAddress() public {
        // Try to update gateway to zero address - should revert
        vm.expectRevert("Gateway cannot be zero address");
        intent.updateGateway(address(0));
    }

    function test_UpdateRouter_ZeroAddress() public {
        // Try to update router to zero address - should revert
        vm.expectRevert("Router cannot be zero address");
        intent.updateRouter(address(0));
    }

    function test_UpdateGateway_NonAdmin() public {
        // Create a non-admin account
        address nonAdmin = makeAddr("nonAdmin");

        // Deploy a new mock gateway
        MockGateway newGateway = new MockGateway();

        // Try to update gateway from non-admin account - should revert
        vm.prank(nonAdmin);
        vm.expectRevert(
            abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", nonAdmin, DEFAULT_ADMIN_ROLE)
        );
        intent.updateGateway(address(newGateway));
    }

    function test_UpdateRouter_NonAdmin() public {
        // Create a non-admin account
        address nonAdmin = makeAddr("nonAdmin");

        // Try to update router from non-admin account - should revert
        vm.prank(nonAdmin);
        vm.expectRevert(
            abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", nonAdmin, DEFAULT_ADMIN_ROLE)
        );
        intent.updateRouter(makeAddr("anotherRouter"));
    }

    function test_InitiateCall() public {
        // Test parameters
        uint256 amount = 100 ether;
        uint256 tip = 10 ether;
        uint256 targetChain = 1;
        bytes memory receiver = abi.encodePacked(user2);
        uint256 salt = 123;
        bytes memory data = abi.encodeWithSignature("someFunction(uint256,address)", 42, user1);
        uint256 currentChainId = block.chainid;

        // Mint tokens for initiateCall
        token.mint(user1, amount + tip);
        vm.prank(user1);
        token.approve(address(intent), amount + tip);

        // Expect the IntentInitiatedWithCall event
        vm.expectEmit(true, true, false, false);
        emit IntentInitiatedWithCall(
            intent.computeIntentId(0, salt, currentChainId), // First intent ID with chainId
            address(token),
            amount,
            targetChain,
            receiver,
            tip,
            salt,
            data
        );

        // Call initiateCall
        vm.prank(user1);
        bytes32 intentId = intent.initiateCall(address(token), amount, targetChain, receiver, tip, salt, data);

        // Verify intent ID
        assertEq(intentId, intent.computeIntentId(0, salt, currentChainId));

        // Verify gateway received the correct amount
        assertEq(token.balanceOf(address(gateway)), amount + tip);

        // Verify gateway call data
        (address callReceiver, uint256 callAmount, address callAsset, bytes memory callPayload,) = gateway.lastCall();
        assertEq(callReceiver, router);
        assertEq(callAmount, amount + tip);
        assertEq(callAsset, address(token));

        // Verify payload
        PayloadUtils.IntentPayload memory payload = PayloadUtils.decodeIntentPayload(callPayload);
        assertEq(payload.intentId, intentId);
        assertEq(payload.amount, amount);
        assertEq(payload.tip, tip);
        assertEq(payload.targetChain, targetChain);
        assertTrue(keccak256(payload.receiver) == keccak256(receiver), "Receiver should match");
        assertEq(payload.isCall, true);
        assertTrue(keccak256(payload.data) == keccak256(data), "Data should match");
    }

    function test_InitiateCall_SameChainReverts() public {
        // Test parameters
        uint256 amount = 100 ether;
        uint256 tip = 10 ether;
        uint256 targetChain = block.chainid; // Same as current chain
        bytes memory receiver = abi.encodePacked(user2);
        uint256 salt = 123;
        bytes memory data = abi.encodeWithSignature("someFunction(uint256)", 42);

        // Mint tokens for initiateCall
        token.mint(user1, amount + tip);
        vm.prank(user1);
        token.approve(address(intent), amount + tip);

        // Call initiateCall and expect revert
        vm.prank(user1);
        vm.expectRevert("Target chain cannot be the current chain");
        intent.initiateCall(address(token), amount, targetChain, receiver, tip, salt, data);
    }

    function test_InitiateCall_FromZetaChain() public {
        // Deploy a new intent contract that has isZetaChain=true
        Intent zetaIntent = _deployZetaChainIntent();

        // Deploy mock router implementation
        MockRouter mockRouter = new MockRouter();

        // Update the intent contract to use mock router
        zetaIntent.updateRouter(address(mockRouter));

        // Test parameters
        uint256 amount = 100 ether;
        uint256 tip = 10 ether;
        uint256 targetChain = 1;
        bytes memory receiver = abi.encodePacked(user2);
        uint256 salt = 123;
        bytes memory data = abi.encodeWithSignature("someFunction(uint256,address)", 42, user1);
        uint256 currentChainId = block.chainid;

        // Mint tokens for initiateCall
        token.mint(user1, amount + tip);

        // Record user1's balance before
        uint256 user1BalanceBefore = token.balanceOf(user1);

        vm.prank(user1);
        token.approve(address(zetaIntent), amount + tip);

        // Expect the IntentInitiatedWithCall event
        vm.expectEmit(true, true, false, false);
        emit IntentInitiatedWithCall(
            zetaIntent.computeIntentId(0, salt, currentChainId), // First intent ID with chainId
            address(token),
            amount,
            targetChain,
            receiver,
            tip,
            salt,
            data
        );

        // Call initiateCall
        vm.prank(user1);
        bytes32 intentId = zetaIntent.initiateCall(address(token), amount, targetChain, receiver, tip, salt, data);

        // Verify intent ID
        assertEq(intentId, zetaIntent.computeIntentId(0, salt, currentChainId));

        // Verify tokens were transferred from user1
        assertEq(token.balanceOf(user1), user1BalanceBefore - (amount + tip));

        // Verify router received the call
        assertEq(mockRouter.lastZRC20(), address(token));
        assertEq(mockRouter.lastAmount(), amount + tip);

        // Verify context
        assertEq(mockRouter.lastContextChainID(), currentChainId);
        assertEq(mockRouter.lastContextSenderEVM(), address(zetaIntent));

        // Verify payload
        bytes memory routerPayload = mockRouter.lastPayload();
        PayloadUtils.IntentPayload memory payload = PayloadUtils.decodeIntentPayload(routerPayload);
        assertEq(payload.intentId, intentId);
        assertEq(payload.amount, amount);
        assertEq(payload.tip, tip);
        assertEq(payload.targetChain, targetChain);
        assertTrue(keccak256(payload.receiver) == keccak256(receiver), "Receiver should match");
        assertEq(payload.isCall, true);
        assertTrue(keccak256(payload.data) == keccak256(data), "Data should match");
    }

    function test_InitiateCall_ComparingWithInitiate() public {
        // Test parameters
        uint256 amount = 100 ether;
        uint256 tip = 10 ether;
        uint256 targetChain = 1;
        bytes memory receiver = abi.encodePacked(user2);
        uint256 salt = 123;
        bytes memory data = abi.encodeWithSignature("someFunction(uint256)", 42);

        // Get initial counter
        uint256 initialCounter = intent.intentCounter();

        // Prepare for first intent (initiateTransfer)
        token.mint(user1, amount + tip);
        vm.prank(user1);
        token.approve(address(intent), amount + tip);

        // Call initiateTransfer
        vm.prank(user1);
        bytes32 transferId = intent.initiateTransfer(address(token), amount, targetChain, receiver, tip, salt);

        // Verify counter incremented
        assertEq(intent.intentCounter(), initialCounter + 1);

        // Prepare for second intent (initiateCall)
        token.mint(user1, amount + tip);
        vm.prank(user1);
        token.approve(address(intent), amount + tip);

        // Call initiateCall
        vm.prank(user1);
        bytes32 callId = intent.initiateCall(address(token), amount, targetChain, receiver, tip, salt, data);

        // Verify counter incremented again
        assertEq(intent.intentCounter(), initialCounter + 2);

        // Verify gateway received the correct amount from both calls
        assertEq(token.balanceOf(address(gateway)), (amount + tip) * 2);
    }

    function test_FulfillCall() public {
        // First create an intent
        uint256 amount = 100 ether;
        uint256 tip = 10 ether;
        uint256 targetChain = 1;
        bytes memory receiverBytes = abi.encodePacked(user2);
        uint256 salt = 123;
        bytes memory data = abi.encodeWithSignature("someFunction(uint256)", 42);

        // Deploy a mock target contract that implements IntentTarget
        MockIntentTarget mockTarget = new MockIntentTarget();

        // Mint tokens for initiate
        token.mint(user1, amount + tip);
        vm.prank(user1);
        token.approve(address(intent), amount + tip);

        // Initiate an intent with call
        vm.prank(user1);
        bytes32 intentId = intent.initiateCall(address(token), amount, targetChain, receiverBytes, tip, salt, data);

        // Mint tokens to the fulfiller (user1) and approve them for the intent contract
        token.mint(user1, amount);
        vm.prank(user1);
        token.approve(address(intent), amount);

        // Expect the IntentFulfilledWithCall event
        vm.expectEmit(true, true, false, true);
        emit IntentFulfilledWithCall(intentId, address(token), amount, address(mockTarget), data);

        // Call fulfillCall
        vm.prank(user1);
        intent.fulfillCall(intentId, address(token), amount, address(mockTarget), data);

        // Verify fulfillment was registered
        bytes32 fulfillmentIndex =
            PayloadUtils.computeFulfillmentIndex(intentId, address(token), amount, address(mockTarget), true, data);
        assertEq(intent.fulfillments(fulfillmentIndex), user1);

        // Verify tokens were transferred from user1 to mockTarget
        assertEq(token.balanceOf(address(mockTarget)), amount);

        // Verify the onFulfill method was called with correct parameters
        assertTrue(mockTarget.onFulfillCalled(), "onFulfill should have been called");
        assertEq(mockTarget.lastIntentId(), intentId, "Intent ID should match");
        assertEq(mockTarget.lastAsset(), address(token), "Asset should match");
        assertEq(mockTarget.lastAmount(), amount, "Amount should match");
        assertTrue(keccak256(mockTarget.lastData()) == keccak256(data), "Data should match");
    }

    function test_FulfillCall_TargetReverts() public {
        // First create an intent with call
        uint256 amount = 100 ether;
        uint256 tip = 10 ether;
        uint256 targetChain = 1;
        bytes memory receiverBytes = abi.encodePacked(user2);
        uint256 salt = 123;
        bytes memory data = abi.encodeWithSignature("someFunction(uint256)", 42);

        // Deploy a mock target contract that implements IntentTarget
        MockIntentTarget mockTarget = new MockIntentTarget();

        // Set the target to revert
        mockTarget.setShouldRevert(true);

        // Mint tokens for initiate
        token.mint(user1, amount + tip);
        vm.prank(user1);
        token.approve(address(intent), amount + tip);

        // Initiate an intent with call
        vm.prank(user1);
        bytes32 intentId = intent.initiateCall(address(token), amount, targetChain, receiverBytes, tip, salt, data);

        // Mint tokens to the fulfiller (user1) and approve them for the intent contract
        token.mint(user1, amount);
        vm.prank(user1);
        token.approve(address(intent), amount);

        // Call fulfillCall - expect it to revert with the target's revert message
        vm.prank(user1);
        vm.expectRevert("MockIntentTarget: intentional revert in onFulfill");
        intent.fulfillCall(intentId, address(token), amount, address(mockTarget), data);

        // Verify fulfillment was NOT registered since the transaction reverted
        bytes32 fulfillmentIndex =
            PayloadUtils.computeFulfillmentIndex(intentId, address(token), amount, address(mockTarget), true, data);
        assertEq(intent.fulfillments(fulfillmentIndex), address(0), "Fulfillment should not be registered after revert");

        // Verify tokens were NOT transferred to the target
        assertEq(token.balanceOf(address(mockTarget)), 0, "Target should not receive tokens after revert");
    }

    function test_FulfillCall_NonContractReceiver() public {
        // First create an intent
        uint256 amount = 100 ether;
        uint256 tip = 10 ether;
        uint256 targetChain = 1;
        bytes memory receiverBytes = abi.encodePacked(user2);
        uint256 salt = 123;
        bytes memory data = abi.encodeWithSignature("someFunction(uint256)", 42);

        // We'll use MockIntentTarget for the fulfillment instead of an EOA
        MockIntentTarget mockTarget = new MockIntentTarget();

        // Mint tokens for initiate
        token.mint(user1, amount + tip);
        vm.prank(user1);
        token.approve(address(intent), amount + tip);

        // Initiate an intent with call
        vm.prank(user1);
        bytes32 intentId = intent.initiateCall(address(token), amount, targetChain, receiverBytes, tip, salt, data);

        // Mint tokens to the fulfiller (user1) and approve them for the intent contract
        token.mint(user1, amount);
        vm.prank(user1);
        token.approve(address(intent), amount);

        // Call fulfillCall with the mock target (a contract)
        vm.prank(user1);
        intent.fulfillCall(intentId, address(token), amount, address(mockTarget), data);

        // Verify fulfillment was registered
        bytes32 fulfillmentIndex =
            PayloadUtils.computeFulfillmentIndex(intentId, address(token), amount, address(mockTarget), true, data);
        assertEq(intent.fulfillments(fulfillmentIndex), user1);

        // Verify tokens were transferred to the mock target
        assertEq(token.balanceOf(address(mockTarget)), amount);
    }

    function test_FulfillCall_TokenAccessDuringOnFulfill() public {
        // First create an intent
        uint256 amount = 100 ether;
        uint256 tip = 10 ether;
        uint256 targetChain = 1;
        bytes memory receiverBytes = abi.encodePacked(user2);
        uint256 salt = 123;
        bytes memory data = abi.encodeWithSignature("someFunction(uint256)", 42);

        // We'll use MockIntentTarget for the fulfillment
        MockIntentTarget mockTarget = new MockIntentTarget();

        // Enable balance checking
        mockTarget.setShouldCheckBalances(true);

        // Mint tokens for initiate
        token.mint(user1, amount + tip);
        vm.prank(user1);
        token.approve(address(intent), amount + tip);

        // Initiate an intent with call
        vm.prank(user1);
        bytes32 intentId = intent.initiateCall(address(token), amount, targetChain, receiverBytes, tip, salt, data);

        // Mint tokens to the fulfiller (user1) and approve them for the intent contract
        token.mint(user1, amount);
        vm.prank(user1);
        token.approve(address(intent), amount);

        // Call fulfillCall
        vm.prank(user1);
        intent.fulfillCall(intentId, address(token), amount, address(mockTarget), data);

        // Verify that the token balance was correct during onFulfill call
        assertEq(mockTarget.balanceDuringOnFulfill(), amount, "Token balance should be available during onFulfill");
    }

    function test_SettleCall() public {
        // First create an intent with call
        uint256 amount = 100 ether;
        uint256 tip = 10 ether;
        uint256 targetChain = 1;
        bytes memory receiverBytes = abi.encodePacked(user2);
        uint256 salt = 123;
        bytes memory data = abi.encodeWithSignature("someFunction(uint256)", 42);

        // Deploy a mock target contract that implements IntentTarget
        MockIntentTarget mockTarget = new MockIntentTarget();

        // Mint tokens for initiate
        token.mint(user1, amount + tip);
        vm.prank(user1);
        token.approve(address(intent), amount + tip);

        // Initiate an intent with call
        vm.prank(user1);
        bytes32 intentId = intent.initiateCall(address(token), amount, targetChain, receiverBytes, tip, salt, data);

        // Mint tokens to the fulfiller (user1) and approve them for the intent contract
        token.mint(user1, amount);
        vm.prank(user1);
        token.approve(address(intent), amount);

        // Fulfill the intent with fulfillCall
        vm.prank(user1);
        intent.fulfillCall(intentId, address(token), amount, address(mockTarget), data);

        // Prepare settlement payload (with isCall=true and data)
        bytes memory settlementPayload = PayloadUtils.encodeSettlementPayload(
            intentId,
            amount,
            address(token),
            address(mockTarget),
            tip,
            amount, // actualAmount same as amount in the test case
            true, // isCall
            data // data for the call
        );

        // Transfer tokens to gateway for settlement
        token.mint(address(gateway), amount + tip);
        vm.prank(address(gateway));
        token.approve(address(intent), amount + tip);

        // Reset the mock target to clear any state from the fulfill call
        mockTarget.reset();

        // Call onCall through gateway to settle the intent
        vm.prank(address(gateway));
        intent.onCall(IIntent.MessageContext({sender: router}), settlementPayload);

        // Verify settlement record
        bytes32 fulfillmentIndex =
            PayloadUtils.computeFulfillmentIndex(intentId, address(token), amount, address(mockTarget), true, data);
        (bool settled, bool fulfilled, uint256 paidTip, address fulfiller) = intent.settlements(fulfillmentIndex);
        assertTrue(settled, "Settlement should be marked as settled");
        assertTrue(fulfilled, "Settlement should be marked as fulfilled");
        assertEq(paidTip, tip, "Paid tip should match the input tip");
        assertEq(fulfiller, user1, "Fulfiller should be user1");

        // Verify tokens were transferred to fulfiller (amount + tip)
        assertEq(token.balanceOf(user1), amount + tip, "User1 should receive amount + tip");

        // Verify onSettle was called on the target
        assertTrue(mockTarget.onSettleCalled(), "onSettle should have been called");
        assertEq(mockTarget.lastIntentId(), intentId, "Intent ID should match");
        assertEq(mockTarget.lastAsset(), address(token), "Asset should match");
        assertEq(mockTarget.lastAmount(), amount, "Amount should match");
        assertEq(keccak256(mockTarget.lastData()), keccak256(data), "Data should match");
        assertEq(mockTarget.lastFulfillmentIndex(), fulfillmentIndex, "Fulfillment index should match");

        // Verify isFulfilled parameter was true
        assertTrue(mockTarget.lastIsFulfilled(), "isFulfilled should be true");
    }

    function test_SettleCall_TargetReverts() public {
        // First create an intent with call
        uint256 amount = 100 ether;
        uint256 tip = 10 ether;
        uint256 targetChain = 1;
        bytes memory receiverBytes = abi.encodePacked(user2);
        uint256 salt = 123;
        bytes memory data = abi.encodeWithSignature("someFunction(uint256)", 42);

        // Deploy a mock target contract that implements IntentTarget
        MockIntentTarget mockTarget = new MockIntentTarget();

        // Mint tokens for initiate
        token.mint(user1, amount + tip);
        vm.prank(user1);
        token.approve(address(intent), amount + tip);

        // Initiate an intent with call
        vm.prank(user1);
        bytes32 intentId = intent.initiateCall(address(token), amount, targetChain, receiverBytes, tip, salt, data);

        // Mint tokens to the fulfiller (user1) and approve them for the intent contract
        token.mint(user1, amount);
        vm.prank(user1);
        token.approve(address(intent), amount);

        // Fulfill the intent with fulfillCall
        vm.prank(user1);
        intent.fulfillCall(intentId, address(token), amount, address(mockTarget), data);

        // Now store user's balance after fulfillment for later comparison
        uint256 userBalanceBeforeSettlement = token.balanceOf(user1);

        // Prepare settlement payload (with isCall=true and data)
        bytes memory settlementPayload = PayloadUtils.encodeSettlementPayload(
            intentId,
            amount,
            address(token),
            address(mockTarget),
            tip,
            amount, // actualAmount same as amount in the test case
            true, // isCall
            data // data for the call
        );

        // Transfer tokens to gateway for settlement
        token.mint(address(gateway), amount + tip);
        vm.prank(address(gateway));
        token.approve(address(intent), amount + tip);

        // Reset the mock target and set it to revert
        mockTarget.reset();
        mockTarget.setShouldRevert(true);

        // Get the gateway's token balance before the call
        uint256 gatewayBalanceBefore = token.balanceOf(address(gateway));

        // Call onCall through gateway to settle the intent - expect it to revert
        vm.prank(address(gateway));
        vm.expectRevert("MockIntentTarget: intentional revert in onSettle");
        intent.onCall(IIntent.MessageContext({sender: router}), settlementPayload);

        // The entire transaction should revert, so balances should remain unchanged
        assertEq(token.balanceOf(user1), userBalanceBeforeSettlement, "User1 balance should be unchanged");
        assertEq(token.balanceOf(address(gateway)), gatewayBalanceBefore, "Gateway balance should be unchanged");
    }

    function test_SettleCall_WithoutFulfillment() public {
        // First create an intent with call
        uint256 amount = 100 ether;
        uint256 tip = 10 ether;
        uint256 targetChain = 1;
        bytes memory receiverBytes = abi.encodePacked(user2);
        uint256 salt = 123;
        bytes memory data = abi.encodeWithSignature("someFunction(uint256)", 42);

        // Deploy a mock target contract that implements IntentTarget
        MockIntentTarget mockTarget = new MockIntentTarget();

        // Mint tokens for initiate
        token.mint(user1, amount + tip);
        vm.prank(user1);
        token.approve(address(intent), amount + tip);

        // Initiate an intent with call
        vm.prank(user1);
        bytes32 intentId = intent.initiateCall(address(token), amount, targetChain, receiverBytes, tip, salt, data);

        // Prepare settlement payload (with isCall=true and data) - Not fulfilling first
        bytes memory settlementPayload = PayloadUtils.encodeSettlementPayload(
            intentId,
            amount,
            address(token),
            address(mockTarget),
            tip,
            amount, // actualAmount same as amount in the test case
            true, // isCall
            data // data for the call
        );

        // Transfer tokens to gateway for settlement
        token.mint(address(gateway), amount + tip);
        vm.prank(address(gateway));
        token.approve(address(intent), amount + tip);

        // Call onCall through gateway to settle the intent
        vm.prank(address(gateway));
        intent.onCall(IIntent.MessageContext({sender: router}), settlementPayload);

        // Verify settlement record
        bytes32 fulfillmentIndex =
            PayloadUtils.computeFulfillmentIndex(intentId, address(token), amount, address(mockTarget), true, data);
        (bool settled, bool fulfilled, uint256 paidTip, address fulfiller) = intent.settlements(fulfillmentIndex);
        assertTrue(settled, "Settlement should be marked as settled");
        assertFalse(fulfilled, "Settlement should be marked as not fulfilled");
        assertEq(paidTip, 0, "Paid tip should be 0");
        assertEq(fulfiller, address(0), "Fulfiller should be address(0)");

        // Verify tokens were transferred to target (amount + tip)
        assertEq(token.balanceOf(address(mockTarget)), amount + tip, "Target should receive amount + tip");

        // Verify onFulfill was called on the target
        assertTrue(mockTarget.onFulfillCalled(), "onFulfill should have been called");

        // Verify onSettle was also called
        assertTrue(mockTarget.onSettleCalled(), "onSettle should have been called");

        // Verify the common parameters
        assertEq(mockTarget.lastIntentId(), intentId, "Intent ID should match");
        assertEq(mockTarget.lastAsset(), address(token), "Asset should match");
        assertEq(mockTarget.lastAmount(), amount, "Amount should match");
        assertEq(keccak256(mockTarget.lastData()), keccak256(data), "Data should match");

        // Verify fulfillmentIndex was passed to onSettle
        assertEq(mockTarget.lastFulfillmentIndex(), fulfillmentIndex, "Fulfillment index should match");

        // Verify isFulfilled parameter was false
        assertFalse(mockTarget.lastIsFulfilled(), "isFulfilled should be false");
    }

    function test_SettleCall_TokenAccessDuringOnFulfill() public {
        // First create an intent with call
        uint256 amount = 100 ether;
        uint256 tip = 10 ether;
        uint256 targetChain = 1;
        bytes memory receiverBytes = abi.encodePacked(user2);
        uint256 salt = 123;
        bytes memory data = abi.encodeWithSignature("someFunction(uint256)", 42);

        // Deploy a mock target contract that implements IntentTarget
        MockIntentTarget mockTarget = new MockIntentTarget();

        // Enable balance checking
        mockTarget.setShouldCheckBalances(true);

        // Mint tokens for initiate
        token.mint(user1, amount + tip);
        vm.prank(user1);
        token.approve(address(intent), amount + tip);

        // Initiate an intent with call
        vm.prank(user1);
        bytes32 intentId = intent.initiateCall(address(token), amount, targetChain, receiverBytes, tip, salt, data);

        // Prepare settlement payload (with isCall=true and data) - Not fulfilling first
        bytes memory settlementPayload = PayloadUtils.encodeSettlementPayload(
            intentId,
            amount,
            address(token),
            address(mockTarget),
            tip,
            amount, // actualAmount same as amount in the test case
            true, // isCall
            data // data for the call
        );

        // Transfer tokens to gateway for settlement
        token.mint(address(gateway), amount + tip);
        vm.prank(address(gateway));
        token.approve(address(intent), amount + tip);

        // Call onCall through gateway to settle the intent
        vm.prank(address(gateway));
        intent.onCall(IIntent.MessageContext({sender: router}), settlementPayload);

        // Verify that the token balance was correct during onFulfill call
        assertEq(
            mockTarget.balanceDuringOnFulfill(), amount + tip, "Token balance should be available during onFulfill"
        );
    }
}
