// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../src/interfaces/ISwap.sol";
import "../../src/interfaces/IZRC20.sol";

contract MockFixedOutputSwapModule is ISwap {
    // Fixed output amount to return
    uint256 public fixedOutputAmount;
    
    // Set the fixed output amount to return
    function setFixedOutputAmount(uint256 _fixedOutputAmount) external {
        fixedOutputAmount = _fixedOutputAmount;
    }
    
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address gasZRC20,
        uint256 gasFee
    ) external override returns (uint256 amountOut) {
        // Transfer tokens from sender to this contract
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        
        // Just return the fixed output amount, ignoring all calculations
        amountOut = fixedOutputAmount;
        
        // Transfer tokens back to the sender
        IERC20(tokenOut).transfer(msg.sender, amountOut);
        IERC20(gasZRC20).transfer(msg.sender, gasFee);
        
        return amountOut;
    }
} 