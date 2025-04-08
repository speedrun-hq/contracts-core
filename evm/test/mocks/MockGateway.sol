// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../src/interfaces/IGateway.sol";

contract MockGateway is IGateway {
    // Track received calls
    struct CallData {
        address receiver;
        uint256 amount;
        address asset;
        bytes payload;
        RevertOptions revertOptions;
    }

    CallData public lastCall;

    function depositAndCall(
        address receiver,
        uint256 amount,
        address asset,
        bytes calldata payload,
        RevertOptions calldata revertOptions
    ) external override {
        // Transfer tokens from the caller to this contract
        IERC20(asset).transferFrom(msg.sender, address(this), amount);

        // Store the call data
        lastCall = CallData({
            receiver: receiver,
            amount: amount,
            asset: asset,
            payload: payload,
            revertOptions: revertOptions
        });
    }

    function withdrawAndCall(
        bytes memory receiver,
        uint256 amount,
        address zrc20,
        bytes calldata message,
        CallOptions calldata callOptions,
        RevertOptions calldata revertOptions
    ) external override {
        // Mock implementation - do nothing
    }
} 