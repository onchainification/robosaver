// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {BaseFixture} from "../BaseFixture.sol";

import {Delay} from "@delay-module/Delay.sol";
import {Roles} from "@roles-module/Roles.sol";

import {RoboSaverVirtualModuleFactory} from "../../src/RoboSaverVirtualModuleFactory.sol";

contract FactoryTest is BaseFixture {
    Delay dummyDelayModule;
    Roles dummyRolesModule;

    function test_ReverWhen_AvatarDoesNotMatch() public {
        address randomAvatar = address(545_495);
        // deploy dummy delay and roles modules
        dummyRolesModule = new Roles(SAFE_EOA_SIGNER, randomAvatar, randomAvatar);
        dummyDelayModule = new Delay(randomAvatar, randomAvatar, randomAvatar, COOLDOWN_PERIOD, EXPIRATION_PERIOD);

        vm.startPrank(address(safe));

        vm.expectRevert(
            abi.encodeWithSelector(
                RoboSaverVirtualModuleFactory.CallerNotMatchingAvatar.selector, "DelayModule", address(safe)
            )
        );
        roboModuleFactory.createVirtualModule(address(dummyRolesModule), address(rolesModule), EURE_BUFFER, SLIPPAGE);

        vm.expectRevert(
            abi.encodeWithSelector(
                RoboSaverVirtualModuleFactory.CallerNotMatchingAvatar.selector, "RolesModule", address(safe)
            )
        );
        roboModuleFactory.createVirtualModule(address(delayModule), address(dummyRolesModule), EURE_BUFFER, SLIPPAGE);
        vm.stopPrank();
    }

    function test_RevertWhen_UpkeepReturnsZero() public {
        // seems that only `upkeepId_` could be return null in case that it is not "autoApprove"
        // ref: https://github.com/smartcontractkit/chainlink/blob/develop/contracts/src/v0.8/automation/v2_0/KeeperRegistrar2_0.sol#L376
    }
}
