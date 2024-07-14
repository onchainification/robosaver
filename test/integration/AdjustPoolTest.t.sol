// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {BaseFixture} from "../BaseFixture.sol";

import {VirtualModule} from "../../src/types/DataTypes.sol";
import {Errors} from ".../../src/libraries/Errors.sol";

contract AdjustPoolTest is BaseFixture {
    function test_RevertWhen_NotKeeper() public {
        address caller = address(54654546);
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotKeeper.selector, caller));
        roboModule.performUpkeep("");
    }

    function test_RevertWhen_QueueTxNotInternal() public {
        // queue dummy transfer - external tx
        _transferOutBelowThreshold();

        (bool canExec,) = roboModule.checkUpkeep("");
        assertFalse(canExec);

        // keeper trying to exec for no reason `adjustPool` while checker is false
        vm.prank(roboModule.keeper());
        vm.expectRevert(abi.encodeWithSelector(Errors.ExternalTxIsQueued.selector));
        roboModule.performUpkeep(abi.encode(VirtualModule.PoolAction.DEPOSIT, 2e18));
    }

    function test_RevertWhen_VirtualModuleIsDisabled() public {
        vm.prank(address(safe));
        // `disableModule(address prevModule, address module)`
        delayModule.disableModule(address(safe), address(roboModule));

        vm.prank(roboModule.keeper());
        vm.expectRevert(abi.encodeWithSelector(Errors.VirtualModuleNotEnabled.selector));
        roboModule.performUpkeep(abi.encode(VirtualModule.PoolAction.DEPOSIT, 2e18));
    }

    function test_When_QueueHasExternalExpiredTxs() public {
        // 1. queue dummy transfer: external tx
        _transferOutBelowThreshold();
        uint256 txNonceBeforeCleanup = delayModule.txNonce(); // in this case should be `0`
        assertEq(txNonceBeforeCleanup, 0);

        (bool canExec, bytes memory execPayload) = roboModule.checkUpkeep("");
        assertFalse(canExec);
        assertEq(execPayload, bytes("External transaction in queue, wait for it to be executed"));

        // 2. force the queued up tx to expire
        skip(COOLDOWN_PERIOD + EXPIRATION_PERIOD + 1);

        (canExec, execPayload) = roboModule.checkUpkeep("");
        assertFalse(canExec);
        assertEq(execPayload, bytes("Neither deficit nor surplus; no action needed"));

        // 3. queue a normal deposit
        vm.prank(keeper);
        roboModule.performUpkeep(abi.encode(VirtualModule.PoolAction.DEPOSIT, 2e18));

        // confirm that the clean up occurred; it should have triggered `txNonce++`
        assertGt(delayModule.txNonce(), txNonceBeforeCleanup);
    }

    function test_When_QueueHasInternalExpiredTxs() public {
        // 1. queue dummy deposit: internal tx
        vm.prank(keeper);
        roboModule.performUpkeep(abi.encode(VirtualModule.PoolAction.DEPOSIT, 2e18));
        uint256 txNonceBeforeCleanup = delayModule.txNonce(); // in this case should be `0`
        assertEq(txNonceBeforeCleanup, 0);

        (bool canExec, bytes memory execPayload) = roboModule.checkUpkeep("");
        assertFalse(canExec);
        assertEq(execPayload, bytes("Internal transaction in cooldown status"));

        // 2. force the queued up tx to expire
        skip(COOLDOWN_PERIOD + EXPIRATION_PERIOD + 1);

        (canExec, execPayload) = roboModule.checkUpkeep("");
        assertFalse(canExec);
        assertEq(execPayload, bytes("Neither deficit nor surplus; no action needed"));

        // 3. queue a normal deposit
        vm.prank(keeper);
        roboModule.performUpkeep(abi.encode(VirtualModule.PoolAction.DEPOSIT, 2e18));

        // confirm that the clean up occurred; it should have triggered `txNonce++`
        assertGt(delayModule.txNonce(), txNonceBeforeCleanup);
    }
}
