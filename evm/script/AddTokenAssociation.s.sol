// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {Router} from "../src/Router.sol";

contract AddTokenAssociationScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Get environment variables
        address routerAddress = vm.envAddress("ROUTER_ADDRESS");
        uint256 chainId = vm.envUint("CHAIN_ID");
        address assetAddress = vm.envAddress("ASSET_ADDRESS");
        address zrc20Address = vm.envAddress("ZRC20_ADDRESS");
        string memory tokenName = vm.envString("TOKEN_NAME");

        // Get Router contract
        Router router = Router(routerAddress);

        // Add token association
        router.addTokenAssociation(tokenName, chainId, assetAddress, zrc20Address);

        console2.log("Added token association:");
        console2.log("- Token Name:", tokenName);
        console2.log("- Chain ID:", chainId);
        console2.log("- Asset Address:", assetAddress);
        console2.log("- ZRC20 Address:", zrc20Address);
        console2.log("- Router Address:", routerAddress);

        vm.stopBroadcast();
    }
} 