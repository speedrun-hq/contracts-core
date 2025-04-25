// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title PayloadUtils
 * @dev Utility functions for encoding and decoding payloads for cross-chain transactions
 */
library PayloadUtils {
    struct IntentPayload {
        bytes32 intentId;
        uint256 amount;
        uint256 tip;
        uint256 targetChain;
        bytes receiver;
        bool isCall;
        bytes data;
    }

    /**
     * @dev Encodes intent data into a payload for cross-chain transaction
     */
    function encodeIntentPayload(
        bytes32 intentId,
        uint256 amount,
        uint256 tip,
        uint256 targetChain,
        bytes memory receiver,
        bool isCall,
        bytes memory data
    ) internal pure returns (bytes memory) {
        return abi.encode(intentId, amount, tip, targetChain, receiver, isCall, data);
    }

    /**
     * @dev Encodes standard intent data into a payload (backward compatibility)
     */
    function encodeIntentPayload(
        bytes32 intentId,
        uint256 amount,
        uint256 tip,
        uint256 targetChain,
        bytes memory receiver
    ) internal pure returns (bytes memory) {
        return encodeIntentPayload(intentId, amount, tip, targetChain, receiver, false, "");
    }

    /**
     * @dev Decodes payload back into intent data
     */
    function decodeIntentPayload(bytes memory payload) internal pure returns (IntentPayload memory) {
        (
            bytes32 intentId,
            uint256 amount,
            uint256 tip,
            uint256 targetChain,
            bytes memory receiver,
            bool isCall,
            bytes memory data
        ) = abi.decode(payload, (bytes32, uint256, uint256, uint256, bytes, bool, bytes));

        return IntentPayload({
            intentId: intentId,
            amount: amount,
            tip: tip,
            targetChain: targetChain,
            receiver: receiver,
            isCall: isCall,
            data: data
        });
    }

    /**
     * @dev Struct for settlement payload
     */
    struct SettlementPayload {
        // The unique identifier of the intent that initiated the cross-chain transfer
        bytes32 intentId;
        // The original intended amount requested in the intent, used for calculating fulfillment index.
        // This amount is used to match with pre-existing fulfillments and is NOT necessarily
        // the amount that will be transferred.
        uint256 amount;
        // The ERC20 token address on the destination chain
        address asset;
        // The receiver address on the destination chain
        address receiver;
        // The tip amount to be paid to the fulfiller (may be reduced from original tip if it was used to cover costs)
        uint256 tip;
        // The actual amount to be transferred after deducting any fees, slippage, or gas costs
        // This may be lower than the original 'amount' if the tip wasn't sufficient to cover all costs
        uint256 actualAmount;
        // Whether this is a callable intent
        bool isCall;
        // Custom data to be used in contract calls
        bytes data;
    }

    /**
     * @dev Encodes settlement data into a payload
     */
    function encodeSettlementPayload(
        bytes32 intentId,
        uint256 amount,
        address asset,
        address receiver,
        uint256 tip,
        uint256 actualAmount,
        bool isCall,
        bytes memory data
    ) internal pure returns (bytes memory) {
        return abi.encode(intentId, amount, asset, receiver, tip, actualAmount, isCall, data);
    }

    /**
     * @dev Encodes standard settlement data into a payload (backward compatibility)
     */
    function encodeSettlementPayload(
        bytes32 intentId,
        uint256 amount,
        address asset,
        address receiver,
        uint256 tip,
        uint256 actualAmount
    ) internal pure returns (bytes memory) {
        return encodeSettlementPayload(intentId, amount, asset, receiver, tip, actualAmount, false, "");
    }

    /**
     * @dev Decodes settlement payload back into data
     */
    function decodeSettlementPayload(bytes memory payload) internal pure returns (SettlementPayload memory) {
        (
            bytes32 intentId,
            uint256 amount,
            address asset,
            address receiver,
            uint256 tip,
            uint256 actualAmount,
            bool isCall,
            bytes memory data
        ) = abi.decode(payload, (bytes32, uint256, address, address, uint256, uint256, bool, bytes));

        return SettlementPayload({
            intentId: intentId,
            amount: amount,
            asset: asset,
            receiver: receiver,
            tip: tip,
            actualAmount: actualAmount,
            isCall: isCall,
            data: data
        });
    }

    /**
     * @dev Computes a unique index for a fulfillment
     * @param intentId The ID of the intent
     * @param asset The ERC20 token address
     * @param amount Amount to transfer
     * @param receiver Receiver address
     * @param isCall Whether this is a callable intent
     * @param data Custom data for contract calls
     * @return The computed fulfillment index
     */
    function computeFulfillmentIndex(
        bytes32 intentId,
        address asset,
        uint256 amount,
        address receiver,
        bool isCall,
        bytes memory data
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(intentId, asset, amount, receiver, isCall, data));
    }

    /**
     * @dev Computes a unique index for a fulfillment (backward compatibility)
     * @param intentId The ID of the intent
     * @param asset The ERC20 token address
     * @param amount Amount to transfer
     * @param receiver Receiver address
     * @return The computed fulfillment index
     */
    function computeFulfillmentIndex(bytes32 intentId, address asset, uint256 amount, address receiver)
        internal
        pure
        returns (bytes32)
    {
        return computeFulfillmentIndex(intentId, asset, amount, receiver, false, "");
    }

    /**
     * @dev Converts bytes to address
     * @param data The bytes to convert
     * @return The converted address
     */
    function bytesToAddress(bytes memory data) internal pure returns (address) {
        require(data.length >= 20, "Invalid address length");
        return address(bytes20(data));
    }
}
