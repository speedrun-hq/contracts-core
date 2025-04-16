// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IGateway} from "../../src/interfaces/IGateway.sol";
import {IRouter} from "../../src/interfaces/IRouter.sol";

/**
 * @title MockRouter
 * @dev Mock implementation of the IRouter interface for testing
 */
contract MockRouter is IRouter {
    // Store the last call parameters
    address public lastZRC20;
    uint256 public lastAmount;
    bytes public lastPayload;

    // Store context fields separately to avoid struct access issues
    bytes public lastContextSender;
    address public lastContextSenderEVM;
    uint256 public lastContextChainID;

    /**
     * @dev Records parameters of the call for verification in tests
     */
    function onCall(
        IGateway.ZetaChainMessageContext calldata context,
        address zrc20,
        uint256 amountWithTip,
        bytes calldata payload
    ) external override {
        // Store the context fields
        lastContextSender = context.sender;
        lastContextSenderEVM = context.senderEVM;
        lastContextChainID = context.chainID;

        // Store the other parameters
        lastZRC20 = zrc20;
        lastAmount = amountWithTip;
        lastPayload = payload;
    }
}
