// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {SwapV2} from "../src/SwapV2.sol";

contract SwapV2Script is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Get addresses from environment variables
        address swapRouter = vm.envAddress("UNISWAP_V2_ROUTER");
        address wzeta = vm.envAddress("WZETA");

        // Deploy SwapV2
        SwapV2 swapV2 = new SwapV2(swapRouter, wzeta);
        console2.log("SwapV2 deployed to:", address(swapV2));
        console2.log("Uniswap V2 Router:", swapRouter);
        console2.log("WZETA:", wzeta);

        vm.stopBroadcast();
    }
} 