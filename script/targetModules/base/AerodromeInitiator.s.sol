// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {AerodromeInitiator} from "../../../src/targetModules/base/AerodromeInitiator.sol";

/**
 * @title AerodromeInitiatorScript
 * @dev Deployment script for the Aerodrome initiator contract on source chain
 */
contract AerodromeInitiatorScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Get addresses from environment variables
        address intentContract = vm.envAddress("INTENT_CONTRACT");
        address targetModule = vm.envAddress("AERODROME_MODULE_ADDRESS");
        uint256 targetChainId = vm.envUint("BASE_CHAIN_ID");

        // Deploy AerodromeInitiator on the source chain
        AerodromeInitiator aerodromeInitiator = new AerodromeInitiator(intentContract, targetModule, targetChainId);

        console2.log("AerodromeInitiator deployed to:", address(aerodromeInitiator));
        console2.log("Intent Contract:", intentContract);
        console2.log("Target Module:", targetModule);
        console2.log("Target Chain ID:", targetChainId);

        vm.stopBroadcast();
    }
}
