// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {AerodromeModule} from "../../../src/targetModules/base/AerodromeModule.sol";

/**
 * @title DeployAerodromeModuleScript
 * @dev Deployment script for the Aerodrome module contract on Base chain
 */
contract DeployAerodromeModuleScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Get addresses from environment variables
        address aerodromeRouter = vm.envAddress("AERODROME_ROUTER");
        address poolFactory = vm.envAddress("AERODROME_POOL_FACTORY");
        address intentContract = vm.envAddress("INTENT_CONTRACT");

        // Deploy AerodromeModule on the target chain (Base)
        AerodromeModule aerodromeModule = new AerodromeModule(aerodromeRouter, poolFactory, intentContract);

        console2.log("AerodromeModule deployed to:", address(aerodromeModule));
        console2.log("Aerodrome Router:", aerodromeRouter);
        console2.log("Pool Factory:", poolFactory);
        console2.log("Intent Contract:", intentContract);

        // Optional: Set reward percentage if different from default (5%)
        // uint256 customRewardPercentage = 10;
        // aerodromeModule.setRewardPercentage(customRewardPercentage);
        // console2.log("Reward percentage set to:", customRewardPercentage);

        vm.stopBroadcast();
    }
}
