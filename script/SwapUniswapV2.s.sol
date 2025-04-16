// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {SwapUniswapV2} from "../src/swapModules/SwapUniswapV2.sol";

contract SwapUniswapV2Script is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Get addresses from environment variables
        address swapRouter = vm.envAddress("UNISWAP_V2_ROUTER");
        address wzeta = vm.envAddress("WZETA");

        // Deploy SwapUniswapV2
        SwapUniswapV2 swapUniswapV2 = new SwapUniswapV2(swapRouter, wzeta);
        console2.log("SwapUniswapV2 deployed to:", address(swapUniswapV2));
        console2.log("Uniswap V2 Router:", swapRouter);
        console2.log("WZETA:", wzeta);

        vm.stopBroadcast();
    }
}
