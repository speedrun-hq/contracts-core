// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../../interfaces/IntentTarget.sol";
import "./AerodromeSwapLib.sol";

/**
 * @title Aerodrome Router interface
 * @dev Interface for the Aerodrome Router contract (inspired by Uniswap V2)
 */
interface IAerodromeRouter {
    struct Route {
        address from;
        address to;
        bool stable;
        address factory;
    }

    function factory() external pure returns (address);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function getAmountsOut(uint256 amountIn, Route[] memory routes) external view returns (uint256[] memory amounts);
}

/**
 * @title AerodromeModule
 * @dev Implementation of IntentTarget that performs token swaps on Aerodrome DEX on Base
 */
contract AerodromeModule is IntentTarget, Ownable {
    using SafeERC20 for IERC20;

    // Aerodrome Router address
    address public aerodromeRouter;

    // Pool Factory address
    address public poolFactory;

    // Intent contract address
    address public intentContract;

    // Reward configuration
    uint256 public rewardPercentage = 5; // 5% reward to fulfillers

    /**
     * @dev Constructor
     * @param _aerodromeRouter The Aerodrome Router address
     * @param _poolFactory The Pool Factory address
     * @param _intentContract The Intent contract address
     */
    constructor(address _aerodromeRouter, address _poolFactory, address _intentContract) Ownable(msg.sender) {
        require(_aerodromeRouter != address(0), "Invalid router address");
        require(_poolFactory != address(0), "Invalid factory address");
        require(_intentContract != address(0), "Invalid intent contract address");
        aerodromeRouter = _aerodromeRouter;
        poolFactory = _poolFactory;
        intentContract = _intentContract;
    }

    /**
     * @dev Modifier to restrict function calls to the Intent contract only
     */
    modifier onlyIntent() {
        require(msg.sender == intentContract, "Caller is not the Intent contract");
        _;
    }

    /**
     * @dev Update the Aerodrome router address
     * @param _aerodromeRouter The new router address
     */
    function setAerodromeRouter(address _aerodromeRouter) external onlyOwner {
        require(_aerodromeRouter != address(0), "Invalid router address");
        aerodromeRouter = _aerodromeRouter;
    }

    /**
     * @dev Update the pool factory address
     * @param _poolFactory The new factory address
     */
    function setPoolFactory(address _poolFactory) external onlyOwner {
        require(_poolFactory != address(0), "Invalid factory address");
        poolFactory = _poolFactory;
    }

    /**
     * @dev Update the Intent contract address
     * @param _intentContract The new Intent contract address
     */
    function setIntentContract(address _intentContract) external onlyOwner {
        require(_intentContract != address(0), "Invalid intent contract address");
        intentContract = _intentContract;
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
     * @param asset The ERC20 token address
     * @param amount Amount transferred
     * @param data Custom data for execution
     */
    function onFulfill(bytes32, address asset, uint256 amount, bytes calldata data) external override onlyIntent {
        // Decode the swap parameters from the data field
        (address[] memory path, bool[] memory stableFlags, uint256 minAmountOut, uint256 deadline, address receiver) =
            AerodromeSwapLib.decodeSwapParams(data);

        // Ensure the first token in the path matches the received asset
        require(path[0] == asset, "Asset mismatch");

        // Verify that the tokens have been received
        uint256 balance = IERC20(asset).balanceOf(address(this));
        require(balance >= amount, "Insufficient token balance received");

        // Create the Aerodrome routes
        IAerodromeRouter.Route[] memory routes = new IAerodromeRouter.Route[](path.length - 1);
        for (uint256 i = 0; i < path.length - 1; i++) {
            routes[i] =
                IAerodromeRouter.Route({from: path[i], to: path[i + 1], stable: stableFlags[i], factory: poolFactory});
        }

        // Approve router to spend the tokens
        IERC20(asset).approve(aerodromeRouter, amount);

        // Execute the swap on Aerodrome
        uint256[] memory amounts =
            IAerodromeRouter(aerodromeRouter).swapExactTokensForTokens(amount, minAmountOut, routes, receiver, deadline);

        // Verify that the output amount meets the minimum expected
        require(amounts.length > 0 && amounts[amounts.length - 1] >= minAmountOut, "Insufficient output amount");
    }

    /**
     * @dev Called by the protocol during intent settlement
     * @param intentId The ID of the intent
     * @param asset The ERC20 token address
     * @param amount Amount transferred
     * @param data Custom data for execution
     * @param fulfillmentIndex The fulfillment index for this intent
     * @param isFulfilled Whether the intent was fulfilled before settlement
     * @param tipAmount Tip amount for this intent, can be used to redistribute if not fulfilled
     */
    function onSettle(
        bytes32 intentId,
        address asset,
        uint256 amount,
        bytes calldata data,
        bytes32 fulfillmentIndex,
        bool isFulfilled,
        uint256 tipAmount
    ) external override onlyIntent {
        // If the intent was not fulfilled, we give back the tip to the swap receiver here
        if (!isFulfilled) {
            (address[] memory path, bool[] memory stableFlags, uint256 minAmountOut, uint256 deadline, address receiver)
            = AerodromeSwapLib.decodeSwapParams(data);

            IERC20(asset).safeTransfer(receiver, tipAmount);
        }
    }

    /**
     * @dev Get the expected output amount for a swap
     * @param amountIn The input amount
     * @param path Array of token addresses for the swap path
     * @param stableFlags Array of booleans indicating if pools are stable or volatile
     * @return The expected output amount
     */
    function getExpectedOutput(uint256 amountIn, address[] memory path, bool[] memory stableFlags)
        external
        view
        returns (uint256)
    {
        require(path.length >= 2, "Invalid path");
        require(path.length - 1 == stableFlags.length, "Path and flags length mismatch");

        // Create the Aerodrome routes
        IAerodromeRouter.Route[] memory routes = new IAerodromeRouter.Route[](path.length - 1);
        for (uint256 i = 0; i < path.length - 1; i++) {
            routes[i] =
                IAerodromeRouter.Route({from: path[i], to: path[i + 1], stable: stableFlags[i], factory: poolFactory});
        }

        // Get amounts out
        uint256[] memory amounts = IAerodromeRouter(aerodromeRouter).getAmountsOut(amountIn, routes);

        // Return the final output amount
        return amounts[amounts.length - 1];
    }
}
