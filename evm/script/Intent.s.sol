// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {Intent} from "../src/Intent.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract IntentScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Get environment variables
        address router = vm.envAddress("ROUTER_ADDRESS");
        address gateway = vm.envAddress("GATEWAY_ADDRESS");

        // Deploy implementation
        Intent implementation = new Intent();

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            Intent.initialize.selector,
            gateway,
            router
        );

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );

        Intent intent = Intent(address(proxy));

        console2.log("Intent deployed to:", address(intent));
        console2.log("Implementation at:", address(implementation));
        console2.log("Proxy at:", address(proxy));
        console2.log("Initialized with:");
        console2.log("- Gateway:", gateway);
        console2.log("- Router:", router);

        vm.stopBroadcast();
    }
} 