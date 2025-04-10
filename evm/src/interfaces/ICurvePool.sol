// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title ICurvePool
 * @dev Interface for Curve StableSwap pools
 */
interface ICurvePool {
    /**
     * @dev Exchange between two tokens in the pool
     * @param i Index of the input token
     * @param j Index of the output token
     * @param dx Amount of input token to swap
     * @param min_dy Minimum amount of output token to receive
     * @return Amount of output token received
     */
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external returns (uint256);

    /**
     * @dev Exchange between underlying tokens in the pool
     * @param i Index of the input token
     * @param j Index of the output token
     * @param dx Amount of input token to swap
     * @param min_dy Minimum amount of output token to receive
     * @return Amount of output token received
     */
    function exchange_underlying(int128 i, int128 j, uint256 dx, uint256 min_dy) external returns (uint256);

    /**
     * @dev Get the amount of output token for a given input amount
     * @param i Index of the input token
     * @param j Index of the output token
     * @param dx Amount of input token
     * @return Amount of output token
     */
    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);

    /**
     * @dev Get the amount of output token for a given input amount (for underlying tokens)
     * @param i Index of the input token
     * @param j Index of the output token
     * @param dx Amount of input token
     * @return Amount of output token
     */
    function get_dy_underlying(int128 i, int128 j, uint256 dx) external view returns (uint256);

    /**
     * @dev Get the number of coins in the pool
     * @return Number of coins
     */
    function n_coins() external view returns (uint256);

    /**
     * @dev Get the address of a coin in the pool
     * @param i Index of the coin
     * @return Address of the coin
     */
    function coins(uint256 i) external view returns (address);

    /**
     * @dev Get the address of an underlying coin in the pool
     * @param i Index of the coin
     * @return Address of the underlying coin
     */
    function underlying_coins(uint256 i) external view returns (address);
}
