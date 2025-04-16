// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {SwapAlgebra} from "../src/swapModules/SwapAlgebra.sol";

contract SwapAlgebraScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Get addresses from environment variables
        address algebraFactory = vm.envAddress("ALGEBRA_FACTORY");
        address uniswapV2Router = vm.envAddress("UNISWAP_V2_ROUTER");
        address wzeta = vm.envAddress("WZETA");

        // Deploy SwapAlgebra
        SwapAlgebra swapAlgebra = new SwapAlgebra(algebraFactory, uniswapV2Router, wzeta);
        console2.log("SwapAlgebra deployed to:", address(swapAlgebra));
        console2.log("Algebra Factory:", algebraFactory);
        console2.log("Uniswap V2 Router:", uniswapV2Router);
        console2.log("WZETA:", wzeta);

        vm.stopBroadcast();
    }
}
