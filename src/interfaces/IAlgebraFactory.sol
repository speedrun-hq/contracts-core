// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IAlgebraFactory
 * @dev Interface for the Algebra factory that creates and manages pools
 */
interface IAlgebraFactory {
    /**
     * @dev Get the pool address for a token pair
     * @param tokenA The address of one token
     * @param tokenB The address of the other token
     * @return pool The address of the pool for the token pair
     */
    function poolByPair(address tokenA, address tokenB) external view returns (address pool);

    /**
     * @dev Creates a pool for the given token pair if it doesn't exist
     * @param tokenA The address of one token
     * @param tokenB The address of the other token
     * @return pool The address of the pool for the token pair
     */
    function createPool(address tokenA, address tokenB) external returns (address pool);
}
