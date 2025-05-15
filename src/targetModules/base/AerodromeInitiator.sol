// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../../interfaces/IIntent.sol";
import "./AerodromeSwapLib.sol";

/**
 * @title AerodromeInitiator
 * @dev Contract to create intents on the source chain that will execute swaps on Aerodrome DEX on Base
 */
contract AerodromeInitiator is Ownable {
    // Intent contract address
    address public intent;

    // Target AerodromeModule address on Base chain
    address public targetModule;

    // Base chain ID
    uint256 public targetChainId;

    // Events
    event IntentCreated(
        bytes32 indexed intentId,
        address indexed asset,
        uint256 amount,
        address receiver,
        uint256 tip,
        address[] path,
        uint256 minAmountOut
    );

    /**
     * @dev Constructor
     * @param _intent The Intent contract address
     * @param _targetModule The AerodromeModule address on the target chain
     * @param _targetChainId The target chain ID (Base chain ID)
     */
    constructor(address _intent, address _targetModule, uint256 _targetChainId) Ownable(msg.sender) {
        require(_intent != address(0), "Invalid intent contract address");
        require(_targetModule != address(0), "Invalid target module address");
        require(_targetChainId != 0, "Invalid target chain ID");

        intent = _intent;
        targetModule = _targetModule;
        targetChainId = _targetChainId;
    }

    /**
     * @dev Update the Intent contract address
     * @param _intent The new Intent contract address
     */
    function setIntent(address _intent) external onlyOwner {
        require(_intent != address(0), "Invalid intent contract address");
        intent = _intent;
    }

    /**
     * @dev Update the target AerodromeModule address
     * @param _targetModule The new target module address
     */
    function setTargetModule(address _targetModule) external onlyOwner {
        require(_targetModule != address(0), "Invalid target module address");
        targetModule = _targetModule;
    }

    /**
     * @dev Update the target chain ID
     * @param _targetChainId The new target chain ID
     */
    function setTargetChainId(uint256 _targetChainId) external onlyOwner {
        require(_targetChainId != 0, "Invalid target chain ID");
        targetChainId = _targetChainId;
    }

    /**
     * @dev Initiates a cross-chain swap on Aerodrome
     * @param asset The source token address
     * @param amount Amount to swap
     * @param tip Tip for the fulfiller
     * @param salt Salt for intent ID generation
     * @param gasLimit Gas limit for the target chain transaction
     * @param path Array of token addresses for the swap path
     * @param stableFlags Array of booleans indicating if pools are stable or volatile
     * @param minAmountOut Minimum output amount
     * @param deadline Transaction deadline
     * @param receiver Address that will receive the swapped tokens
     * @return intentId The generated intent ID
     */
    function initiateAerodromeSwap(
        address asset,
        uint256 amount,
        uint256 tip,
        uint256 salt,
        uint256 gasLimit,
        address[] calldata path,
        bool[] calldata stableFlags,
        uint256 minAmountOut,
        uint256 deadline,
        address receiver
    ) external returns (bytes32) {
        require(path.length >= 2, "Invalid path");
        require(path.length - 1 == stableFlags.length, "Path and flags length mismatch");

        // Encode the swap parameters
        bytes memory data = AerodromeSwapLib.encodeSwapParams(path, stableFlags, minAmountOut, deadline, receiver);

        // Transfer tokens from sender to this contract
        IERC20(asset).transferFrom(msg.sender, address(this), amount + tip);

        // Approve the Intent contract to spend the tokens
        IERC20(asset).approve(intent, amount + tip);

        // Initiate the call through the Intent contract
        bytes32 intentId = IIntent(intent).initiateCall(
            asset, amount, targetChainId, abi.encodePacked(targetModule), tip, salt, data, gasLimit
        );

        // Emit event
        emit IntentCreated(intentId, asset, amount, receiver, tip, path, minAmountOut);

        return intentId;
    }
}
