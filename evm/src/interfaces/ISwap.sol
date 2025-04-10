// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title ISwap
 * @dev Interface for token swapping modules
 */
interface ISwap {
    /**
     * @dev Swaps tokens from tokenIn to tokenOut
     * @param tokenIn The input token address
     * @param tokenOut The output token address
     * @param amountIn The amount of input tokens to swap
     * @param gasZRC20 The gas token address
     * @param gasFee The amount of gas token needed
     * @return amountOut The amount of output tokens received
     */
    function swap(address tokenIn, address tokenOut, uint256 amountIn, address gasZRC20, uint256 gasFee)
        external
        returns (uint256 amountOut);

    /**
     * @dev Swaps tokens from tokenIn to tokenOut with token name for routing
     * @param tokenIn The input token address
     * @param tokenOut The output token address
     * @param amountIn The amount of input tokens to swap
     * @param gasZRC20 The gas token address
     * @param gasFee The amount of gas token needed
     * @param tokenName The name of the token for routing decisions
     * @return amountOut The amount of output tokens received
     */
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address gasZRC20,
        uint256 gasFee,
        string memory tokenName
    ) external returns (uint256 amountOut);
}
