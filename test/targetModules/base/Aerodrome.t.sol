// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test, console2} from "forge-std/Test.sol";
import {AerodromeModule} from "../../../src/targetModules/base/AerodromeModule.sol";
import {AerodromeInitiator} from "../../../src/targetModules/base/AerodromeInitiator.sol";
import {AerodromeSwapLib} from "../../../src/targetModules/base/AerodromeSwapLib.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {MockIntent} from "../../mocks/MockIntent.sol";

// Mock Aerodrome Router Interface for testing
interface IAerodromeRouter {
    struct Route {
        address from;
        address to;
        bool stable;
        address factory;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function getAmountsOut(uint256 amountIn, Route[] memory routes) external view returns (uint256[] memory amounts);
}

// Mock Aerodrome Router
contract MockAerodromeRouter {
    struct Route {
        address from;
        address to;
        bool stable;
        address factory;
    }

    // Keep track of the last swap
    uint256 public lastAmountIn;
    uint256 public lastAmountOutMin;
    address public lastReceiver;
    address public lastFactoryUsed;

    // Mock a 1:1 swap with 2% fee for testing purposes
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        // Save parameters for assertions
        lastAmountIn = amountIn;
        lastAmountOutMin = amountOutMin;
        lastReceiver = to;

        if (routes.length > 0) {
            lastFactoryUsed = routes[0].factory;

            // Transfer tokens
            IERC20(routes[0].from).transferFrom(msg.sender, address(this), amountIn);

            // Calculate output (98% to simulate fee)
            uint256 amountOut = amountIn * 98 / 100;
            require(amountOut >= amountOutMin, "Insufficient output amount");

            // Generate last token in path
            address lastToken = routes[routes.length - 1].to;
            MockERC20(lastToken).mint(to, amountOut);

            // Return amounts
            amounts = new uint256[](2);
            amounts[0] = amountIn;
            amounts[1] = amountOut;
            return amounts;
        }

        revert("Invalid routes");
    }

    function getAmountsOut(uint256 amountIn, Route[] memory routes) external pure returns (uint256[] memory amounts) {
        amounts = new uint256[](routes.length + 1);
        amounts[0] = amountIn;

        // Simulate a 2% fee on each hop
        uint256 currentAmount = amountIn;
        for (uint256 i = 0; i < routes.length; i++) {
            currentAmount = currentAmount * 98 / 100;
            amounts[i + 1] = currentAmount;
        }

        return amounts;
    }
}

// Mock Intent contract with token transfer functionality
contract MockIntentWithTransfer is MockIntent {
    function initiateCall(
        address asset,
        uint256 amount,
        uint256,
        bytes calldata,
        uint256 tip,
        uint256,
        bytes calldata,
        uint256
    ) external override returns (bytes32) {
        // Transfer tokens from sender to this contract
        IERC20(asset).transferFrom(msg.sender, address(this), amount + tip);
        return bytes32(uint256(1));
    }
}

