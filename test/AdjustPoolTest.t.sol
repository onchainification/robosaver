// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {BaseFixture} from "./BaseFixture.sol";

import {RoboSaverVirtualModule} from "../src/RoboSaverVirtualModule.sol";

contract AdjustPoolTest is BaseFixture {
    function test_ReverWhen_NoKeeper() public {
        address caller = address(54654546);
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(RoboSaverVirtualModule.NotKeeper.selector, caller));
        roboModule.adjustPool(RoboSaverVirtualModule.PoolAction.WITHDRAW, 5e18);
    }

    function test_RevertWhen_QueueTxNotInternal() public {
        // queue dummy transfer - external tx
        _transferOutBelowThreshold();

        (bool canExec,) = roboModule.checker();
        assertFalse(canExec);

        // keeper trying to exec for no reason `adjustPool` while checker is false
        vm.prank(roboModule.keeper());
        vm.expectRevert(abi.encodeWithSelector(RoboSaverVirtualModule.ExternalTxIsQueued.selector));
        roboModule.adjustPool(RoboSaverVirtualModule.PoolAction.WITHDRAW, 5e18);
    }

    function test_When_QueueHasExpiredTxs() public {
        // 1. queue dummy transfer - external tx
        _transferOutBelowThreshold();
        uint256 txNonceBeforeCleanup = delayModule.txNonce(); // in this case should be `0`
        assertEq(txNonceBeforeCleanup, 0);

        // 2. force queue to expire
        skip(COOL_DOWN_PERIOD + EXPIRATION_PERIOD + 1);

        // 3. trigger a normal flow (includes cleanup + queuing of a deposit)
        vm.prank(KEEPER);
        roboModule.adjustPool(RoboSaverVirtualModule.PoolAction.DEPOSIT, 2e18);

        assertGt(delayModule.txNonce(), txNonceBeforeCleanup);
    }
}
