// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {Router} from "../src/Router.sol";

contract SetIntentScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Get environment variables
        address routerAddress = vm.envAddress("ROUTER_ADDRESS");
        address intentAddress = vm.envAddress("INTENT_ADDRESS");
        uint256 chainId = vm.envUint("CHAIN_ID");

        // Get Router contract
        Router router = Router(routerAddress);

        // Add intent contract
        router.setIntentContract(chainId, intentAddress);

        console2.log("Added intent contract:");
        console2.log("- Chain ID:", chainId);
        console2.log("- Intent Address:", intentAddress);
        console2.log("- Router Address:", routerAddress);

        vm.stopBroadcast();
    }
} 