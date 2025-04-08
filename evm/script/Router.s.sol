// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {Router} from "../src/Router.sol";

contract RouterScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Print diagnostics
        console2.log("Deployer address:", deployer);
        console2.log("Deployer balance:", deployer.balance);
        console2.log("Current nonce:", vm.getNonce(deployer));
        
        // Get environment variables
        address gateway = vm.envAddress("GATEWAY_ADDRESS");
        address swapModule = vm.envAddress("SWAP_MODULE_ADDRESS");
        
        // Deploy router with specific compiler version noted
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy router directly (no proxy needed)
        Router router = new Router(gateway, swapModule);
        
        console2.log("Router deployed to:", address(router));
        console2.log("Initialized with:");
        console2.log("- Gateway:", gateway);
        console2.log("- Swap Module:", swapModule);
        
        vm.stopBroadcast();
    }
} 