// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../../src/interfaces/ICurveRegistry.sol";

/**
 * @title MockCurveRegistry
 * @dev Mock implementation of Curve's registry for testing
 */
contract MockCurveRegistry {
    // Mapping for pools by token pair
    mapping(address => mapping(address => address)) private poolsForCoins;

    // Mapping for coin indices in pools
    mapping(address => mapping(address => mapping(address => int128))) private coinIndices;

    /**
     * @dev Set a pool for a token pair
     * @param tokenA The first token address
     * @param tokenB The second token address
     * @param pool The pool address
     */
    function setPool(address tokenA, address tokenB, address pool) external {
        poolsForCoins[tokenA][tokenB] = pool;
        poolsForCoins[tokenB][tokenA] = pool; // Set for both directions
    }

    /**
     * @dev Set coin indices for a pool
     * @param pool The pool address
     * @param tokenA The first token address
     * @param tokenB The second token address
     * @param indexA The index of the first token
     * @param indexB The index of the second token
     */
    function setCoinIndices(address pool, address tokenA, address tokenB, int128 indexA, int128 indexB) external {
        coinIndices[pool][tokenA][tokenB] = indexA;
        coinIndices[pool][tokenB][tokenA] = indexB;
    }

    /**
     * @dev Find the best pool for exchanging two tokens
     * @param from The address of the input token
     * @param to The address of the output token
     * @return The address of the most liquid pool for the token pair
     */
    function find_pool_for_coins(address from, address to) external view returns (address) {
        return poolsForCoins[from][to];
    }

    /**
     * @dev Find the best pool for exchanging two tokens with a custom index
     * @param from The address of the input token
     * @param to The address of the output token
     * @param i Index to start searching from (ignored in mock)
     * @return The address of the pool at the given index
     */
    function find_pool_for_coins(address from, address to, uint256 i) external view returns (address) {
        if (i > 0) {
            return address(0); // Mock only supports the first pool
        }
        return poolsForCoins[from][to];
    }

    /**
     * @dev Get the index of a coin within a pool
     * @param pool The address of the pool
     * @param from The address of the input token
     * @param to The address of the output token
     * @return The indices of the input and output tokens in the pool
     */
    function get_coin_indices(address pool, address from, address to) external view returns (int128, int128) {
        return (coinIndices[pool][from][to], coinIndices[pool][to][from]);
    }
}
