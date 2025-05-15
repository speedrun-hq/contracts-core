// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IAerodromeRouter {
    struct Route {
        address from;
        address to;
        bool stable;
        address factory;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

contract TryDirectSwapScript is Script {
    // Aerodrome router on Base
    address constant AERODROME_ROUTER = 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43;
    
    // Token addresses
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // USDC
    address constant WETH = 0x4200000000000000000000000000000000000006; // WETH
    
    // Aerodrome pool factory
    address constant POOL_FACTORY = 0x420DD381b31aEf6683db6B902084cB0FFECe40Da;
    
    // Parameters for the swap
    uint256 constant AMOUNT_IN = 100000; // 0.1 USDC (6 decimals)
    uint256 constant MIN_AMOUNT_OUT = 0;
    uint256 constant DEADLINE = type(uint256).max; // Max deadline
    address constant RECEIVER = 0xD8ba46B6fc4b29d645eE44403060e91F38fbF9C1;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Attempting swap with account:", deployer);
        console.log("USDC balance before:", IERC20(USDC).balanceOf(deployer));
        console.log("WETH balance before:", IERC20(WETH).balanceOf(deployer));

        // Create route
        IAerodromeRouter.Route[] memory routes = new IAerodromeRouter.Route[](1);
        routes[0] = IAerodromeRouter.Route({
            from: USDC,
            to: WETH,
            stable: false,
            factory: POOL_FACTORY
        });

        vm.startBroadcast(deployerPrivateKey);
        
        // Approve router to spend tokens
        IERC20(USDC).approve(AERODROME_ROUTER, AMOUNT_IN);
        
        // Execute swap
        IAerodromeRouter(AERODROME_ROUTER).swapExactTokensForTokens(
            AMOUNT_IN,
            MIN_AMOUNT_OUT,
            routes,
            RECEIVER,
            DEADLINE
        );
        
        vm.stopBroadcast();
        
        console.log("USDC balance after:", IERC20(USDC).balanceOf(deployer));
        console.log("WETH balance after:", IERC20(WETH).balanceOf(RECEIVER));
    }
} 