// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IIntent} from "../src/interfaces/IIntent.sol";

contract SetIntentScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address intent = vm.envAddress("INTENT_ADDRESS");

        IIntent(intent).initiate(
            address(0x0cbe0dF132a6c6B4a2974Fa1b7Fb953CF0Cc798a),
            50000,
            8453,
            abi.encode(address(0xD8ba46B6fc4b29d645eE44403060e91F38fbF9C1)),
            200000,
            42
        );
    }
}
