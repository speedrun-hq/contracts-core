// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ISwap.sol";
import "./interfaces/IUniswapV2Router02.sol";

contract SwapV2 is ISwap {
    using SafeERC20 for IERC20;

    // Uniswap V2 Router address
    IUniswapV2Router02 public immutable swapRouter;
    // WZETA address on ZetaChain
    address public immutable wzeta;

    constructor(address _swapRouter, address _wzeta) {
        require(_swapRouter != address(0), "Invalid swap router address");
        require(_wzeta != address(0), "Invalid WZETA address");
        swapRouter = IUniswapV2Router02(_swapRouter);
        wzeta = _wzeta;
    }

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address gasZRC20,
        uint256 gasFee
    ) public returns (uint256 amountOut) {
        // Transfer tokens from sender to this contract
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // First swap: from input token to ZETA
        IERC20(tokenIn).approve(address(swapRouter), amountIn);
        address[] memory path1 = new address[](2);
        path1[0] = tokenIn;
        path1[1] = wzeta;
        uint256[] memory amounts1 = swapRouter.swapExactTokensForTokens(
            amountIn,
            0, // Accept any amount of ZETA
            path1,
            address(this),
            block.timestamp + 15 minutes
        );
        uint256 zetaAmount = amounts1[1];

        // Swap ZETA for gas fee token
        IERC20(wzeta).approve(address(swapRouter), zetaAmount);
        address[] memory gasPath = new address[](2);
        gasPath[0] = wzeta;
        gasPath[1] = gasZRC20;
        uint256[] memory gasAmounts = swapRouter.swapTokensForExactTokens(
            gasFee,
            zetaAmount, // Use all ZETA if needed
            gasPath,
            address(this),
            block.timestamp + 15 minutes
        );
        uint256 zetaUsedForGas = gasAmounts[0];

        // Transfer gas fee tokens back to sender
        IERC20(gasZRC20).safeTransfer(msg.sender, gasFee);

        // Second swap: remaining ZETA to target token
        uint256 remainingZeta = zetaAmount - zetaUsedForGas;
        IERC20(wzeta).approve(address(swapRouter), remainingZeta);
        address[] memory path2 = new address[](2);
        path2[0] = wzeta;
        path2[1] = tokenOut;
        uint256[] memory amounts2 = swapRouter.swapExactTokensForTokens(
            remainingZeta,
            0, // Accept any amount of output token
            path2,
            address(this),
            block.timestamp + 15 minutes
        );
        amountOut = amounts2[1];

        // Transfer output tokens to sender
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
    }
} 