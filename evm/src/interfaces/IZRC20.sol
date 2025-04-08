// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IZRC20 {
    /**
     * @dev Returns the gas fee information for withdrawing with the specified gas limit
     * @param gasLimit The gas limit to use for the withdrawal
     * @return gasZRC20 The address of the ZRC20 token to use for gas payment
     * @return gasFee The amount of gas fee to pay
     */
    function withdrawGasFeeWithGasLimit(uint256 gasLimit) external view returns (address gasZRC20, uint256 gasFee);
    
    /**
     * @dev Returns the number of decimals used by the token
     * @return The number of decimals (e.g., 6 for USDC, 18 for most tokens)
     */
    function decimals() external view returns (uint8);
} 