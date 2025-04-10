// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../../src/interfaces/ICurvePool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MockCurvePool
 * @dev Mock implementation of a Curve StableSwap pool for testing
 */
contract MockCurvePool {
    using SafeERC20 for IERC20;
    
    // Each coin in the pool
    mapping(uint256 => address) private _coins;
    mapping(uint256 => address) private _underlying_coins;
    
    // Return a percentage of the input amount (90% by default)
    uint256 public returnPercentage = 90;
    
    /**
     * @dev Set the return percentage (out of 100)
     * @param percentage The percentage of input to return as output
     */
    function setReturnPercentage(uint256 percentage) external {
        require(percentage <= 100, "Percentage must be <= 100");
        returnPercentage = percentage;
    }
    
    /**
     * @dev Set a coin address at a specific index
     * @param i The index of the coin
     * @param coin The address of the coin
     */
    function setCoin(uint256 i, address coin) external {
        _coins[i] = coin;
    }
    
    /**
     * @dev Set an underlying coin address at a specific index
     * @param i The index of the coin
     * @param coin The address of the underlying coin
     */
    function setUnderlyingCoin(uint256 i, address coin) external {
        _underlying_coins[i] = coin;
    }
    
    /**
     * @dev Exchange between two tokens in the pool
     * @param i Index of the input token
     * @param j Index of the output token
     * @param dx Amount of input token to swap
     * @param min_dy Minimum amount of output token to receive
     * @return Amount of output token received
     */
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external returns (uint256) {
        // Get token addresses
        address tokenIn = _coins[uint256(uint128(i))];
        address tokenOut = _coins[uint256(uint128(j))];
        
        // Check that tokens are set
        require(tokenIn != address(0) && tokenOut != address(0), "Token not set");
        
        // Transfer input tokens from sender
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), dx);
        
        // Calculate output amount (simple percentage)
        uint256 dy = (dx * returnPercentage) / 100;
        
        // Ensure minimum amount
        require(dy >= min_dy, "Slippage limit exceeded");
        
        // Transfer output tokens to sender
        IERC20(tokenOut).safeTransfer(msg.sender, dy);
        
        return dy;
    }
    
    /**
     * @dev Exchange between underlying tokens in the pool
     * @param i Index of the input token
     * @param j Index of the output token
     * @param dx Amount of input token to swap
     * @param min_dy Minimum amount of output token to receive
     * @return Amount of output token received
     */
    function exchange_underlying(int128 i, int128 j, uint256 dx, uint256 min_dy) external returns (uint256) {
        // Similar to exchange, but using underlying tokens
        address tokenIn = _underlying_coins[uint256(uint128(i))];
        address tokenOut = _underlying_coins[uint256(uint128(j))];
        
        // Check that tokens are set
        require(tokenIn != address(0) && tokenOut != address(0), "Token not set");
        
        // Transfer input tokens from sender
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), dx);
        
        // Calculate output amount (simple percentage)
        uint256 dy = (dx * returnPercentage) / 100;
        
        // Ensure minimum amount
        require(dy >= min_dy, "Slippage limit exceeded");
        
        // Transfer output tokens to sender
        IERC20(tokenOut).safeTransfer(msg.sender, dy);
        
        return dy;
    }
    
    /**
     * @dev Get the amount of output token for a given input amount
     * @param dx Amount of input token
     * @return Amount of output token
     */
    function get_dy(int128 , int128 , uint256 dx) external view returns (uint256) {
        return (dx * returnPercentage) / 100;
    }
    
    /**
     * @dev Get the amount of output token for a given input amount (for underlying tokens)
     * @param dx Amount of input token
     * @return Amount of output token
     */
    function get_dy_underlying(int128 , int128 , uint256 dx) external view returns (uint256) {
        return (dx * returnPercentage) / 100;
    }
    
    /**
     * @dev Get the number of coins in the pool
     * @return Number of coins
     */
    function n_coins() external pure returns (uint256) {
        return 2; // Default to 2 coins for testing
    }
    
    /**
     * @dev Get the address of a coin in the pool
     * @param i Index of the coin
     * @return Address of the coin
     */
    function coins(uint256 i) external view returns (address) {
        return _coins[i];
    }
    
    /**
     * @dev Get the address of an underlying coin in the pool
     * @param i Index of the coin
     * @return Address of the underlying coin
     */
    function underlying_coins(uint256 i) external view returns (address) {
        return _underlying_coins[i];
    }
} 