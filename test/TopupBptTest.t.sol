// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";

import {BaseFixture} from "./BaseFixture.sol";

import {IMulticall} from "@gnosispay-kit/interfaces/IMulticall.sol";

import "@balancer-v2/interfaces/contracts/vault/IVault.sol";

import {Enum} from "../lib/delay-module/node_modules/@gnosis.pm/safe-contracts/contracts/common/Enum.sol";

import {IEURe} from "../src/interfaces/eure/IEURe.sol";

import {RoboSaverVirtualModule} from "../src/RoboSaverVirtualModule.sol";

contract TopupBptTest is BaseFixture {
    function testTopupBpt() public {
        // mint further EURE to be way above buffer
        vm.prank(EURE_MINTER);
        IEURe(EURE).mintTo(address(safe), EURE_TO_MINT);

        uint256 initialEureBal = IERC20(EURE).balanceOf(address(safe));
        uint256 initialBptBal = IERC20(BPT_STEUR_EURE).balanceOf(address(safe));

        (bool canExec, bytes memory execPayload) = roboModule.checker();
        (bytes memory dataWithoutSelector, bytes4 selector) = _extractEncodeDataWithoutSelector(execPayload);
        (RoboSaverVirtualModule.PoolAction _action, uint256 _amount) =
            abi.decode(dataWithoutSelector, (RoboSaverVirtualModule.PoolAction, uint256));

        // since initially it was minted 1000 it should be way above the buffer
        assertTrue(canExec, "CanExec: not executable");
        assertEq(selector, ADJUST_POOL_SELECTOR, "Selector: not adjust pool (0xba2f0056)");
        assertEq(
            uint8(_action), uint8(RoboSaverVirtualModule.PoolAction.DEPOSIT), "PoolAction: not depositing into the pool"
        );

        uint256 bptOutExpected = _getBptOutExpected(_amount);

        // listen for `AdjustPoolTxDataQueued` event to capture the payload
        vm.recordLogs();

        vm.prank(KEEPER);
        roboModule.adjustPool(_action, _amount);

        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(
            entries[1].topics[0],
            keccak256("AdjustPoolTxDataQueued(address,bytes,uint256)"),
            "Topic: not matching 0x1e06c48e3eae1d5087ad1d103fe5666fb3fd180f582006fb14e9635c596736d7"
        );
        assertEq(
            address(uint160(uint256(entries[1].topics[1]))),
            roboModule.MULTICALL3(),
            "Target: expected to be the MULTICALL3 address"
        );

        vm.warp(block.timestamp + COOLDOWN_PERIOD);

        _assertPreStorageValuesNextTxExec(roboModule.MULTICALL3(), abi.decode(entries[1].data, (bytes)));

        // two actions:
        // 1. eure exact appproval to `BALANCER_VAULT`
        // 2. join the pool single sided with the excess
        vm.prank(KEEPER);
        roboModule.adjustPool(RoboSaverVirtualModule.PoolAction.EXEC_QUEUE_POOL_ACTION, 0);

        // ensure default values at `queuedTx` after execution
        _assertPostDefaultValuesNextTxExec();

        assertEq(
            IERC20(EURE).balanceOf(address(safe)),
            initialEureBal - _amount,
            "EURE balance: did not decrease precisely by the amount deposited into the pool"
        );
        assertApproxEqAbs(
            IERC20(BPT_STEUR_EURE).balanceOf(address(safe)),
            initialBptBal + bptOutExpected,
            DIFF_MIN_OUT_CALC_ALLOWED,
            "BPT balance: after depositing has greater difference than allowed (received vs expected)"
        );
    }
}
