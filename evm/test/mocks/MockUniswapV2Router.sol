// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../../src/interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MockUniswapV2Router
 * @dev Mock implementation of Uniswap V2 Router for testing
 */
contract MockUniswapV2Router {
    using SafeERC20 for IERC20;

    // Mock value to return for getAmountsIn
    uint256 private amountInValue = 100 ether; // Default: 100 tokens for any output amount

    // Mock value for getAmountsOut
    uint256 private amountOutValue = 90 ether; // Default: 90% of input amount

    /**
     * @dev Set the amount in value for mocking
     * @param value The value to return
     */
    function setAmountIn(uint256 value) external {
        amountInValue = value;
    }

    /**
     * @dev Set the amount out value for mocking
     * @param value The value to return
     */
    function setAmountOut(uint256 value) external {
        amountOutValue = value;
    }

    /**
     * @dev Mock implementation of swapExactTokensForTokens
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(deadline >= block.timestamp, "Expired");
        require(path.length >= 2, "Invalid path");

        // Mock transfer token in
        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountIn);

        // Calculate mock amount out
        uint256 amountOut = (amountIn * amountOutValue) / 100 ether;
        require(amountOut >= amountOutMin, "Insufficient output amount");

        // Transfer token out
        IERC20(path[path.length - 1]).safeTransfer(to, amountOut);

        // Return mock amounts
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[path.length - 1] = amountOut;

        return amounts;
    }

    /**
     * @dev Mock implementation of swapTokensForExactTokens
     */
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(deadline >= block.timestamp, "Expired");
        require(path.length >= 2, "Invalid path");

        // Calculate mock amount in needed
        uint256 amountIn = (amountOut * amountInValue) / amountOutValue;
        require(amountIn <= amountInMax, "Excessive input amount");

        // Mock transfer token in
        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountIn);

        // Transfer token out
        IERC20(path[path.length - 1]).safeTransfer(to, amountOut);

        // Return mock amounts
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[path.length - 1] = amountOut;

        return amounts;
    }

    /**
     * @dev Mock implementation of getAmountsOut
     */
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, "Invalid path");

        amounts = new uint256[](path.length);
        amounts[0] = amountIn;

        for (uint256 i = 1; i < path.length; i++) {
            amounts[i] = (amounts[i - 1] * amountOutValue) / 100 ether;
        }

        return amounts;
    }

    /**
     * @dev Mock implementation of getAmountsIn
     */
    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, "Invalid path");

        amounts = new uint256[](path.length);
        amounts[path.length - 1] = amountOut;

        for (uint256 i = path.length - 1; i > 0; i--) {
            amounts[i - 1] = (amounts[i] * amountInValue) / amountOutValue;
        }

        return amounts;
    }

    /**
     * @dev Required by IUniswapV2Router but not used in tests
     */
    function factory() external pure returns (address) {
        return address(0);
    }

    /**
     * @dev Required by IUniswapV2Router but not used in tests
     */
    function WETH() external pure returns (address) {
        return address(0);
    }
}
