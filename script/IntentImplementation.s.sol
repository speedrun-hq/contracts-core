// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {Intent} from "../src/Intent.sol";

contract IntentImplementationScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Default to false for non-ZetaChain deployments
        // Set IS_ZETACHAIN environment variable to "true" for ZetaChain deployments
        bool isZetaChain = vm.envOr("IS_ZETACHAIN", false);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy only the implementation contract with isZetaChain parameter
        Intent implementation = new Intent(isZetaChain);

        console2.log("Intent implementation deployed to:", address(implementation));
        console2.log("isZetaChain value:", isZetaChain);

        vm.stopBroadcast();
    }
}
