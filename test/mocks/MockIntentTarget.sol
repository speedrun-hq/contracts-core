// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../../src/interfaces/IntentTarget.sol";

/**
 * @title MockIntentTarget
 * @dev Mock implementation of IntentTarget for testing
 */
contract MockIntentTarget is IntentTarget {
    // Variables to track calls
    bool public onFulfillCalled;
    bool public onSettleCalled;
    bytes32 public lastIntentId;
    address public lastAsset;
    uint256 public lastAmount;
    bytes public lastData;
    bytes32 public lastFulfillmentIndex;

    // Variables that can be set to control behavior
    bool public shouldRevert;

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    /**
     * @dev Implementation of onFulfill to record parameters and optionally revert
     */
    function onFulfill(bytes32 intentId, address asset, uint256 amount, bytes calldata data) external override {
        if (shouldRevert) {
            revert("MockIntentTarget: intentional revert in onFulfill");
        }

        onFulfillCalled = true;
        lastIntentId = intentId;
        lastAsset = asset;
        lastAmount = amount;
        lastData = data;
    }

    /**
     * @dev Implementation of onSettle to record parameters and optionally revert
     */
    function onSettle(bytes32 intentId, address asset, uint256 amount, bytes calldata data, bytes32 fulfillmentIndex)
        external
        override
    {
        if (shouldRevert) {
            revert("MockIntentTarget: intentional revert in onSettle");
        }

        onSettleCalled = true;
        lastIntentId = intentId;
        lastAsset = asset;
        lastAmount = amount;
        lastData = data;
        lastFulfillmentIndex = fulfillmentIndex;
    }

    /**
     * @dev Reset all tracking variables
     */
    function reset() external {
        onFulfillCalled = false;
        onSettleCalled = false;
        lastIntentId = bytes32(0);
        lastAsset = address(0);
        lastAmount = 0;
        lastData = "";
        lastFulfillmentIndex = bytes32(0);
        shouldRevert = false;
    }
}
