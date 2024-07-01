// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";

import {BaseFixture} from "../BaseFixture.sol";

import "@balancer-v2/interfaces/contracts/vault/IVault.sol";

import {Enum} from "../../lib/delay-module/node_modules/@gnosis.pm/safe-contracts/contracts/common/Enum.sol";

import {VirtualModule} from "../../src/types/DataTypes.sol";

contract TopupTest is BaseFixture {
    // @note ref for error codes: https://docs.balancer.fi/reference/contracts/error-codes.html#error-codes
    function testExitPool() public {
        _assertCheckerFalseNoDeficitNorSurplus();

        uint256 tokenAmountTargetToMove = _transferOutBelowThreshold();

        vm.warp(block.timestamp + COOLDOWN_PERIOD);

        bytes memory payload = abi.encodeWithSignature("transfer(address,uint256)", WETH, tokenAmountTargetToMove);

        delayModule.executeNextTx(EURE, 0, payload, Enum.Operation.Call);

        // check balance after mirroring a EURE transaction out from the CARD as "initial balances"
        uint256 initialBptBal = IERC20(BPT_STEUR_EURE).balanceOf(address(safe));
        uint256 initialStakedBptBal = IERC20(AURA_GAUGE_STEUR_EURE).balanceOf(address(safe));
        uint256 initialEureBal = IERC20(EURE).balanceOf(address(safe));

        (bool canExec, bytes memory execPayload) = roboModule.checkUpkeep("");
        (VirtualModule.PoolAction _action, uint256 _deficit) =
            abi.decode(execPayload, (VirtualModule.PoolAction, uint256));

        assertTrue(canExec, "CanExec: not executable");
        assertEq(uint8(_action), uint8(VirtualModule.PoolAction.WITHDRAW), "PoolAction: not withdrawal from pool");

        // calc via Balancer Queries the max BPT amount to withdraw
        uint256 maxBPTAmountIn = _getMaxBptInExpected(_deficit, initialStakedBptBal);

        // listen for `AdjustPoolTxDataQueued` event to capture the payload
        vm.recordLogs();

        vm.prank(keeper);
        roboModule.performUpkeep(execPayload);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(
            entries[1].topics[0],
            keccak256("AdjustPoolTxDataQueued(address,bytes,uint256)"),
            "Topic: not matching 0x1e06c48e3eae1d5087ad1d103fe5666fb3fd180f582006fb14e9635c596736d7"
        );
        assertEq(
            address(uint160(uint256(entries[1].topics[1]))),
            address(roboModule.MULTICALL3()),
            "Target: expected to be the MULTICALL3 address"
        );

        vm.warp(block.timestamp + COOLDOWN_PERIOD);

        _assertPreStorageValuesNextTxExec(address(roboModule.MULTICALL3()), abi.decode(entries[1].data, (bytes)));

        vm.prank(keeper);
        roboModule.performUpkeep(abi.encode(VirtualModule.PoolAction.EXEC_QUEUE_POOL_ACTION, 0));

        // ensure default values at `queuedTx` after execution
        _assertPostDefaultValuesNextTxExec();

        // withdrawing leaves some residual BPT in the save; so we take balances for both tokens
        assertApproxEqAbs(
            IERC20(BPT_STEUR_EURE).balanceOf(address(safe)) + IERC20(AURA_GAUGE_STEUR_EURE).balanceOf(address(safe)),
            initialBptBal + initialStakedBptBal - maxBPTAmountIn,
            DIFF_MIN_OUT_CALC_ALLOWED,
            "(Staked) BPT balance: after withdrawing has greater difference than allowed (burn vs expected reduction)"
        );

        assertEq(
            IERC20(EURE).balanceOf(address(safe)),
            initialEureBal + _deficit,
            "EURE balance: did not increase precisely by the amount withdrawn from the pool"
        );
    }
}
