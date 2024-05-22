// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {BaseFixture} from "./BaseFixture.sol";

import {Enum} from "../lib/delay-module/node_modules/@gnosis.pm/safe-contracts/contracts/common/Enum.sol";

contract CheckerTest is BaseFixture {
    function testChecker_When_TopupIsRequired() public {
        (bool canExec, bytes memory execPayload) = roboModule.checker();

        assertFalse(canExec);
        assertEq(execPayload, bytes("Neither deficit nor surplus; no action needed"));

        uint256 tokenAmountTargetToMove = _transferOutBelowThreshold();

        vm.warp(block.timestamp + COOL_DOWN_PERIOD);

        bytes memory payload = abi.encodeWithSignature("transfer(address,uint256)", WETH, tokenAmountTargetToMove);

        delayModule.executeNextTx(EURE, 0, payload, Enum.Operation.Call);

        (canExec, execPayload) = roboModule.checker();

        assertTrue(canExec, "CanExec: not executable");
        assertEq(bytes4(execPayload), ADJUST_POOL_SELECTOR, "Selector: not adjust pool (0xba2f0056)");
    }

    function testChecker_When_TxIsOnQueue() public {
        (bool canExec, bytes memory execPayload) = roboModule.checker();

        assertFalse(canExec);
        assertEq(execPayload, bytes("Neither deficit nor surplus; no action needed"));

        // queue a tx, leverage the `_transferOutBelowThreshold` function from base fixture
        _transferOutBelowThreshold();

        (canExec, execPayload) = roboModule.checker();

        assertFalse(canExec);
        assertEq(execPayload, bytes("Transaction in queue, wait for it to be executed"));
    }
}
