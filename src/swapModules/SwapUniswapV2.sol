// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/ISwap.sol";
import "../interfaces/IUniswapV2Router02.sol";

/**
 * @title SwapUniswapV2
 * @dev Implements token swapping functionality for cross-chain routing using Uniswap V2
 *
 * This contract handles the token swap process for the Router contract using Uniswap V2 pools.
 * The swap process involves:
 * 1. Converting input token to WZETA
 * 2. Converting some WZETA to cover gas fees on the target chain
 * 3. Converting remaining WZETA to the destination token
 */
contract SwapUniswapV2 is ISwap {
    using SafeERC20 for IERC20;

    // Uniswap V2 Router address
    IUniswapV2Router02 public immutable swapRouter;
    // WZETA address on ZetaChain
    address public immutable wzeta;

    constructor(address _swapRouter, address _wzeta) {
        require(_swapRouter != address(0), "Invalid swap router address");
        require(_wzeta != address(0), "Invalid WZETA address");
        swapRouter = IUniswapV2Router02(_swapRouter);
        wzeta = _wzeta;
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn, address gasZRC20, uint256 gasFee)
        public
        returns (uint256 amountOut)
    {
        // Transfer tokens from sender to this contract
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Step 1: Swap input token to WZETA
        uint256 zetaAmount = _swapToWZETA(tokenIn, amountIn);

        // Step 2: Swap WZETA for gas fee token and send it back
        uint256 zetaUsedForGas = _swapForGas(gasZRC20, gasFee, zetaAmount);

        // Step 3: Swap remaining WZETA to target token
        uint256 remainingZeta = zetaAmount - zetaUsedForGas;
        amountOut = _swapWZETAToTarget(tokenOut, remainingZeta);

        // Transfer output tokens to sender
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
    }

    /**
     * @dev Swaps input token to WZETA
     * @param tokenIn The input token address
     * @param amountIn The amount of input token
     * @return Amount of WZETA received
     */
    function _swapToWZETA(address tokenIn, uint256 amountIn) internal returns (uint256) {
        IERC20(tokenIn).approve(address(swapRouter), amountIn);

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = wzeta;

        uint256[] memory amounts = swapRouter.swapExactTokensForTokens(
            amountIn,
            0, // Accept any amount of WZETA
            path,
            address(this),
            block.timestamp + 15 minutes
        );

        return amounts[1]; // WZETA amount received
    }

    /**
     * @dev Swaps WZETA for gas fee token and transfers it to sender
     * @param gasZRC20 The gas token address
     * @param gasFee The amount of gas fee needed
     * @param maxZetaAmount The maximum amount of WZETA to use
     * @return Amount of WZETA used for gas
     */
    function _swapForGas(address gasZRC20, uint256 gasFee, uint256 maxZetaAmount) internal returns (uint256) {
        IERC20(wzeta).approve(address(swapRouter), maxZetaAmount);

        address[] memory path = new address[](2);
        path[0] = wzeta;
        path[1] = gasZRC20;

        uint256[] memory amounts = swapRouter.swapTokensForExactTokens(
            gasFee, maxZetaAmount, path, address(this), block.timestamp + 15 minutes
        );

        // Transfer gas fee tokens back to sender
        IERC20(gasZRC20).safeTransfer(msg.sender, gasFee);

        return amounts[0]; // WZETA amount used for gas
    }

    /**
     * @dev Swaps WZETA to target token
     * @param tokenOut The output token address
     * @param zetaAmount The amount of WZETA to swap
     * @return Amount of output tokens received
     */
    function _swapWZETAToTarget(address tokenOut, uint256 zetaAmount) internal returns (uint256) {
        IERC20(wzeta).approve(address(swapRouter), zetaAmount);

        address[] memory path = new address[](2);
        path[0] = wzeta;
        path[1] = tokenOut;

        uint256[] memory amounts = swapRouter.swapExactTokensForTokens(
            zetaAmount,
            0, // Accept any amount of output token
            path,
            address(this),
            block.timestamp + 15 minutes
        );

        return amounts[1]; // Output token amount
    }

    /**
     * @dev Extended swap function with token name (ignored in this implementation)
     */
    function swap(address tokenIn, address tokenOut, uint256 amountIn, address gasZRC20, uint256 gasFee, string memory)
        external
        returns (uint256 amountOut)
    {
        // Just delegate to the original function since this implementation doesn't use the token name
        return swap(tokenIn, tokenOut, amountIn, gasZRC20, gasFee);
    }
}
