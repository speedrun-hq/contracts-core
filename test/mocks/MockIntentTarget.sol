// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../../src/interfaces/IntentTarget.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
    bool public lastIsFulfilled;

    // Variables to track token balance during function calls
    uint256 public balanceDuringOnFulfill;

    // Variables that can be set to control behavior
    bool public shouldRevert;
    bool public shouldCheckBalances;

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function setShouldCheckBalances(bool _shouldCheckBalances) external {
        shouldCheckBalances = _shouldCheckBalances;
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

        // Check the current token balance if requested
        if (shouldCheckBalances) {
            balanceDuringOnFulfill = IERC20(asset).balanceOf(address(this));
        }
    }

    /**
     * @dev Implementation of onSettle to record parameters and optionally revert
     */
    function onSettle(
        bytes32 intentId,
        address asset,
        uint256 amount,
        bytes calldata data,
        bytes32 fulfillmentIndex,
        bool isFulfilled
    ) external override {
        if (shouldRevert) {
            revert("MockIntentTarget: intentional revert in onSettle");
        }

        onSettleCalled = true;
        lastIntentId = intentId;
        lastAsset = asset;
        lastAmount = amount;
        lastData = data;
        lastFulfillmentIndex = fulfillmentIndex;
        lastIsFulfilled = isFulfilled;
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
        lastIsFulfilled = false;
        shouldRevert = false;
        balanceDuringOnFulfill = 0;
        shouldCheckBalances = false;
    }
}
