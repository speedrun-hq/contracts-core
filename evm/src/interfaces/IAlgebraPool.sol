// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IAlgebraPool
 * @dev Interface for interacting with Algebra liquidity pools
 */
interface IAlgebraPool {
    /**
     * @dev Parameters for the swap function
     * @param zeroForOne Direction of the swap, true for token0 to token1, false for token1 to token0
     * @param recipient Address that will receive the output tokens
     * @param amountSpecified Amount of input tokens (positive) or output tokens (negative)
     * @param sqrtPriceLimitX96 Price limit during the swap (used in previous Algebra versions)
     * @param limitSqrtPrice Price limit during the swap (used in newer Algebra versions)
     */
    struct SwapParams {
        bool zeroForOne;
        address recipient;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
        uint160 limitSqrtPrice;
    }

    /**
     * @dev Swap tokens in the pool
     * @param recipient The address to receive callback
     * @param params The parameters for the swap
     * @return amount0 The delta of token0 balance
     * @return amount1 The delta of token1 balance
     */
    function swap(address recipient, SwapParams memory params) external returns (int256 amount0, int256 amount1);

    /**
     * @dev Get the address of token0
     * @return The address of token0
     */
    function token0() external view returns (address);

    /**
     * @dev Get the address of token1
     * @return The address of token1
     */
    function token1() external view returns (address);
}