contract AerodromeTest is Test {
    // Contracts to test
    AerodromeModule public aerodromeModule;
    AerodromeInitiator public aerodromeInitiator;

    // Mocks
    MockAerodromeRouter public mockRouter;
    MockIntentWithTransfer public mockIntent;
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    MockERC20 public tokenC;

    // Test addresses
    address public owner;
    address public user;
    address public poolFactory;

    // Constants
    uint256 public constant AMOUNT = 1000 ether;
    uint256 public constant MIN_AMOUNT_OUT = 950 ether;
    uint256 public constant TIP = 10 ether;
    uint256 public constant TARGET_CHAIN_ID = 8453; // Base chain ID

    // Set up the test environment
    function setUp() public {
        // Setup addresses
        owner = address(this);
        user = makeAddr("user");
        poolFactory = makeAddr("poolFactory");

        // Deploy mock contracts
        mockRouter = new MockAerodromeRouter();
        mockIntent = new MockIntentWithTransfer();

        // Deploy tokens
        tokenA = new MockERC20("Token A", "TKNA");
        tokenB = new MockERC20("Token B", "TKNB");
        tokenC = new MockERC20("Token C", "TKNC");

        // Mint tokens to user
        tokenA.mint(user, AMOUNT * 10);
        tokenB.mint(address(mockRouter), AMOUNT * 10);
        tokenC.mint(address(mockRouter), AMOUNT * 10);

        // Deploy module
        aerodromeModule = new AerodromeModule(address(mockRouter), poolFactory, address(mockIntent));

        // Deploy initiator
        aerodromeInitiator = new AerodromeInitiator(address(mockIntent), address(aerodromeModule), TARGET_CHAIN_ID);

        // Approve tokens
        vm.startPrank(user);
        tokenA.approve(address(aerodromeInitiator), type(uint256).max);
        vm.stopPrank();
    }

    // Test initialization parameters
    function test_Initialization() public {
        assertEq(aerodromeModule.aerodromeRouter(), address(mockRouter), "Router address mismatch");
        assertEq(aerodromeModule.poolFactory(), poolFactory, "Pool factory address mismatch");
        assertEq(aerodromeModule.intentContract(), address(mockIntent), "Intent contract address mismatch");
        assertEq(aerodromeModule.rewardPercentage(), 5, "Default reward percentage mismatch");

        assertEq(aerodromeInitiator.intent(), address(mockIntent), "Intent address mismatch");
        assertEq(aerodromeInitiator.targetModule(), address(aerodromeModule), "Target module address mismatch");
        assertEq(aerodromeInitiator.targetChainId(), TARGET_CHAIN_ID, "Target chain ID mismatch");
    }

    // Test setting addresses in the module contract
    function test_SetAddresses() public {
        address newRouter = makeAddr("newRouter");
        address newFactory = makeAddr("newFactory");
        address newIntent = makeAddr("newIntent");

        aerodromeModule.setAerodromeRouter(newRouter);
        aerodromeModule.setPoolFactory(newFactory);
        aerodromeModule.setIntentContract(newIntent);

        assertEq(aerodromeModule.aerodromeRouter(), newRouter, "New router address not set");
        assertEq(aerodromeModule.poolFactory(), newFactory, "New pool factory address not set");
        assertEq(aerodromeModule.intentContract(), newIntent, "New intent contract address not set");
    }

    // Test setting addresses in the initiator contract
    function test_SetInitiatorAddresses() public {
        address newIntent = makeAddr("newIntent");
        address newModule = makeAddr("newModule");
        uint256 newChainId = 1;

        aerodromeInitiator.setIntent(newIntent);
        aerodromeInitiator.setTargetModule(newModule);
        aerodromeInitiator.setTargetChainId(newChainId);

        assertEq(aerodromeInitiator.intent(), newIntent, "New intent address not set");
        assertEq(aerodromeInitiator.targetModule(), newModule, "New target module address not set");
        assertEq(aerodromeInitiator.targetChainId(), newChainId, "New target chain ID not set");
    }

    // Test setting reward percentage
    function test_SetRewardPercentage() public {
        uint256 newPercentage = 10;
        aerodromeModule.setRewardPercentage(newPercentage);
        assertEq(aerodromeModule.rewardPercentage(), newPercentage, "New reward percentage not set");
    }

    // Test setting invalid reward percentage (>100)
    function test_SetInvalidRewardPercentage() public {
        uint256 invalidPercentage = 101;
        vm.expectRevert("Percentage must be between 0-100");
        aerodromeModule.setRewardPercentage(invalidPercentage);
    }

    // Test AerodromeSwapLib encoding and decoding
    function test_SwapParamsEncoding() public {
        // Create test data
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        bool[] memory stableFlags = new bool[](1);
        stableFlags[0] = false;

        uint256 minAmountOut = MIN_AMOUNT_OUT;
        uint256 deadline = block.timestamp + 1 hours;
        address receiver = user;

        // Encode the data
        bytes memory encoded = AerodromeSwapLib.encodeSwapParams(path, stableFlags, minAmountOut, deadline, receiver);

        // Decode the data
        (
            address[] memory decodedPath,
            bool[] memory decodedFlags,
            uint256 decodedMinOut,
            uint256 decodedDeadline,
            address decodedReceiver
        ) = AerodromeSwapLib.decodeSwapParams(encoded);

        // Verify decoding
        assertEq(decodedPath.length, path.length, "Path length mismatch");
        assertEq(decodedPath[0], path[0], "Path[0] mismatch");
        assertEq(decodedPath[1], path[1], "Path[1] mismatch");

        assertEq(decodedFlags.length, stableFlags.length, "Flags length mismatch");
        assertEq(decodedFlags[0], stableFlags[0], "Flags[0] mismatch");

        assertEq(decodedMinOut, minAmountOut, "Min amount out mismatch");
        assertEq(decodedDeadline, deadline, "Deadline mismatch");
        assertEq(decodedReceiver, receiver, "Receiver mismatch");
    }

    // Test initiating a swap
    function test_InitiateAerodromeSwap() public {
        // Create test data
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        bool[] memory stableFlags = new bool[](1);
        stableFlags[0] = false;

        uint256 minAmountOut = MIN_AMOUNT_OUT;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 salt = 123;
        uint256 gasLimit = 300000;

        // Call the initiator
        vm.prank(user);
        bytes32 intentId = aerodromeInitiator.initiateAerodromeSwap(
            address(tokenA), AMOUNT, TIP, salt, gasLimit, path, stableFlags, minAmountOut, deadline, user
        );

        // Verify the intent was created
        assertFalse(intentId == bytes32(0), "Intent ID should not be zero");

        // Verify token transfer
        assertEq(tokenA.balanceOf(user), AMOUNT * 10 - AMOUNT - TIP, "Tokens not transferred from user");
        assertEq(tokenA.balanceOf(address(mockIntent)), AMOUNT + TIP, "Tokens not transferred to intent contract");
    }

    // Test onFulfill
    function test_OnFulfill() public {
        // Create test data
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        bool[] memory stableFlags = new bool[](1);
        stableFlags[0] = false;

        uint256 minAmountOut = MIN_AMOUNT_OUT;
        uint256 deadline = block.timestamp + 1 hours;

        // Encode the swap data
        bytes memory data = AerodromeSwapLib.encodeSwapParams(path, stableFlags, minAmountOut, deadline, user);

        // Mint tokens to the module
        tokenA.mint(address(aerodromeModule), AMOUNT);

        // Mock the intent call
        vm.prank(address(mockIntent));
        aerodromeModule.onFulfill(bytes32(0), address(tokenA), AMOUNT, data);

        // Verify the swap
        assertEq(mockRouter.lastAmountIn(), AMOUNT, "Amount in mismatch");
        assertEq(mockRouter.lastAmountOutMin(), minAmountOut, "Amount out min mismatch");
        assertEq(mockRouter.lastReceiver(), user, "Receiver mismatch");
        assertEq(mockRouter.lastFactoryUsed(), poolFactory, "Factory mismatch");

        // Expected output with 2% fee
        uint256 expectedOutput = AMOUNT * 98 / 100;
        assertEq(tokenB.balanceOf(user), expectedOutput, "User did not receive swapped tokens");
    }

    // Test onFulfill with invalid caller (not the intent contract)
    function test_OnFulfillInvalidCaller() public {
        // Create test data
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        bool[] memory stableFlags = new bool[](1);
        stableFlags[0] = false;

        uint256 minAmountOut = MIN_AMOUNT_OUT;
        uint256 deadline = block.timestamp + 1 hours;

        // Encode the swap data
        bytes memory data = AerodromeSwapLib.encodeSwapParams(path, stableFlags, minAmountOut, deadline, user);

        // Try to call onFulfill from unauthorized address
        vm.prank(user);
        vm.expectRevert("Caller is not the Intent contract");
        aerodromeModule.onFulfill(bytes32(0), address(tokenA), AMOUNT, data);
    }

    // Test getExpectedOutput
    function test_GetExpectedOutput() public {
        // Create test data
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        bool[] memory stableFlags = new bool[](1);
        stableFlags[0] = false;

        // Get expected output
        uint256 output = aerodromeModule.getExpectedOutput(AMOUNT, path, stableFlags);

        // Expected output with 2% fee
        uint256 expectedOutput = AMOUNT * 98 / 100;
        assertEq(output, expectedOutput, "Expected output mismatch");
    }

    // Test onSettle when intent is not fulfilled
    function test_OnSettle_NotFulfilled() public {
        // Create test data
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        bool[] memory stableFlags = new bool[](1);
        stableFlags[0] = false;

        uint256 minAmountOut = MIN_AMOUNT_OUT;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 tipAmount = 5 ether;

        // Encode the swap data
        bytes memory data = AerodromeSwapLib.encodeSwapParams(path, stableFlags, minAmountOut, deadline, user);

        // Mint tokenA to the module to be sent as tip
        tokenA.mint(address(aerodromeModule), tipAmount);

        // Record user's balance before onSettle
        uint256 userBalanceBefore = tokenA.balanceOf(user);

        // Call onSettle with isFulfilled = false from the intent contract
        vm.prank(address(mockIntent));
        aerodromeModule.onSettle(
            bytes32(0), // intentId
            address(tokenA), // asset
            AMOUNT, // amount
            data, // data containing receiver
            bytes32(uint256(1)), // fulfillmentIndex
            false, // isFulfilled = false -> should send tip to receiver
            tipAmount // tip amount
        );

        // Check that the tip was sent to the user (receiver)
        uint256 userBalanceAfter = tokenA.balanceOf(user);
        assertEq(userBalanceAfter, userBalanceBefore + tipAmount, "Tip was not sent to receiver");
    }

    // Test onSettle when intent is fulfilled
    function test_OnSettle_Fulfilled() public {
        // Create test data
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        bool[] memory stableFlags = new bool[](1);
        stableFlags[0] = false;

        uint256 minAmountOut = MIN_AMOUNT_OUT;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 tipAmount = 5 ether;

        // Encode the swap data
        bytes memory data = AerodromeSwapLib.encodeSwapParams(path, stableFlags, minAmountOut, deadline, user);

        // Mint tokenA to the module
        tokenA.mint(address(aerodromeModule), tipAmount);

        // Record user's balance before onSettle
        uint256 userBalanceBefore = tokenA.balanceOf(user);

        // Call onSettle with isFulfilled = true from the intent contract
        vm.prank(address(mockIntent));
        aerodromeModule.onSettle(
            bytes32(0), // intentId
            address(tokenA), // asset
            AMOUNT, // amount
            data, // data containing receiver
            bytes32(uint256(1)), // fulfillmentIndex
            true, // isFulfilled = true -> should NOT send tip to receiver
            tipAmount // tip amount
        );

        // Check that the tip was NOT sent to the user (since intent was fulfilled)
        uint256 userBalanceAfter = tokenA.balanceOf(user);
        assertEq(userBalanceAfter, userBalanceBefore, "Tip should not be sent when intent is fulfilled");
    }

    // Test onSettle with invalid caller
    function test_OnSettle_InvalidCaller() public {
        // Create test data
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        bool[] memory stableFlags = new bool[](1);
        stableFlags[0] = false;

        uint256 minAmountOut = MIN_AMOUNT_OUT;
        uint256 deadline = block.timestamp + 1 hours;

        // Encode the swap data
        bytes memory data = AerodromeSwapLib.encodeSwapParams(path, stableFlags, minAmountOut, deadline, user);

        // Try to call onSettle from unauthorized address
        vm.prank(user);
        vm.expectRevert("Caller is not the Intent contract");
        aerodromeModule.onSettle(
            bytes32(0), // intentId
            address(tokenA), // asset
            AMOUNT, // amount
            data, // data
            bytes32(uint256(1)), // fulfillmentIndex
            false, // isFulfilled
            TIP // tipAmount
        );
    }
}
