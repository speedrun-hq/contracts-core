// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ISwap.sol";
import "./interfaces/IUniswapV3Router.sol";

contract SwapV3 is ISwap {
    using SafeERC20 for IERC20;

    // Uniswap V3 Router address
    IUniswapV3Router public immutable swapRouter;
    // WZETA address on ZetaChain
    address public immutable wzeta;

    constructor(address _swapRouter, address _wzeta) {
        require(_swapRouter != address(0), "Invalid swap router address");
        require(_wzeta != address(0), "Invalid WZETA address");
        swapRouter = IUniswapV3Router(_swapRouter);
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
        IUniswapV3Router.ExactInputSingleParams memory params1 = IUniswapV3Router.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: wzeta,
            fee: 3000,
            recipient: address(this),
            deadline: block.timestamp + 15 minutes,
            amountIn: amountIn,
            amountOutMinimum: 0, // TODO: Calculate minimum amount based on slippage
            sqrtPriceLimitX96: 0
        });
        uint256 zetaAmount = swapRouter.exactInputSingle(params1);

        // Swap ZETA for gas fee token
        IERC20(wzeta).approve(address(swapRouter), zetaAmount);
        IUniswapV3Router.ExactOutputSingleParams memory gasParams = IUniswapV3Router.ExactOutputSingleParams({
            tokenIn: wzeta,
            tokenOut: gasZRC20,
            fee: 3000,
            recipient: address(this),
            deadline: block.timestamp + 15 minutes,
            amountOut: gasFee,
            amountInMaximum: zetaAmount,
            sqrtPriceLimitX96: 0
        });
        uint256 zetaUsedForGas = swapRouter.exactOutputSingle(gasParams);

        // Transfer gas fee tokens back to sender
        IERC20(gasZRC20).safeTransfer(msg.sender, gasFee);

        // Second swap: remaining ZETA to target token
        uint256 remainingZeta = zetaAmount - zetaUsedForGas;
        IERC20(wzeta).approve(address(swapRouter), remainingZeta);
        IUniswapV3Router.ExactInputSingleParams memory params2 = IUniswapV3Router.ExactInputSingleParams({
            tokenIn: wzeta,
            tokenOut: tokenOut,
            fee: 3000,
            recipient: address(this),
            deadline: block.timestamp + 15 minutes,
            amountIn: remainingZeta,
            amountOutMinimum: 0, // TODO: Calculate minimum amount based on slippage
            sqrtPriceLimitX96: 0
        });
        amountOut = swapRouter.exactInputSingle(params2);

        // Transfer output tokens to user
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
    }
} 