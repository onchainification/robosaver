// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {BaseFixture} from "../BaseFixture.sol";

import {Delay} from "@delay-module/Delay.sol";
import {Roles} from "@roles-module/Roles.sol";

import {Enum} from "../../lib/delay-module/node_modules/@gnosis.pm/safe-contracts/contracts/common/Enum.sol";

import {IKeeperRegistrar} from "../../src/interfaces/chainlink/IKeeperRegistrar.sol";

import {Errors} from ".../../src/libraries/Errors.sol";

import {RoboSaverVirtualModule} from "../../src/RoboSaverVirtualModule.sol";

contract FactoryTest is BaseFixture {
    Delay dummyDelayModule;
    Roles dummyRolesModule;

    function test_RevertWhen_AvatarDoesNotMatch() public {
        address randomAvatar = address(545_495);
        // deploy dummy delay and roles modules
        dummyRolesModule = new Roles(SAFE_EOA_SIGNER, randomAvatar, randomAvatar);
        dummyDelayModule = new Delay(randomAvatar, randomAvatar, randomAvatar, COOLDOWN_PERIOD, EXPIRATION_PERIOD);

        vm.startPrank(address(safe));

        vm.expectRevert(abi.encodeWithSelector(Errors.CallerNotMatchingAvatar.selector, "DelayModule", address(safe)));
        roboModuleFactory.createVirtualModule(address(dummyRolesModule), address(rolesModule), EURE_BUFFER, SLIPPAGE);

        vm.expectRevert(abi.encodeWithSelector(Errors.CallerNotMatchingAvatar.selector, "RolesModule", address(safe)));
        roboModuleFactory.createVirtualModule(address(delayModule), address(dummyRolesModule), EURE_BUFFER, SLIPPAGE);
        vm.stopPrank();
    }

    function test_delegationSuccesful() public {
        // check: is the eoa actually a module before anything?
        assertTrue(delayModule.isModuleEnabled(SAFE_EOA_SIGNER));

        uint256 txNonceBeforeInstallationCall = delayModule.queueNonce();
        // queues the tx, abstracting away the complexity of the delay module
        vm.prank(SAFE_EOA_SIGNER);
        roboModuleFactory.installation(address(delayModule));

        // check: actually new tx is queued up?
        assertGt(delayModule.queueNonce(), txNonceBeforeInstallationCall, "No new tx queued up");

        // push time fwd
        skip(COOLDOWN_PERIOD + 1);

        // exec: queue tx after cooldown is ok to be executed
        bytes memory payload = abi.encodeWithSignature("enableModule(address)", address(this));
        delayModule.executeNextTx(address(delayModule), 0, payload, Enum.Operation.Call);

        // check: did the factory become a module?
        assertTrue(delayModule.isModuleEnabled(address(roboModuleFactory)), "Factory not enabled as module");
    }

    /// @todo pendant of implementing properly in another PR ensuring proper storage manipulation
    // function test_RevertWhen_UpkeepReturnsZero() public {
    //     bytes memory creationCode = abi.encodePacked(type(RoboSaverVirtualModule).creationCode);
    //     bytes32 salt = keccak256(abi.encodePacked(address(safe)));
    //     address deterministicVirtualModuleAddress = _getDeterministicAddress(creationCode, salt);

    //     // seems that only `upkeepId_` could be return null in case that it is not "autoApprove"
    //     // ref: https://github.com/smartcontractkit/chainlink/blob/develop/contracts/src/v0.8/automation/v2_0/KeeperRegistrar2_0.sol#L376
    //     IKeeperRegistrar.RegistrationParams memory params = IKeeperRegistrar.RegistrationParams({
    //         name: string.concat("RoboSaverVirtualModule-EURE", "-", _addressToString(address(safe))),
    //         encryptedEmail: "",
    //         upkeepContract: deterministicVirtualModuleAddress,
    //         gasLimit: 2_000_000,
    //         adminAddress: address(roboModuleFactory),
    //         triggerType: 0,
    //         checkData: "",
    //         triggerConfig: "",
    //         offchainConfig: "",
    //         amount: 200e18
    //     });
    // }
}
