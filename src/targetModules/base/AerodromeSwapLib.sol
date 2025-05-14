// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title AerodromeSwapLib
 * @dev Library for encoding and decoding Aerodrome swap parameters
 */
library AerodromeSwapLib {
    /**
     * @dev Helper function to encode swap parameters
     * @param path Array of token addresses for the swap path
     * @param stableFlags Array of booleans indicating if pools are stable or volatile
     * @param minAmountOut Minimum output amount
     * @param deadline Transaction deadline
     * @param receiver Address that will receive the swapped tokens
     * @return The encoded parameters as bytes
     */
    function encodeSwapParams(
        address[] memory path,
        bool[] memory stableFlags,
        uint256 minAmountOut,
        uint256 deadline,
        address receiver
    ) public pure returns (bytes memory) {
        return abi.encode(path, stableFlags, minAmountOut, deadline, receiver);
    }

    /**
     * @dev Helper function to decode swap parameters from the bytes data
     * @param data The encoded swap parameters
     * @return path Array of token addresses for the swap path
     * @return stableFlags Array of booleans indicating if pools are stable or volatile
     * @return minAmountOut Minimum output amount
     * @return deadline Transaction deadline
     * @return receiver Address that will receive the swapped tokens
     */
    function decodeSwapParams(bytes memory data)
        public
        pure
        returns (
            address[] memory path,
            bool[] memory stableFlags,
            uint256 minAmountOut,
            uint256 deadline,
            address receiver
        )
    {
        // Decode the packed data
        return abi.decode(data, (address[], bool[], uint256, uint256, address));
    }
}
