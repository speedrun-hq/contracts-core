// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title IIntent
 * @dev Interface for Intent contract from Router's perspective
 */
interface IIntent {
    // Struct for message context
    struct MessageContext {
        address sender;
    }

    /**
     * @dev Handles incoming cross-chain messages
     * @param context Message context containing sender information
     * @param message Encoded settlement payload
     * @return Empty bytes array
     */
    function onCall(MessageContext calldata context, bytes calldata message) external payable returns (bytes memory);
}
