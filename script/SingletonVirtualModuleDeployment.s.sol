// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";

import {RoboSaverVirtualModule} from "../src/RoboSaverVirtualModule.sol";

/// @notice Deploys a {RoboSaverVirtualModule} as singleton to facilitate verfication for users of source code. Deploys:
/// 1. {RoboSaverVirtualModule}
contract SingletonVirtualModuleDeployment is Script {
    RoboSaverVirtualModule roboSaverVirtualModule;

    function run() public {
        // grab pk from `.env`
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        roboSaverVirtualModule = new RoboSaverVirtualModule(
            0xAC2ba600b02078206E67fB6fE28bCa493736f708,
            0xBc54FB517e73E410E652C3199964012154f672e7,
            0xedDB035d27fE99Dd934D97E0A58664B4803bc6dE,
            50e18,
            200
        );
    }
}
