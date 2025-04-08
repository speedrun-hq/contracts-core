// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {Intent} from "../src/Intent.sol";

contract IntentImplementationScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);

        // Deploy only the implementation contract
        Intent implementation = new Intent();
        
        console2.log("Intent implementation deployed to:", address(implementation));
        
        vm.stopBroadcast();
    }
} 