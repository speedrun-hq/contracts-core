// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {Router} from "../src/Router.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/**
 * @title UpgradeRouterScript
 * @dev Script to upgrade an existing Router proxy to a new implementation
 * 
 * Required environment variables:
 * - PRIVATE_KEY: Private key of the deployer account (must have DEFAULT_ADMIN_ROLE)
 * - PROXY_ADDRESS: Address of the Router proxy contract to upgrade
 * - NEW_IMPLEMENTATION: Address of the new Router implementation contract
 */
contract UpgradeRouterScript is Script {
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    
    function setUp() public {}

    function run() public {
        // Required environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");
        address newImplementationAddress = vm.envAddress("NEW_IMPLEMENTATION");
        
        address deployer = vm.addr(deployerPrivateKey);
        
        console2.log("Deployer:", deployer);
        console2.log("Router proxy address:", proxyAddress);
        console2.log("New implementation address:", newImplementationAddress);
        
        // Verify deployer has DEFAULT_ADMIN_ROLE
        bool hasRole = IAccessControl(proxyAddress).hasRole(DEFAULT_ADMIN_ROLE, deployer);
        require(hasRole, "Deployer does not have DEFAULT_ADMIN_ROLE");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Upgrade the proxy to the new implementation
        UUPSUpgradeable(proxyAddress).upgradeToAndCall(newImplementationAddress, "");
        
        console2.log("Router proxy upgraded to:", newImplementationAddress);
        
        vm.stopBroadcast();
    }
} 