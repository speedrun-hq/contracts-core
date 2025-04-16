// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {Router} from "../src/Router.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title RouterScript
 * @dev Script to deploy a Router with a proxy for upgradeability
 * @notice Running script on ZetaChain has a bug where it fails because of invalid nonce when two contracts are deployed
 * therefore for ZetaChain the implementation and proxy contracts are deployed separately
 */
contract RouterScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Get environment variables
        address gateway = vm.envAddress("GATEWAY_ADDRESS");
        address swapModule = vm.envAddress("SWAP_MODULE_ADDRESS");
        address implementation = vm.envAddress("ROUTER_IMPLEMENTATION_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(Router.initialize.selector, gateway, swapModule);

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

        Router router = Router(address(proxy));

        console2.log("Router deployed to:", address(router));
        // console2.log("Implementation at:", address(implementation));
        console2.log("Proxy at:", address(proxy));
        console2.log("Initialized with:");
        console2.log("- Gateway:", gateway);
        console2.log("- Swap Module:", swapModule);

        vm.stopBroadcast();
    }
}
