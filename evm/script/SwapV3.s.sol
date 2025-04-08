// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {SwapV3} from "../src/SwapV3.sol";

contract SwapV3Script is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Get addresses from environment variables
        address swapRouter = vm.envAddress("UNISWAP_V3_ROUTER");
        address wzeta = vm.envAddress("WZETA");

        // Deploy SwapV3
        SwapV3 swapV3 = new SwapV3(swapRouter, wzeta);
        console2.log("SwapV3 deployed to:", address(swapV3));
        console2.log("Uniswap V3 Router:", swapRouter);
        console2.log("WZETA:", wzeta);

        vm.stopBroadcast();
    }
} 