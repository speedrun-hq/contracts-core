// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title ICurveRegistry
 * @dev Interface for Curve's registry to find pools
 */
interface ICurveRegistry {
    /**
     * @dev Find the best pool for exchanging two tokens
     * @param from The address of the input token
     * @param to The address of the output token
     * @return The address of the most liquid pool for the token pair
     */
    function find_pool_for_coins(address from, address to) external view returns (address);

    /**
     * @dev Find the best pool for exchanging two tokens with a custom index
     * @param from The address of the input token
     * @param to The address of the output token
     * @param i Index to start searching from
     * @return The address of the pool at the given index
     */
    function find_pool_for_coins(address from, address to, uint256 i) external view returns (address);

    /**
     * @dev Get the index of a coin within a pool
     * @param pool The address of the pool
     * @param from The address of the input token
     * @param to The address of the output token
     * @return The indices of the input and output tokens in the pool
     */
    function get_coin_indices(address pool, address from, address to) external view returns (int128, int128);
}
