// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {Router} from "../src/Router.sol";

/**
 * @title RouterImplementationScript
 * @dev Script to deploy the Router implementation contract (WITHOUT initializing it)
 * This implementation is meant to be used with a proxy contract
 */
contract RouterImplementationScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("Deployer:", deployer);
        console2.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the implementation contract (uninitialized)
        // The implementation should NEVER be initialized directly
        Router implementation = new Router();

        console2.log("Router implementation deployed at:", address(implementation));

        vm.stopBroadcast();
    }
}
