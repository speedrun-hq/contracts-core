// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {Router} from "../src/Router.sol";

contract AddTokenScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Get environment variables
        address routerAddress = vm.envAddress("ROUTER_ADDRESS");
        string memory tokenName = vm.envString("TOKEN_NAME");

        // Get Router contract
        Router router = Router(routerAddress);

        // Add token
        router.addToken(tokenName);

        console2.log("Added token:");
        console2.log("- Token Name:", tokenName);
        console2.log("- Router Address:", routerAddress);

        vm.stopBroadcast();
    }
} 