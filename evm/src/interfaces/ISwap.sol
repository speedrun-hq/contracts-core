// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface ISwap {
    /**
     * @dev Performs a two-step swap through ZETA and handles gas fee swap
     * @param tokenIn The input token address
     * @param tokenOut The output token address
     * @param amountIn The amount of input tokens
     * @param gasZRC20 The gas token address for the target chain
     * @param gasFee The gas fee amount needed
     * @return amountOut The amount of output tokens received
     */
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address gasZRC20,
        uint256 gasFee
    ) external returns (uint256 amountOut);
} 