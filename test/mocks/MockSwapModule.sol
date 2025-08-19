// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../src/interfaces/ISwap.sol";
import "../../src/interfaces/IZRC20.sol";

contract MockSwapModule is ISwap {
    // Control parameters to simulate different swap behaviors
    uint256 public slippage = 0; // 0 = no slippage (1:1 swap), higher means more slippage
    bool public useDecimalAdjustment = false; // Flag to enable/disable decimal adjustment

    // Allow to set a custom amount out for testing
    uint256 customAmountOut = 0;

    function setSlippage(uint256 _slippage) external {
        slippage = _slippage;
    }

    function setCustomAmountOut(uint256 _customAmountOut) external {
        customAmountOut = _customAmountOut;
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn, address gasZRC20, uint256 gasFee)
        external
        override
        returns (uint256 amountOut)
    {
        // Transfer tokens from sender to this contract
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);

        // Handle gas fee first (similar to SwapAlgebra)
        uint256 amountInForMainSwap = amountIn;

        if (gasFee > 0 && gasZRC20 != address(0)) {
            // If tokenIn is not the gas token, we need to account for gas fee
            if (tokenIn != gasZRC20) {
                // In mock, we just reduce the main swap amount by gas fee
                amountInForMainSwap = amountIn - gasFee;
            } else {
                // If tokenIn is already the gas token, just set aside the needed amount
                amountInForMainSwap = amountIn - gasFee;
            }

            // Transfer gas fee tokens back to the sender
            IERC20(gasZRC20).transfer(msg.sender, gasFee);
        }

        // Handle main swap
        if (amountInForMainSwap > 0) {
            // Check if input and output tokens are the same
            if (tokenIn == tokenOut) {
                // No swap needed, just return the remaining amount
                amountOut = amountInForMainSwap;
            } else {
                // Calculate amount out based on slippage settings
                uint256 slippageCost = (amountInForMainSwap * slippage) / 10000; // slippage in basis points (e.g., 100 = 1%)
                amountOut = amountInForMainSwap - slippageCost;
            }

            // Transfer tokens back to the sender
            IERC20(tokenOut).transfer(msg.sender, amountOut);
        } else {
            amountOut = 0;
        }

        // Allow to set a custom amount out for testing
        if (customAmountOut > 0) {
            amountOut = customAmountOut;
        }

        return amountOut;
    }

    /**
     * @dev Extended swap function with token name (ignored in this implementation)
     */
    function swap(address tokenIn, address tokenOut, uint256 amountIn, address gasZRC20, uint256 gasFee, string memory)
        external
        returns (uint256 amountOut)
    {
        // Transfer tokens from sender to this contract
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);

        // Handle gas fee first (similar to SwapAlgebra)
        uint256 amountInForMainSwap = amountIn;

        if (gasFee > 0 && gasZRC20 != address(0)) {
            // If tokenIn is not the gas token, we need to account for gas fee
            if (tokenIn != gasZRC20) {
                // In mock, we just reduce the main swap amount by gas fee
                amountInForMainSwap = amountIn - gasFee;
            } else {
                // If tokenIn is already the gas token, just set aside the needed amount
                amountInForMainSwap = amountIn - gasFee;
            }

            // Transfer gas fee tokens back to the sender
            IERC20(gasZRC20).transfer(msg.sender, gasFee);
        }

        // Handle main swap
        if (amountInForMainSwap > 0) {
            // Check if input and output tokens are the same
            if (tokenIn == tokenOut) {
                // No swap needed, just return the remaining amount
                amountOut = amountInForMainSwap;
            } else {
                // Calculate amount out based on slippage settings
                uint256 slippageCost = (amountInForMainSwap * slippage) / 10000; // slippage in basis points (e.g., 100 = 1%)
                amountOut = amountInForMainSwap - slippageCost;
            }

            // Transfer tokens back to the sender
            IERC20(tokenOut).transfer(msg.sender, amountOut);
        } else {
            amountOut = 0;
        }

        // Allow to set a custom amount out for testing
        if (customAmountOut > 0) {
            amountOut = customAmountOut;
        }

        return amountOut;
    }
}
