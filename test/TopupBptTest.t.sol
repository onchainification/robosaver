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
        IEURe(EURE).mintTo(GNOSIS_SAFE, EURE_TO_MINT);

        uint256 initialEureBal = IERC20(EURE).balanceOf(GNOSIS_SAFE);
        uint256 initialBptBal = IERC20(BPT_STEUR_EURE).balanceOf(GNOSIS_SAFE);

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

        // listen for `AdjustPoolTxDataQueued` event to capture the payload
        vm.recordLogs();

        vm.prank(KEEPER);
        roboModule.adjustPool(_action, _amount);

        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(
            entries[1].topics[0],
            keccak256("AdjustPoolTxDataQueued(address,bytes)"),
            "Topic: not matching 0xd6f543d0f78fc911805eb7976b83bb1e8cc25c931073876bab9df7a09813cf0b"
        );
        assertEq(
            address(uint160(uint256(entries[1].topics[1]))),
            roboModule.MULTICALL3(),
            "Target: expected to be the MULTICALL3 address"
        );

        vm.warp(block.timestamp + COOL_DOWN_PERIOD);

        // two actions:
        // 1. eure exact appproval to `BALANCER_VAULT`
        // 2. join the pool single sided with the excess
        IMulticall.Call[] memory calls_ = abi.decode(abi.decode(entries[1].data, (bytes)), (IMulticall.Call[]));

        bytes memory multiCallPayalod = abi.encodeWithSelector(IMulticall.aggregate.selector, calls_);
        delayModule.executeNextTx(roboModule.MULTICALL3(), 0, multiCallPayalod, Enum.Operation.DelegateCall);

        assertLt(
            IERC20(EURE).balanceOf(GNOSIS_SAFE),
            initialEureBal,
            "EURE balance: did not decrease after depositing into the pool"
        );
        assertGt(
            IERC20(BPT_STEUR_EURE).balanceOf(GNOSIS_SAFE),
            initialBptBal,
            "BPT balance: did not increase after depositing into the pool"
        );
    }
}
