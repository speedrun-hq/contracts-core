// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../src/interfaces/IntentTarget.sol";

// Uniswap V2 Router interface (partial)
interface IUniswapV2Router {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

/**
 * @title CrossChainSwapper
 * @dev Example implementation of IntentTarget that performs token swaps
 */
contract CrossChainSwapper is IntentTarget, Ownable {
    // Uniswap V2 Router address
    address public uniswapRouter;

    // Reward configuration
    uint256 public rewardPercentage = 5; // 5% reward to fulfillers

    /**
     * @dev Constructor
     * @param _uniswapRouter The Uniswap V2 Router address
     */
    constructor(address _uniswapRouter) Ownable(msg.sender) {
        uniswapRouter = _uniswapRouter;
    }

    /**
     * @dev Update the Uniswap router address
     * @param _uniswapRouter The new router address
     */
    function setUniswapRouter(address _uniswapRouter) external onlyOwner {
        uniswapRouter = _uniswapRouter;
    }

    /**
     * @dev Set reward percentage for fulfillers
     * @param _percentage New percentage (0-100)
     */
    function setRewardPercentage(uint256 _percentage) external onlyOwner {
        require(_percentage <= 100, "Percentage must be between 0-100");
        rewardPercentage = _percentage;
    }

    /**
     * @dev Called by the protocol during intent fulfillment
     * @param intentId The ID of the intent
     * @param asset The ERC20 token address
     * @param amount Amount transferred
     * @param data Custom data for execution
     */
    function onFulfill(
        bytes32 intentId,
        address asset,
        uint256 amount,
        bytes calldata data
    ) external override {
        // Decode the swap parameters from the data field
        (
            address[] memory path,
            uint256 minAmountOut,
            uint256 deadline,
            address receiver
        ) = decodeSwapParams(data);

        // Ensure the first token in the path matches the received asset
        require(path[0] == asset, "Asset mismatch");

        // Approve router to spend the tokens
        IERC20(asset).approve(uniswapRouter, amount);

        // Execute the swap on Uniswap
        IUniswapV2Router(uniswapRouter).swapExactTokensForTokens(
            amount,
            minAmountOut,
            path,
            receiver,
            deadline
        );
    }

    /**
     * @dev Called by the protocol during intent settlement
     * @param intentId The ID of the intent
     * @param asset The ERC20 token address
     * @param amount Amount transferred
     * @param data Custom data for execution
     * @param fulfillmentIndex The fulfillment index for this intent
     */
    function onSettle(
        bytes32 intentId,
        address asset,
        uint256 amount,
        bytes calldata data,
        bytes32 fulfillmentIndex
    ) external override {
        // This function is called when an intent is settled
        // We can implement custom logic here, such as rewarding the fulfiller

        // We could send a small reward to the fulfiller from this contract's balance
        // This might be tokens previously sent to this contract for this purpose

        // Example: get receiver address from the data
        (, , , address receiver) = decodeSwapParams(data);

        // Example: transfer a small reward from this contract to the fulfiller
        // This assumes this contract holds some tokens for rewards
        // In a real implementation, you might have a more sophisticated reward system

        // Get fulfiller address from the Intent contract (passed as msg.sender)
        address intentContract = msg.sender;

        // Note: In a real implementation, you would have a way to get the fulfiller address
        // For this example, we're just showing the concept
        // Normally, you could call a view function on the Intent contract to get the fulfiller
    }

    /**
     * @dev Helper function to decode swap parameters from the bytes data
     * @param data The encoded swap parameters
     * @return path Array of token addresses for the swap path
     * @return minAmountOut Minimum output amount
     * @return deadline Transaction deadline
     * @return receiver Address that will receive the swapped tokens
     */
    function decodeSwapParams(
        bytes memory data
    )
        internal
        pure
        returns (
            address[] memory path,
            uint256 minAmountOut,
            uint256 deadline,
            address receiver
        )
    {
        // Decode the packed data
        return abi.decode(data, (address[], uint256, uint256, address));
    }

    /**
     * @dev Helper function to encode swap parameters
     * @param path Array of token addresses for the swap path
     * @param minAmountOut Minimum output amount
     * @param deadline Transaction deadline
     * @param receiver Address that will receive the swapped tokens
     * @return The encoded parameters as bytes
     */
    function encodeSwapParams(
        address[] memory path,
        uint256 minAmountOut,
        uint256 deadline,
        address receiver
    ) public pure returns (bytes memory) {
        return abi.encode(path, minAmountOut, deadline, receiver);
    }
}
