// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.25;

import {BaseFixture} from "../BaseFixture.sol";

import {VirtualModule} from "../../src/types/DataTypes.sol";

/// @notice This file is for testing the corner cases that were faced during v0.1.0 tests-run
///         and face minor challenges which should be always fixed and gracefully handled on `>v0.1.0`
contract CornerCaseV0_1_0Test is BaseFixture {
    function test_DepositAndShutdownBlockage() public {
        // 1. encounter condition where naturally a deposit is being queued
        _incomingEure(1_000e18);
        uint256 surplus = roboModule.surplus();
        assertGt(surplus, 0);

        _upkeepAndAssertPayload(abi.encode(VirtualModule.PoolAction.DEPOSIT, surplus));

        (uint256 nonceDepositTx,, bytes memory payloadDepositTx) = roboModule.queuedTx();
        assertEq(nonceDepositTx, 1);

        // 2. admin of the virtual module decides to `shutdown()` while initial queue tx is on cooldown phase still
        vm.prank(roboModule.CARD());
        roboModule.shutdown();

        // 3. Internal payload should not have being override, otherwise initial deposit never can be executed
        (uint256 nonceShutdownTx,, bytes memory payloadShutdownTx) = roboModule.queuedTx();

        // @note if it not identical a blockage will be suffer and force to wait for tx expiration
        assertEq(nonceDepositTx, nonceShutdownTx);
        assertEq(payloadDepositTx, payloadShutdownTx);

    }
}
