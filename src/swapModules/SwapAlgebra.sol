// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
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
contract SwapAlgebra is ISwap, Ownable {
    using SafeERC20 for IERC20;

    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    // Maximum allowed slippage (1%)
    uint256 private constant MAX_SLIPPAGE = 100;
    uint256 private constant BASIS_POINTS_DENOMINATOR = 10000;

    // Algebra Factory address
    IAlgebraFactory public immutable algebraFactory;

    // Uniswap V2 Router address for gas fee token swaps
    IUniswapV2Router02 public immutable uniswapV2Router;

    // WZETA address on ZetaChain
    address public immutable wzeta;

    // Mapping from token name to intermediary token address
    mapping(string => address) public intermediaryTokens;

    // Events
    event IntermediaryTokenSet(string indexed tokenName, address indexed tokenAddress);

    event SwapWithIntermediary(
        address indexed tokenIn,
        address indexed intermediary,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    constructor(address _algebraFactory, address _uniswapV2Router, address _wzeta) Ownable(msg.sender) {
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
    function setIntermediaryToken(string calldata tokenName, address intermediaryToken) external onlyOwner {
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
    function algebraPoolExists(address tokenA, address tokenB) internal view returns (bool) {
        // Check if pool exists in Algebra factory
        address pool = algebraFactory.poolByPair(tokenA, tokenB);
        return pool != address(0);
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
     * @dev Calculates the minimum amount out based on the given slippage tolerance
     * @param amountOut The expected amount out
     * @return The minimum amount out that satisfies the MAX_SLIPPAGE tolerance
     */
    function calculateMinAmountOutWithSlippage(uint256 amountOut) public pure returns (uint256) {
        return (amountOut * (BASIS_POINTS_DENOMINATOR - MAX_SLIPPAGE)) / BASIS_POINTS_DENOMINATOR;
    }

    /// @notice Returns a valid `limitSqrtPrice` just beyond the current price
    /// @param zeroForOne If true, token0 → token1; else token1 → token0
    function getValidLimitSqrtPrice(bool zeroForOne) internal pure returns (uint160) {
        unchecked {
            if (zeroForOne) {
                return MIN_SQRT_RATIO + 1;
            } else {
                return MAX_SQRT_RATIO - 1;
            }
        }
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
        // Record initial balances for slippage calculation
        uint256 initialOutBalance = 0;
        if (tokenOut != address(0)) {
            initialOutBalance = IERC20(tokenOut).balanceOf(address(this));
        }

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
                uint256 intermediaryAmount = swapThroughAlgebraPool(tokenIn, intermediaryToken, amountInForMainSwap);

                // Second hop: intermediaryToken -> tokenOut
                amountOut = swapThroughAlgebraPool(intermediaryToken, tokenOut, intermediaryAmount);

                emit SwapWithIntermediary(tokenIn, intermediaryToken, tokenOut, amountInForMainSwap, amountOut);
            }

            // Calculate actual balance change to account for any existing balance
            uint256 finalOutBalance = IERC20(tokenOut).balanceOf(address(this));
            uint256 actualAmountOut = finalOutBalance - initialOutBalance;

            // Apply slippage check using constant MAX_SLIPPAGE (1%)
            uint256 minRequiredAmount = calculateMinAmountOutWithSlippage(amountOut);

            // Verify we received at least the minimum amount expected
            require(actualAmountOut >= minRequiredAmount, "Slippage tolerance exceeded");

            // Use the actual received amount for the transfer to the user
            uint256 amountToTransfer = actualAmountOut;

            // Transfer output tokens to sender
            IERC20(tokenOut).safeTransfer(msg.sender, amountToTransfer);

            // Update the return value to match what was actually received and transferred
            amountOut = amountToTransfer;
        }

        return amountOut;
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

        address token0 = IAlgebraPool(pool).token0();
        bool zeroToOne = tokenIn == token0;

        IERC20(tokenIn).approve(pool, amountIn);

        uint160 limitSqrtPrice = getValidLimitSqrtPrice(zeroToOne);

        // Perform the swap
        return executeAlgebraSwap(pool, amountIn, zeroToOne, limitSqrtPrice);
    }

    /**
     * @dev Executes the swap through an Algebra pool
     * @param pool The Algebra pool address
     * @param amountIn The amount of input tokens
     * @param zeroToOne Whether the input token is token0 (true) or token1 (false)
     * @param limitSqrtPrice The limitSqrtPrice for the swap
     * @return amountOut The amount of output tokens received
     */
    function executeAlgebraSwap(address pool, uint256 amountIn, bool zeroToOne, uint160 limitSqrtPrice)
        internal
        returns (uint256 amountOut)
    {
        // Try the swap
        try IAlgebraPool(pool).swap(
            address(this), // recipient
            zeroToOne, // zeroToOne
            int256(amountIn), // amountRequired
            limitSqrtPrice,
            bytes("") // empty data
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
     */
    function algebraSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
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
            }

            IERC20(token0).safeTransfer(msg.sender, amount);
        }

        // If amount1Delta > 0, we need to transfer token1 to the pool
        if (amount1Delta > 0) {
            uint256 amount = uint256(amount1Delta);
            uint256 balance = IERC20(token1).balanceOf(address(this));

            if (balance < amount) {
                revert("Insufficient token1 balance");
            }

            IERC20(token1).safeTransfer(msg.sender, amount);
        }
    }
}
