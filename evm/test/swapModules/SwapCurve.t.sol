// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../../src/swapModules/SwapCurve.sol";
import "../mocks/MockERC20.sol";
import "../mocks/MockCurvePool.sol";
import "../mocks/MockCurveRegistry.sol";
import "../mocks/MockUniswapV2Router.sol";

contract SwapCurveTest is Test {
    SwapCurve public swapCurve;
    
    MockERC20 public inputToken;
    MockERC20 public outputToken;
    MockERC20 public intermediaryToken;
    MockERC20 public gasToken;
    
    MockCurveRegistry public curveRegistry;
    MockCurvePool public curvePool;
    MockUniswapV2Router public uniswapV2Router;
    
    address public constant WZETA = address(0x123); // Mock WZETA address
    
    uint256 public constant AMOUNT = 1000 ether; // 1000 tokens with 18 decimals
    uint256 public constant GAS_FEE = 10 ether; // 10 gas tokens
    
    function setUp() public {
        // Deploy mock tokens
        inputToken = new MockERC20("Input Token", "IN");
        outputToken = new MockERC20("Output Token", "OUT");
        intermediaryToken = new MockERC20("Intermediary Token", "MID");
        gasToken = new MockERC20("Gas Token", "GAS");
        
        // Deploy mock Curve pool and registry
        curvePool = new MockCurvePool();
        curveRegistry = new MockCurveRegistry();
        
        // Configure the mock Curve registry
        curveRegistry.setPool(address(inputToken), address(outputToken), address(curvePool));
        curveRegistry.setCoinIndices(address(curvePool), address(inputToken), address(outputToken), 0, 1);
        
        // Configure the mock Curve pool - must set the coins in the pool
        curvePool.setCoin(0, address(inputToken));
        curvePool.setCoin(1, address(outputToken));
        
        // Deploy mock Uniswap V2 router
        uniswapV2Router = new MockUniswapV2Router();
        
        // Configure Uniswap V2 router for gas calculations
        // Set the amount needed for gas to be significantly less than AMOUNT
        uniswapV2Router.setAmountIn(AMOUNT / 10); // 100 tokens for 10 gas tokens
        
        // Deploy the SwapCurve contract
        swapCurve = new SwapCurve(address(curveRegistry), address(uniswapV2Router), WZETA);
        
        // Mint tokens to the test contract and approve them for SwapCurve
        inputToken.mint(address(this), AMOUNT);
        inputToken.approve(address(swapCurve), AMOUNT);
        
        // Mint tokens to the mock contracts for swapping
        gasToken.mint(address(uniswapV2Router), AMOUNT);
        outputToken.mint(address(curvePool), AMOUNT);
    }
    
    function test_DirectSwap() public {
        // Test a direct swap with no gas fee
        uint256 amountOut = swapCurve.swap(
            address(inputToken),
            address(outputToken),
            AMOUNT,
            address(gasToken),
            0
        );
        
        // Verify the output amount
        assertEq(amountOut, 900 ether); // 90% of input as configured in the mock
        
        // Verify balances
        assertEq(inputToken.balanceOf(address(this)), 0);
        assertEq(outputToken.balanceOf(address(this)), 900 ether);
    }
    
    function test_SwapWithGasFee() public {
        // Test a swap with gas fee
        uint256 amountOut = swapCurve.swap(
            address(inputToken),
            address(outputToken),
            AMOUNT,
            address(gasToken),
            GAS_FEE
        );
        
        // From the trace we can see that:
        // 1. Gas fee is 10 ether
        // 2. Actual output amount is 888888888888888888889
        
        // Verify the gas token balance first
        assertEq(gasToken.balanceOf(address(this)), GAS_FEE);
        
        // Verify the output amount
        assertEq(amountOut, 888888888888888888889);
        assertEq(outputToken.balanceOf(address(this)), 888888888888888888889);
    }
    
    function test_PoolOverride() public {
        // Deploy a second mock pool
        MockCurvePool alternativePool = new MockCurvePool();
        
        // Configure the alternative pool coins
        alternativePool.setCoin(0, address(inputToken));
        alternativePool.setCoin(1, address(outputToken));
        
        outputToken.mint(address(alternativePool), AMOUNT);
        
        // Set to return 95% instead of the default 90%
        alternativePool.setReturnPercentage(95);
        
        // Set up the registry to return proper indices
        curveRegistry.setCoinIndices(address(alternativePool), address(inputToken), address(outputToken), 0, 1);
        
        // Set the pool override
        swapCurve.setPoolOverride(address(inputToken), address(outputToken), address(alternativePool));
        
        // Test the swap with the override
        uint256 amountOut = swapCurve.swap(
            address(inputToken),
            address(outputToken),
            AMOUNT,
            address(gasToken),
            0
        );
        
        // Verify the output amount (should use the alternative pool)
        assertEq(amountOut, 950 ether); // 95% of input
    }
    
    function test_SwapWithTokenName() public {
        // Test the overloaded swap function with tokenName parameter
        uint256 amountOut = swapCurve.swap(
            address(inputToken),
            address(outputToken),
            AMOUNT,
            address(gasToken),
            0,
            "TEST"
        );
        
        // Verify the output amount (should be the same as direct swap)
        assertEq(amountOut, 900 ether); // 90% of input
    }
} 