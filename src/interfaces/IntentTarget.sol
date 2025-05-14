// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title IntentTarget
 * @dev Interface for contracts that want to support intent calls
 */
interface IntentTarget {
    /**
     * @dev Called during intent fulfillment to execute custom logic
     * @param intentId The ID of the intent
     * @param asset The ERC20 token address
     * @param amount Amount transferred
     * @param data Custom data for execution
     */
    function onFulfill(bytes32 intentId, address asset, uint256 amount, bytes calldata data) external;

    /**
     * @dev Called during intent settlement to execute custom logic
     * @param intentId The ID of the intent
     * @param asset The ERC20 token address
     * @param amount Amount transferred
     * @param data Custom data for execution
     * @param fulfillmentIndex The fulfillment index for this intent
     * @param isFulfilled Whether the intent was fulfilled before settlement
     */
    function onSettle(
        bytes32 intentId,
        address asset,
        uint256 amount,
        bytes calldata data,
        bytes32 fulfillmentIndex,
        bool isFulfilled
    ) external;
}
