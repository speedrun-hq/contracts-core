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
     * @dev Initiates a new intent for cross-chain transfer (backward compatibility)
     * @param asset The ERC20 token address
     * @param amount Amount to receive on target chain
     * @param targetChain Target chain ID
     * @param receiver Receiver address in bytes format
     * @param tip Tip for the fulfiller
     * @param salt Salt for intent ID generation
     * @return intentId The generated intent ID
     */
    function initiate(
        address asset,
        uint256 amount,
        uint256 targetChain,
        bytes calldata receiver,
        uint256 tip,
        uint256 salt
    ) external returns (bytes32);

    /**
     * @dev Initiates a new intent for cross-chain transfer
     * @param asset The ERC20 token address
     * @param amount Amount to receive on target chain
     * @param targetChain Target chain ID
     * @param receiver Receiver address in bytes format
     * @param tip Tip for the fulfiller
     * @param salt Salt for intent ID generation
     * @return intentId The generated intent ID
     */
    function initiateTransfer(
        address asset,
        uint256 amount,
        uint256 targetChain,
        bytes calldata receiver,
        uint256 tip,
        uint256 salt
    ) external returns (bytes32);

    /**
     * @dev Initiates a new intent for cross-chain transfer with contract call
     * @param asset The ERC20 token address
     * @param amount Amount to receive on target chain
     * @param targetChain Target chain ID
     * @param receiver Receiver address in bytes format (must implement ICallableIntent)
     * @param tip Tip for the fulfiller
     * @param salt Salt for intent ID generation
     * @param data Custom data to be passed to the receiver contract
     * @return intentId The generated intent ID
     */
    function initiateCall(
        address asset,
        uint256 amount,
        uint256 targetChain,
        bytes calldata receiver,
        uint256 tip,
        uint256 salt,
        bytes calldata data
    ) external returns (bytes32);

    /**
     * @dev Fulfills an intent by transferring tokens to the receiver (backward compatibility)
     * @param intentId The ID of the intent to fulfill
     * @param asset The ERC20 token address
     * @param amount Amount to transfer
     * @param receiver Receiver address
     */
    function fulfill(bytes32 intentId, address asset, uint256 amount, address receiver) external;

    /**
     * @dev Fulfills an intent by transferring tokens to the receiver
     * @param intentId The ID of the intent to fulfill
     * @param asset The ERC20 token address
     * @param amount Amount to transfer
     * @param receiver Receiver address
     */
    function fulfillTransfer(bytes32 intentId, address asset, uint256 amount, address receiver) external;

    /**
     * @dev Fulfills an intent by transferring tokens to the receiver and calling onFulfill
     * @param intentId The ID of the intent to fulfill
     * @param asset The ERC20 token address
     * @param amount Amount to transfer
     * @param receiver Receiver address that implements IntentTarget
     * @param data Custom data to be passed to the receiver contract
     */
    function fulfillCall(bytes32 intentId, address asset, uint256 amount, address receiver, bytes calldata data)
        external;

    /**
     * @dev Handles incoming cross-chain messages
     * @param context Message context containing sender information
     * @param message Encoded settlement payload
     * @return Empty bytes array
     */
    function onCall(MessageContext calldata context, bytes calldata message) external payable returns (bytes memory);
}
