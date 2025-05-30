// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Script, console2} from "forge-std/Script.sol";
import {Intent} from "../src/Intent.sol";

/**
 * @title UpgradeIntentScript
 * @dev Script to upgrade an existing Intent proxy to a new implementation
 *
 * Required environment variables:
 * - PRIVATE_KEY: Private key of the deployer (must have the DEFAULT_ADMIN_ROLE)
 * - PROXY_ADDRESS: Address of the existing Intent proxy
 * - NEW_IMPLEMENTATION: Address of the new implementation (mandatory)
 */
contract UpgradeIntentScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get proxy address
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");
        Intent proxy = Intent(proxyAddress);

        // Check if deployer has the DEFAULT_ADMIN_ROLE
        bytes32 DEFAULT_ADMIN_ROLE = 0x00;
        if (!proxy.hasRole(DEFAULT_ADMIN_ROLE, deployer)) {
            revert("Deployer does not have the DEFAULT_ADMIN_ROLE");
        }

        // Get new implementation address (required)
        address newImplementationAddress = vm.envAddress("NEW_IMPLEMENTATION");
        console2.log("Using implementation at:", newImplementationAddress);

        vm.startBroadcast(deployerPrivateKey);

        // Upgrade the proxy to the new implementation
        UUPSUpgradeable(proxyAddress).upgradeToAndCall(
            newImplementationAddress,
            "" // No initialization function call needed for upgrade
        );

        console2.log("Proxy upgraded:");
        console2.log("- Proxy address:", proxyAddress);
        console2.log("- New implementation:", newImplementationAddress);

        vm.stopBroadcast();
    }
}
