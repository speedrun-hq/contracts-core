// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./IGateway.sol";

/**
 * @title IRouter
 * @dev Interface for the Router contract to support calls from Intent
 */
interface IRouter {
    /**
     * @dev Handles incoming messages from the gateway or direct calls from Intent on ZetaChain
     * @param context The message context containing sender and chain information
     * @param zrc20 The ZRC20 token address
     * @param amountWithTip The amount of tokens with tip
     * @param payload The encoded message containing intent payload
     */
    function onCall(
        IGateway.ZetaChainMessageContext calldata context,
        address zrc20,
        uint256 amountWithTip,
        bytes calldata payload
    ) external;
}
