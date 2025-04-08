// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IGateway {
    struct ZetaChainMessageContext {
        /// @notice The address of the sender on the connected chain.
        /// @dev This field uses `bytes` to remain chain-agnostic, allowing support for both EVM and non-EVM chains.
        /// If the connected chain is an EVM chain, `senderEVM` will also be populated with the same value.
        bytes sender;
        /// @notice The sender's address in `address` type if the connected chain is an EVM-compatible chain.
        address senderEVM;
        /// @notice The chain ID of the connected chain.
        /// @dev This identifies the origin chain of the message, allowing contract logic to differentiate between sources.
        uint256 chainID;
    }

    struct CallOptions {
        uint256 gasLimit;
        bool isArbitraryCall;
    }

    struct RevertOptions {
        address revertAddress;
        bool callOnRevert;
        address abortAddress;
        bytes revertMessage;
        uint256 onRevertGasLimit;
    }

    /**
     * @notice Deposits ERC20 tokens to the custody or connector contract and calls an omnichain smart contract.
     * @param receiver Address of the receiver.
     * @param amount Amount of tokens to deposit.
     * @param asset Address of the ERC20 token.
     * @param payload Calldata to pass to the call.
     * @param revertOptions Revert options.
     */
    function depositAndCall(
        address receiver,
        uint256 amount,
        address asset,
        bytes calldata payload,
        RevertOptions calldata revertOptions
    ) external;

    function withdrawAndCall(
        bytes memory receiver,
        uint256 amount,
        address zrc20,
        bytes calldata message,
        CallOptions calldata callOptions,
        RevertOptions calldata revertOptions
    ) external;
} 