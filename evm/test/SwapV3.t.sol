// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import "../src/SwapV3.sol";
import "../src/interfaces/IUniswapV3Router.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

contract MockSwapRouter is IUniswapV3Router {
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut) {
        // Mock 1:1 swap for testing
        if (params.tokenIn == address(0)) {
            // Handle ETH input
            require(msg.value == params.amountIn, "Incorrect ETH amount");
        } else {
            IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);
        }

        if (params.tokenOut == address(0)) {
            // Handle ETH output
            (bool success,) = msg.sender.call{value: params.amountIn}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(params.tokenOut).transfer(msg.sender, params.amountIn);
        }
        return params.amountIn;
    }

    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut) {
        // For testing purposes, we'll just return the input amount
        return params.amountIn;
    }

    function exactOutputSingle(ExactOutputSingleParams calldata params) external payable returns (uint256 amountIn) {
        // Mock 1:1 swap for testing
        if (params.tokenIn == address(0)) {
            // Handle ETH input
            require(msg.value == params.amountOut, "Incorrect ETH amount");
        } else {
            IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountOut);
        }

        if (params.tokenOut == address(0)) {
            // Handle ETH output
            (bool success,) = msg.sender.call{value: params.amountOut}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(params.tokenOut).transfer(msg.sender, params.amountOut);
        }
        return params.amountOut;
    }
}

contract SwapV3Test is Test {
    SwapV3 public swapV3;
    MockSwapRouter public mockRouter;
    MockERC20 public wzeta;
    MockERC20 public inputToken;
    MockERC20 public outputToken;
    MockERC20 public gasToken;
    address public user;
    uint256 public constant AMOUNT = 1000 ether;
    uint256 public constant GAS_FEE = 100 ether;

    function setUp() public {
        // Deploy mock contracts
        mockRouter = new MockSwapRouter();
        wzeta = new MockERC20("Wrapped ZETA", "WZETA");
        inputToken = new MockERC20("Input Token", "INPUT");
        outputToken = new MockERC20("Output Token", "OUTPUT");
        gasToken = new MockERC20("Gas Token", "GAS");

        // Deploy SwapV3
        swapV3 = new SwapV3(address(mockRouter), address(wzeta));

        // Setup user
        user = makeAddr("user");
        inputToken.mint(user, AMOUNT);
        vm.prank(user);
        inputToken.approve(address(swapV3), AMOUNT);

        // Mint tokens to router for swaps
        wzeta.mint(address(mockRouter), AMOUNT);
        outputToken.mint(address(mockRouter), AMOUNT);
        gasToken.mint(address(mockRouter), AMOUNT);
    }

    function test_Swap() public {
        uint256 initialBalance = inputToken.balanceOf(user);
        uint256 expectedOutput = AMOUNT - GAS_FEE; // 1:1 swap with gas fee deduction

        vm.prank(user);
        uint256 amountOut = swapV3.swap(
            address(inputToken),
            address(outputToken),
            AMOUNT,
            address(gasToken),
            GAS_FEE
        );

        assertEq(amountOut, expectedOutput, "Incorrect output amount");
        assertEq(inputToken.balanceOf(user), initialBalance - AMOUNT, "Input tokens not transferred from user");
        assertEq(inputToken.balanceOf(address(swapV3)), 0, "Input tokens should not remain in swap contract");
        assertEq(outputToken.balanceOf(user), expectedOutput, "Output tokens not received by user");
        assertEq(gasToken.balanceOf(user), GAS_FEE, "Gas tokens not received by swap contract");
    }

    function test_SwapWithZeroAmount() public {
        vm.prank(user);
        vm.expectRevert();
        swapV3.swap(
            address(inputToken),
            address(outputToken),
            0,
            address(gasToken),
            GAS_FEE
        );
    }

    function test_SwapWithZeroGasFee() public {
        uint256 initialBalance = inputToken.balanceOf(user);
        uint256 expectedOutput = AMOUNT; // 1:1 swap with no gas fee deduction

        vm.prank(user);
        uint256 amountOut = swapV3.swap(
            address(inputToken),
            address(outputToken),
            AMOUNT,
            address(gasToken),
            0
        );

        assertEq(amountOut, expectedOutput, "Incorrect output amount");
        assertEq(inputToken.balanceOf(user), initialBalance - AMOUNT, "Input tokens not transferred from user");
        assertEq(inputToken.balanceOf(address(swapV3)), 0, "Input tokens should not remain in swap contract");
        assertEq(outputToken.balanceOf(user), expectedOutput, "Output tokens not received by user");
        assertEq(gasToken.balanceOf(address(swapV3)), 0, "Gas tokens should not be received");
    }
} 