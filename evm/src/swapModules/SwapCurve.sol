// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/ISwap.sol";
import "../interfaces/ICurvePool.sol";
import "../interfaces/ICurveRegistry.sol";
import "../interfaces/IUniswapV2Router02.sol";

/**
 * @title SwapCurve
 * @dev Implements token swapping functionality for cross-chain routing using Curve StableSwap for main swaps
 * 
 * This contract handles the token swap process for the Router contract:
 * 1. Uses Curve pools for the main token swap (stable coins and other supported tokens)
 * 2. Uses Uniswap V2 pools for gas fee token acquisition:
 *    - If tokenIn is different from gasZRC20, route tokenIn -> WZETA -> gasZRC20
 *    - Only the exact amount needed for gas fees is swapped this way
 * 3. The remaining tokenIn amount is swapped to tokenOut using Curve pools
 */
contract SwapCurve is ISwap {
    using SafeERC20 for IERC20;

    // Curve Registry address to find the best pools
    ICurveRegistry public immutable curveRegistry;
    // Uniswap V2 Router address for gas fee token swaps
    IUniswapV2Router02 public immutable uniswapV2Router;
    // WZETA address on ZetaChain
    address public immutable wzeta;
    
    // Mapping for direct pool overrides (for specific token pairs)
    mapping(address => mapping(address => address)) public directPoolOverrides;
    
    // Events
    event PoolOverrideSet(address indexed tokenA, address indexed tokenB, address indexed pool);
    event CurveSwapExecuted(address indexed tokenIn, address indexed tokenOut, address pool, uint256 amountIn, uint256 amountOut);

    constructor(address _curveRegistry, address _uniswapV2Router, address _wzeta) {
        require(_curveRegistry != address(0), "Invalid Curve registry address");
        require(_uniswapV2Router != address(0), "Invalid Uniswap V2 router address");
        require(_wzeta != address(0), "Invalid WZETA address");
        
        curveRegistry = ICurveRegistry(_curveRegistry);
        uniswapV2Router = IUniswapV2Router02(_uniswapV2Router);
        wzeta = _wzeta;
    }
    
    /**
     * @dev Sets a direct pool override for a specific token pair
     * @param tokenA The first token address
     * @param tokenB The second token address
     * @param pool The pool address to use for this pair
     */
    function setPoolOverride(address tokenA, address tokenB, address pool) external {
        require(pool != address(0), "Invalid pool address");
        directPoolOverrides[tokenA][tokenB] = pool;
        directPoolOverrides[tokenB][tokenA] = pool; // Set both directions
        emit PoolOverrideSet(tokenA, tokenB, pool);
    }
    
    /**
     * @dev Finds the best Curve pool for a token pair
     * @param tokenIn The input token address
     * @param tokenOut The output token address
     * @return The address of the pool to use
     */
    function findBestPool(address tokenIn, address tokenOut) public view returns (address) {
        // Check for manual override first
        address overridePool = directPoolOverrides[tokenIn][tokenOut];
        if (overridePool != address(0)) {
            return overridePool;
        }
        
        // Find the best pool using the Curve registry
        return curveRegistry.find_pool_for_coins(tokenIn, tokenOut);
    }

    /**
     * @dev Swaps tokens using Curve for main swap and Uniswap V2 for gas fee acquisition
     * @param tokenIn The input token address
     * @param tokenOut The output token address
     * @param amountIn The amount of input tokens to swap
     * @param gasZRC20 The gas token address
     * @param gasFee The amount of gas token needed
     * @return amountOut The amount of output tokens received
     */
    function swap(
        address tokenIn, 
        address tokenOut, 
        uint256 amountIn, 
        address gasZRC20, 
        uint256 gasFee,
        string memory
    ) public returns (uint256 amountOut) {
        // Transfer tokens from sender to this contract
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        
        // Handle the gas fee acquisition first
        uint256 amountInForMainSwap = amountIn;
        
        if (gasFee > 0) {
            // If tokenIn is not the gas token, we need to swap for it
            if (tokenIn != gasZRC20) {
                // First calculate how much tokenIn we need to get the gas fee
                uint256 amountInForGas = getAmountInForGasFee(tokenIn, gasZRC20, gasFee);
                require(amountInForGas < amountIn, "Amount insufficient to cover gas fees");
                
                // Reduce the main swap amount
                amountInForMainSwap = amountIn - amountInForGas;
                
                // Use Uniswap V2 to swap for gas tokens
                IERC20(tokenIn).approve(address(uniswapV2Router), amountInForGas);
                
                // If the gas token is not WZETA, we need to route through WZETA
                if (gasZRC20 != wzeta) {
                    // tokenIn -> WZETA -> gasZRC20
                    address[] memory path = new address[](3);
                    path[0] = tokenIn;
                    path[1] = wzeta;
                    path[2] = gasZRC20;
                    
                    uniswapV2Router.swapTokensForExactTokens(
                        gasFee,  // Exact amount of gas tokens we need
                        amountInForGas,  // Maximum amount of tokenIn to use
                        path,
                        address(this),
                        block.timestamp + 15 minutes
                    );
                } else {
                    // Direct swap if gas token is WZETA
                    address[] memory path = new address[](2);
                    path[0] = tokenIn;
                    path[1] = gasZRC20;
                    
                    uniswapV2Router.swapTokensForExactTokens(
                        gasFee,
                        amountInForGas,
                        path,
                        address(this),
                        block.timestamp + 15 minutes
                    );
                }
            } else {
                // If tokenIn is already the gas token, just set aside the needed amount
                amountInForMainSwap = amountIn - gasFee;
            }
            
            // Transfer gas fee tokens back to the sender
            IERC20(gasZRC20).safeTransfer(msg.sender, gasFee);
        }
        
        // Now perform the main swap using Curve pool for the remaining amount
        if (amountInForMainSwap > 0) {
            // Find the best Curve pool for this token pair
            address pool = findBestPool(tokenIn, tokenOut);
            require(pool != address(0), "No Curve pool found for token pair");
            
            // Get the coin indices in the pool
            (int128 i, int128 j) = curveRegistry.get_coin_indices(pool, tokenIn, tokenOut);
            
            // Approve the input token for the pool
            IERC20(tokenIn).approve(pool, amountInForMainSwap);
            
            // Calculate the minimum expected output
            uint256 expectedOut = ICurvePool(pool).get_dy(i, j, amountInForMainSwap);
            uint256 minAmountOut = expectedOut * 99 / 100; // 1% slippage tolerance
            
            // Execute the swap
            amountOut = ICurvePool(pool).exchange(i, j, amountInForMainSwap, minAmountOut);
            
            emit CurveSwapExecuted(tokenIn, tokenOut, pool, amountInForMainSwap, amountOut);
            
            // Transfer output tokens to sender
            IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
        }
        
        return amountOut;
    }
    
    /**
     * @dev Compatibility function for the ISwap interface
     */
    function swap(address tokenIn, address tokenOut, uint256 amountIn, address gasZRC20, uint256 gasFee)
        external
        returns (uint256 amountOut)
    {
        // Use empty string for tokenName (not needed for Curve implementation)
        string memory emptyString = "";
        return swap(tokenIn, tokenOut, amountIn, gasZRC20, gasFee, emptyString);
    }
    
    /**
     * @dev Calculates the amount of input tokens needed to get the exact amount of gas tokens
     * @param tokenIn The input token address
     * @param gasZRC20 The gas token address
     * @param gasFee The amount of gas tokens needed
     * @return The amount of input tokens needed
     */
    function getAmountInForGasFee(address tokenIn, address gasZRC20, uint256 gasFee) 
        internal 
        view 
        returns (uint256) 
    {
        // Tokens in the path
        address[] memory path;
        
        // If the gas token is not WZETA, we need to route through WZETA
        if (gasZRC20 != wzeta) {
            path = new address[](3);
            path[0] = tokenIn;
            path[1] = wzeta;
            path[2] = gasZRC20;
        } else {
            path = new address[](2);
            path[0] = tokenIn;
            path[1] = gasZRC20;
        }
        
        // Get the amount of input tokens needed to get the exact amount of gas tokens
        uint256[] memory amounts = uniswapV2Router.getAmountsIn(gasFee, path);
        return amounts[0];
    }
} 