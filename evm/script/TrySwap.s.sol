// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {ISwap} from "../src/interfaces/ISwap.sol";

contract SetIntentScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address swapModule = vm.envAddress("SWAP_ADDRESS");

        uint256 amountOut = ISwap(swapModule).swap(
            address(0x0327f0660525b15Cdb8f1f5FBF0dD7Cd5Ba182aD),
            address(0xfC9201f4116aE6b054722E10b98D904829b469c3),
            100000,
            address(0xA614Aebf7924A3Eb4D066aDCA5595E4980407f1d),
            10000,
            "USDC"
        );

        console2.log("Amount out:", amountOut); 
    }
}