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
        // save the current txNonce on the delay module
        uint256 delayTxNonceBefore = delayModule.txNonce();

        // make sure our balance is within the buffer
        _assertCheckerFalseNoDeficitNorSurplus();

        // deposit enough eure to the card to create a surplus
        _incomingEure(500e18);
        uint256 surplus = roboModule.eureSurplus();
        assertGt(surplus, 0);

        // an upkeep should now result in queueing an internal tx; a deposit of the surplus
        _upkeepAndAssertReturnedPayload(abi.encode(VirtualModule.PoolAction.DEPOSIT, surplus));
        _upkeepAndAssertReturnedPayload(bytes("Internal transaction in cooldown status"));

        // force the queued up tx to expire
        skip(COOLDOWN_PERIOD + EXPIRATION_PERIOD + 1);

        // upkeep should now want to try to deposit again since our previous deposit expired
        _upkeepAndAssertReturnedPayload(abi.encode(VirtualModule.PoolAction.DEPOSIT, surplus));

        // this time we will actually exec the deposit
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);
        _upkeepAndAssertReturnedPayload(abi.encode(VirtualModule.PoolAction.EXEC_QUEUE_POOL_ACTION, 0));

        // confirm that the delay module triggered `txNonce++` **twice**!
        // (once for the clean up, and once for the exec of the deposit)
        assertEq(delayModule.txNonce() - delayTxNonceBefore, 2);
    }
}
