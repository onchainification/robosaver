// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";

import {BaseFixture} from "./BaseFixture.sol";

import "@balancer-v2/interfaces/contracts/vault/IVault.sol";

import {Enum} from "../lib/delay-module/node_modules/@gnosis.pm/safe-contracts/contracts/common/Enum.sol";

import {RoboSaverVirtualModule} from "../src/RoboSaverVirtualModule.sol";

contract TopupTest is BaseFixture {
    // @note ref for error codes: https://docs.balancer.fi/reference/contracts/error-codes.html#error-codes
    function testExitPool() public {
        uint256 initialBptBal = IERC20(BPT_STEUR_EURE).balanceOf(GNOSIS_SAFE);

        (bool canExec, bytes memory execPayload) = roboModule.checker();

        assertFalse(canExec);
        assertEq(execPayload, bytes("Neither deficit nor surplus; no action needed"));

        uint256 tokenAmountTargetToMove = _transferOutBelowThreshold();

        vm.warp(block.timestamp + COOL_DOWN_PERIOD);

        bytes memory payload = abi.encodeWithSignature("transfer(address,uint256)", WETH, tokenAmountTargetToMove);

        delayModule.executeNextTx(EURE, 0, payload, Enum.Operation.Call);

        (canExec, execPayload) = roboModule.checker();
        (bytes memory dataWithoutSelector, bytes4 selector) = _extractEncodeDataWithoutSelector(execPayload);
        (RoboSaverVirtualModule.PoolAction _action, uint256 _amount) =
            abi.decode(dataWithoutSelector, (RoboSaverVirtualModule.PoolAction, uint256));

        assertTrue(canExec, "CanExec: not executable");
        assertEq(selector, ADJUST_POOL_SELECTOR, "Selector: not adjust pool (0xba2f0056)");
        assertEq(
            uint8(_action), uint8(RoboSaverVirtualModule.PoolAction.WITHDRAW), "PoolAction: not withdrawal from pool"
        );

        uint256 initialEureBal = IERC20(EURE).balanceOf(GNOSIS_SAFE);

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
            address(roboModule.BALANCER_VAULT()),
            "Target: expected to be the BALANCER_VAULT address"
        );

        vm.warp(block.timestamp + COOL_DOWN_PERIOD);

        IVault.ExitPoolRequest memory request =
            abi.decode(abi.decode(entries[1].data, (bytes)), (IVault.ExitPoolRequest));

        bytes memory execTxPayload = abi.encodeWithSelector(
            IVault.exitPool.selector, roboModule.BPT_STEUR_EURE_POOL_ID(), GNOSIS_SAFE, payable(GNOSIS_SAFE), request
        );
        delayModule.executeNextTx(address(roboModule.BALANCER_VAULT()), 0, execTxPayload, Enum.Operation.Call);

        assertLt(
            IERC20(BPT_STEUR_EURE).balanceOf(GNOSIS_SAFE),
            initialBptBal,
            "BPT balance: not decreased after withdrawing from the pool"
        );
        assertGt(
            IERC20(EURE).balanceOf(GNOSIS_SAFE),
            initialEureBal,
            "EURE balance: not increased after withdrawing from the pool"
        );
    }
}
