// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AerodromeInitiator} from "../../../src/targetModules/base/AerodromeInitiator.sol";
import {IIntent} from "../../../src/interfaces/IIntent.sol";

contract TryIntentSwapScript is Script {
    // Contract addresses
    address constant AERODROME_INITIATOR = 0xD954f11FC1a90B26D586746E831652Eb30b227BE;

    // Token addresses
    address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant USDC_ARB = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    
    // Parameters for the swap
    uint256 constant AMOUNT_IN = 100000;
    uint256 constant TIP = 200000;
    uint256 constant SALT = 123456;
    uint256 constant GAS_LIMIT = 400000;
    uint256 constant MIN_AMOUNT_OUT = 0;
    uint256 constant DEADLINE = type(uint256).max;
    address constant RECEIVER = 0xD8ba46B6fc4b29d645eE44403060e91F38fbF9C1;
    
    // Swap path and stable flags
    address[] public path;
    bool[] public stableFlags;
    

    // AerodromeInitiator address if not deploying new one
    address public existingInitiator;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Attempting to create intent with account:", deployer);
        console.log("USDC balance before:", IERC20(USDC_ARB).balanceOf(deployer));
        
        // Initialize swap path
        path = new address[](2);
        path[0] = USDC_BASE;
        path[1] = WETH;
        
        // Initialize stable flags
        stableFlags = new bool[](1);
        stableFlags[0] = false; // USDC/WETH pool is not stable
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Get AerodromeInitiator instance
        AerodromeInitiator aerodromeInitiator = AerodromeInitiator(AERODROME_INITIATOR);
        
        // Approve tokens for AerodromeInitiator
        IERC20(USDC_ARB).approve(address(aerodromeInitiator), AMOUNT_IN + TIP);
        console.log("Approved USDC for AerodromeInitiator");
        
        // Initiate swap
        bytes32 intentId = aerodromeInitiator.initiateAerodromeSwap(
            USDC_ARB,
            AMOUNT_IN,
            TIP,
            SALT,
            GAS_LIMIT,
            path,
            stableFlags,
            MIN_AMOUNT_OUT,
            DEADLINE,
            RECEIVER
        );
        
        console.log("Intent created with ID:", uint256(intentId));
        
        vm.stopBroadcast();
        
        console.log("USDC balance after:", IERC20(USDC_ARB).balanceOf(deployer));
    }
} 