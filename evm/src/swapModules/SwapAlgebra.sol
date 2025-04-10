// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/ISwap.sol";
import "../interfaces/IAlgebraPool.sol";
import "../interfaces/IAlgebraFactory.sol";
import "../interfaces/IUniswapV2Router02.sol";

/**
 * @title SwapAlgebra
 * @dev Implements token swapping functionality for cross-chain routing using Algebra AMM for main swaps
 * 
 * This contract handles the token swap process for the Router contract using a hybrid approach:
 * 1. Uses Algebra pools for the main token swap (tokenIn -> tokenOut)
 * 2. Uses Uniswap V2 pools for gas fee token acquisition:
 *    - If tokenIn is different from gasZRC20, route tokenIn -> WZETA -> gasZRC20
 *    - Only the exact amount needed for gas fees is swapped this way
 * 3. The remaining tokenIn amount is swapped directly to tokenOut using the Algebra pool
 */
contract SwapAlgebra is ISwap {
    using SafeERC20 for IERC20;

    // Algebra Factory address
    IAlgebraFactory public immutable algebraFactory;
    // Uniswap V2 Router address for gas fee token swaps
    IUniswapV2Router02 public immutable uniswapV2Router;
    // WZETA address on ZetaChain
    address public immutable wzeta;

    constructor(address _algebraFactory, address _uniswapV2Router, address _wzeta) {
        require(_algebraFactory != address(0), "Invalid Algebra factory address");
        require(_uniswapV2Router != address(0), "Invalid Uniswap V2 router address");
        require(_wzeta != address(0), "Invalid WZETA address");
        
        algebraFactory = IAlgebraFactory(_algebraFactory);
        uniswapV2Router = IUniswapV2Router02(_uniswapV2Router);
        wzeta = _wzeta;
    }

    /**
     * @dev Swaps tokens using Algebra for main swap and Uniswap V2 for gas fee acquisition
     * @param tokenIn The input token address
     * @param tokenOut The output token address
     * @param amountIn The amount of input tokens to swap
     * @param gasZRC20 The gas token address
     * @param gasFee The amount of gas token needed
     * @return amountOut The amount of output tokens received
     */
    function swap(address tokenIn, address tokenOut, uint256 amountIn, address gasZRC20, uint256 gasFee)
        public
        returns (uint256 amountOut)
    {
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
        
        // Now perform the main swap using Algebra pool for the remaining amount
        if (amountInForMainSwap > 0) {
            address pool = algebraFactory.poolByPair(tokenIn, tokenOut);
            require(pool != address(0), "Algebra pool does not exist");
            
            // Check which token is token0 in the pool
            (address token0, address token1) = tokenIn < tokenOut 
                ? (tokenIn, tokenOut) 
                : (tokenOut, tokenIn);
                
            bool zeroForOne = tokenIn == token0;
            
            // Approve the tokens for the pool
            IERC20(tokenIn).approve(pool, amountInForMainSwap);
            
            // Perform the swap
            amountOut = swapExactInputSingle(
                pool,
                amountInForMainSwap,
                zeroForOne,
                tokenOut
            );
            
            // Transfer output tokens to sender
            IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
        }
        
        return amountOut;
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
    
    /**
     * @dev Swaps exact input amount for output using Algebra pool
     * @param pool The Algebra pool address
     * @param amountIn The amount of input tokens
     * @param zeroForOne Whether the input token is token0 (true) or token1 (false)
     * @param tokenOut The output token address
     * @return amountOut The amount of output tokens received
     */
    function swapExactInputSingle(
        address pool,
        uint256 amountIn,
        bool zeroForOne,
        address tokenOut
    ) internal returns (uint256 amountOut) {
        // Calculate the minimum amount out (could add slippage protection here)
        uint256 amountOutMinimum = 0;  // TODO: Calculate minimum amount based on slippage
        
        // Prepare the swap params
        IAlgebraPool.SwapParams memory params = IAlgebraPool.SwapParams({
            zeroForOne: zeroForOne,
            recipient: address(this),
            amountSpecified: int256(amountIn),
            sqrtPriceLimitX96: 0,  // No price limit
            limitSqrtPrice: 0  // No limit
        });
        
        // Perform the swap
        (int256 amount0, int256 amount1) = IAlgebraPool(pool).swap(
            address(this),
            params
        );
        
        // Calculate the amount out based on which token is the output
        if (zeroForOne) {
            // If zeroForOne, then token1 is the output token
            amountOut = uint256(-amount1);  // amount1 is negative (tokens coming out)
        } else {
            // If not zeroForOne, then token0 is the output token
            amountOut = uint256(-amount0);  // amount0 is negative (tokens coming out)
        }
        
        return amountOut;
    }
    
    /**
     * @dev Callback for Algebra swap
     * @param amount0Delta The change in token0 balance
     * @param amount1Delta The change in token1 balance
     * @param data Additional data
     */
    function algebraSwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        // Ensure the caller is a pool
        require(algebraFactory.poolByPair(IAlgebraPool(msg.sender).token0(), IAlgebraPool(msg.sender).token1()) == msg.sender, "Not an Algebra pool");
        
        // If amount0Delta > 0, we need to transfer token0 to the pool
        if (amount0Delta > 0) {
            IERC20(IAlgebraPool(msg.sender).token0()).safeTransfer(msg.sender, uint256(amount0Delta));
        }
        
        // If amount1Delta > 0, we need to transfer token1 to the pool
        if (amount1Delta > 0) {
            IERC20(IAlgebraPool(msg.sender).token1()).safeTransfer(msg.sender, uint256(amount1Delta));
        }
    }
} 