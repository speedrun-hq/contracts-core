// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IAlgebraPool
 * @dev Interface for interacting with Algebra liquidity pools
 */
interface IAlgebraPool {
    /**
     * @dev Swap tokens in the pool
     * @param recipient The address to receive callback
     * @param zeroToOne Direction of the swap, true for token0 to token1, false for token1 to token0
     * @param amountRequired Amount of input tokens (positive) or output tokens (negative)
     * @param limitSqrtPrice Price limit during the swap
     * @param data Additional data passed to the callback
     * @return amount0 The delta of token0 balance
     * @return amount1 The delta of token1 balance
     */
    function swap(address recipient, bool zeroToOne, int256 amountRequired, uint160 limitSqrtPrice, bytes calldata data)
        external
        returns (int256 amount0, int256 amount1);

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

    /**
     * @dev Returns the global state of the pool
     * @return price The current sqrt price (Q64.96)
     * @return tick The current tick
     * @return fee The current fee
     * @return timepointIndex The index of the last written timepoint
     * @return communityFeeToken0 Community fee for token0 (in hundredths of a bip)
     * @return communityFeeToken1 Community fee for token1 (in hundredths of a bip)
     * @return unlocked Whether the pool is unlocked for swapping
     */
    function globalState()
        external
        view
        returns (
            uint160 price,
            int24 tick,
            uint16 fee,
            uint16 timepointIndex,
            uint8 communityFeeToken0,
            uint8 communityFeeToken1,
            bool unlocked
        );
}
