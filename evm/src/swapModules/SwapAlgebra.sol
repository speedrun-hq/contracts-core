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
 * 1. Uses Algebra pools for the main token swap (tokenIn -> intermediary -> tokenOut) if direct pool isn't available
 * 2. Uses Uniswap V2 pools for gas fee token acquisition:
 *    - If tokenIn is different from gasZRC20, route tokenIn -> WZETA -> gasZRC20
 *    - Only the exact amount needed for gas fees is swapped this way
 * 3. The remaining tokenIn amount is swapped to tokenOut using the Algebra pool,
 *    potentially routing through an intermediary token if a direct pool doesn't exist
 */
contract SwapAlgebra is ISwap {
    using SafeERC20 for IERC20;

    // Algebra Factory address
    IAlgebraFactory public immutable algebraFactory;
    // Uniswap V2 Router address for gas fee token swaps
    IUniswapV2Router02 public immutable uniswapV2Router;
    // WZETA address on ZetaChain
    address public immutable wzeta;

    // Mapping from token name to intermediary token address
    mapping(string => address) public intermediaryTokens;

    // Token name to pair existence check
    mapping(address => mapping(address => bool)) private poolExistsCache;

    // Events
    event IntermediaryTokenSet(string indexed tokenName, address indexed tokenAddress);
    event SwapWithIntermediary(
        address indexed tokenIn,
        address indexed intermediary,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    constructor(address _algebraFactory, address _uniswapV2Router, address _wzeta) {
        require(_algebraFactory != address(0), "Invalid Algebra factory address");
        require(_uniswapV2Router != address(0), "Invalid Uniswap V2 router address");
        require(_wzeta != address(0), "Invalid WZETA address");

        algebraFactory = IAlgebraFactory(_algebraFactory);
        uniswapV2Router = IUniswapV2Router02(_uniswapV2Router);
        wzeta = _wzeta;
    }

    /**
     * @dev Sets the intermediary token for a specific token name
     * @param tokenName The name of the token
     * @param intermediaryToken The address of the intermediary token
     */
    function setIntermediaryToken(string calldata tokenName, address intermediaryToken) external {
        require(intermediaryToken != address(0), "Invalid intermediary token address");
        intermediaryTokens[tokenName] = intermediaryToken;
        emit IntermediaryTokenSet(tokenName, intermediaryToken);
    }

    /**
     * @dev Checks if an Algebra pool exists for the given token pair
     * @param tokenA The first token address
     * @param tokenB The second token address
     * @return Whether a pool exists
     */
    function algebraPoolExists(address tokenA, address tokenB) public view returns (bool) {
        // Check cache first
        if (poolExistsCache[tokenA][tokenB]) {
            return true;
        }

        // Check if pool exists in Algebra factory
        address pool = algebraFactory.poolByPair(tokenA, tokenB);
        return pool != address(0);
    }

    /**
     * @dev Swaps tokens using Algebra for main swap and Uniswap V2 for gas fee acquisition
     * @param tokenIn The input token address
     * @param tokenOut The output token address
     * @param amountIn The amount of input tokens to swap
     * @param gasZRC20 The gas token address
     * @param gasFee The amount of gas token needed
     * @param tokenName The name of the token for intermediary lookup
     * @return amountOut The amount of output tokens received
     */
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address gasZRC20,
        uint256 gasFee,
        string memory tokenName
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
                        gasFee, // Exact amount of gas tokens we need
                        amountInForGas, // Maximum amount of tokenIn to use
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
                        gasFee, amountInForGas, path, address(this), block.timestamp + 15 minutes
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
            // Check if a direct pool exists
            bool directPoolExists = algebraPoolExists(tokenIn, tokenOut);

            if (directPoolExists) {
                // Swap directly using the Algebra pool
                amountOut = swapThroughAlgebraPool(tokenIn, tokenOut, amountInForMainSwap);
            } else {
                // Get the intermediary token for this token name
                address intermediaryToken = intermediaryTokens[tokenName];
                require(intermediaryToken != address(0), "No intermediary token set for this token name");

                // Check if both pools exist
                bool poolInToInterExists = algebraPoolExists(tokenIn, intermediaryToken);
                bool poolInterToOutExists = algebraPoolExists(intermediaryToken, tokenOut);

                require(poolInToInterExists && poolInterToOutExists, "Required Algebra pools do not exist");

                // First hop: tokenIn -> intermediaryToken
                uint256 intermediaryAmount;
                try this.executeFirstHopSwap(tokenIn, intermediaryToken, amountInForMainSwap) returns (uint256 result) {
                    intermediaryAmount = result;
                } catch Error(string memory reason) {
                    revert(string(abi.encodePacked("First hop swap failed: ", reason)));
                } catch {
                    revert("First hop swap failed with unknown error");
                }
                
                // Second hop: intermediaryToken -> tokenOut
                try this.executeSecondHopSwap(intermediaryToken, tokenOut, intermediaryAmount) returns (uint256 result) {
                    amountOut = result;
                } catch Error(string memory reason) {
                    revert(string(abi.encodePacked("Second hop swap failed: ", reason)));
                } catch {
                    revert("Second hop swap failed with unknown error");
                }

                emit SwapWithIntermediary(tokenIn, intermediaryToken, tokenOut, amountInForMainSwap, amountOut);
            }

            // Transfer output tokens to sender
            IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
        }

        return amountOut;
    }

    /**
     * @dev Compatibility function for the ISwap interface (uses WZETA as intermediary by default)
     */
    function swap(address tokenIn, address tokenOut, uint256 amountIn, address gasZRC20, uint256 gasFee)
        external
        returns (uint256 amountOut)
    {
        // Use a default empty string for tokenName, which will rely on direct pools or default intermediary
        string memory emptyString = "";
        return swap(tokenIn, tokenOut, amountIn, gasZRC20, gasFee, emptyString);
    }

    /**
     * @dev Executes a swap between two tokens using an Algebra pool
     * @param tokenIn The input token address
     * @param tokenOut The output token address
     * @param amountIn The amount of input tokens to swap
     * @return amountOut The amount of output tokens received
     */
    function swapThroughAlgebraPool(address tokenIn, address tokenOut, uint256 amountIn)
        internal
        returns (uint256 amountOut)
    {
        address pool = algebraFactory.poolByPair(tokenIn, tokenOut);
        require(pool != address(0), "Algebra pool does not exist");

        // Check which token is token0 in the pool
        (address token0,) = tokenIn < tokenOut ? (tokenIn, tokenOut) : (tokenOut, tokenIn);

        bool zeroToOne = tokenIn == token0;

        // Approve the tokens for the pool - use max approval to ensure no issues
        uint256 currentAllowance = IERC20(tokenIn).allowance(address(this), pool);
        if (currentAllowance < amountIn) {
            IERC20(tokenIn).approve(pool, 0); // Clear any previous allowance
            IERC20(tokenIn).approve(pool, type(uint256).max); // Approve max amount
        }

        // Try the swap with a different limitSqrtPrice
        // Algebra v3 expects a non-zero limitSqrtPrice for certain swap directions
        uint160 limitSqrtPrice;
        if (zeroToOne) {
            // When swapping token0 for token1 (zeroToOne = true),
            // we need a minimum price limit
            limitSqrtPrice = 4295128740; // Minimum possible value
        } else {
            // When swapping token1 for token0 (zeroToOne = false),
            // we need a maximum price limit
            limitSqrtPrice = 1461446703485210103287273052203988822378723970341; // Maximum possible value
        }

        // Perform the swap
        return executeAlgebraSwap(pool, amountIn, zeroToOne, limitSqrtPrice);
    }

    /**
     * @dev Calculates the amount of input tokens needed to get the exact amount of gas tokens
     * @param tokenIn The input token address
     * @param gasZRC20 The gas token address
     * @param gasFee The amount of gas tokens needed
     * @return The amount of input tokens needed
     */
    function getAmountInForGasFee(address tokenIn, address gasZRC20, uint256 gasFee) internal view returns (uint256) {
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
     * @dev Executes the swap through an Algebra pool
     * @param pool The Algebra pool address
     * @param amountIn The amount of input tokens
     * @param zeroToOne Whether the input token is token0 (true) or token1 (false)
     * @param limitSqrtPrice The limitSqrtPrice for the swap
     * @return amountOut The amount of output tokens received
     */
    function executeAlgebraSwap(address pool, uint256 amountIn, bool zeroToOne, uint160 limitSqrtPrice) internal returns (uint256 amountOut) {

        // Try the swap
        try IAlgebraPool(pool).swap(
            address(this),            // recipient
            zeroToOne,               // zeroToOne
            int256(amountIn),         // amountRequired
            4295128740,           // limitSqrtPrice (using non-zero value)
            bytes("")                 // empty data
        ) returns (int256 amount0, int256 amount1) {
            // Calculate the amount out based on which token is the output
            if (zeroToOne) {
                // If zeroForOne, then token1 is the output token
                amountOut = uint256(-amount1); // amount1 is negative (tokens coming out)
            } else {
                // If not zeroForOne, then token0 is the output token
                amountOut = uint256(-amount0); // amount0 is negative (tokens coming out)
            }
        } catch Error(string memory reason) {
            // Revert with the exact error message from the pool
            revert(string(abi.encodePacked("Algebra swap error: ", reason)));
        } catch {
            // Generic error for any other type of failure
            revert("Algebra swap failed with unknown error");
        }

        return amountOut;
    }

    /**
     * @dev Callback for Algebra swap
     * @param amount0Delta The change in token0 balance
     * @param amount1Delta The change in token1 balance
     * @param data Additional data passed by the pool
     */
    function algebraSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        // Get the tokens from the caller pool
        address token0 = IAlgebraPool(msg.sender).token0();
        address token1 = IAlgebraPool(msg.sender).token1();
        
        // Ensure the caller is a valid Algebra pool by checking with the factory
        // address expectedPool = algebraFactory.poolByPair(token0, token1);
        // require(expectedPool == msg.sender, "Not an Algebra pool");

        // If amount0Delta > 0, we need to transfer token0 to the pool
        if (amount0Delta > 0) {
            uint256 amount = uint256(amount0Delta);
            uint256 balance = IERC20(token0).balanceOf(address(this));
            
            if (balance < amount) {
                revert("Insufficient token0 balance");
                // revert(string(abi.encodePacked("Insufficient token0 balance: have ", 
                //     uint2str(balance), ", need ", uint2str(amount))));
            }
            
            try IERC20(token0).transfer(msg.sender, amount) returns (bool success) {
                if (!success) {
                    revert("Token0 transfer failed");
                }
            } catch {
                revert("Error in token0 transfer");
            }
        }

        // If amount1Delta > 0, we need to transfer token1 to the pool
        if (amount1Delta > 0) {
            uint256 amount = uint256(amount1Delta);
            uint256 balance = IERC20(token1).balanceOf(address(this));
            
            if (balance < amount) {
                revert("Insufficient token1 balance");
                // revert(string(abi.encodePacked("Insufficient token1 balance: have ", 
                //     uint2str(balance), ", need ", uint2str(amount))));
            }
            
            try IERC20(token1).transfer(msg.sender, amount) returns (bool success) {
                if (!success) {
                    revert("Token1 transfer failed");
                }
            } catch {
                revert("Error in token1 transfer");
            }
        }
    }

    /**
     * @dev External function for executing direct swaps (to be used with try/catch)
     */
    function executeDirectSwap(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256) {
        return swapThroughAlgebraPool(tokenIn, tokenOut, amountIn);
    }

    /**
     * @dev External function for executing the first hop of a swap (to be used with try/catch)
     */
    function executeFirstHopSwap(address tokenIn, address intermediaryToken, uint256 amountIn) external returns (uint256) {
        return swapThroughAlgebraPool(tokenIn, intermediaryToken, amountIn);
    }

    /**
     * @dev External function for executing the second hop of a swap (to be used with try/catch)
     */
    function executeSecondHopSwap(address intermediaryToken, address tokenOut, uint256 amountIn) external returns (uint256) {
        return swapThroughAlgebraPool(intermediaryToken, tokenOut, amountIn);
    }

    // // Helper function to convert uint to string
    // function uint2str(uint256 _i) internal pure returns (string memory) {
    //     if (_i == 0) {
    //         return "0";
    //     }
    //     uint256 j = _i;
    //     uint256 len;
    //     while (j != 0) {
    //         len++;
    //         j /= 10;
    //     }
    //     bytes memory bstr = new bytes(len);
    //     uint256 k = len;
    //     while (_i != 0) {
    //         k = k-1;
    //         uint8 temp = (48 + uint8(_i - _i / 10 * 10));
    //         bytes1 b1 = bytes1(temp);
    //         bstr[k] = b1;
    //         _i /= 10;
    //     }
    //     return string(bstr);
    // }
}
