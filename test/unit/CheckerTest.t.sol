// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {BaseFixture} from "../BaseFixture.sol";

import {IERC20} from "@gnosispay-kit/interfaces/IERC20.sol";

import {Enum} from "../../lib/delay-module/node_modules/@gnosis.pm/safe-contracts/contracts/common/Enum.sol";

import {VirtualModule} from "../../src/types/DataTypes.sol";

contract CheckerTest is BaseFixture {
    function testChecker_When_TopupIsRequired() public {
        _assertCheckerFalseNoDeficitNorSurplus();

        uint256 tokenAmountTargetToMove = _transferOutBelowThreshold();

        vm.warp(block.timestamp + COOLDOWN_PERIOD);

        bytes memory payload = abi.encodeWithSignature("transfer(address,uint256)", WETH, tokenAmountTargetToMove);

        delayModule.executeNextTx(EURE, 0, payload, Enum.Operation.Call);

        (bool canExec, bytes memory execPayload) = roboModule.checkUpkeep("");
        (VirtualModule.PoolAction _action, uint256 _amount) =
            abi.decode(execPayload, (VirtualModule.PoolAction, uint256));
        assertTrue(canExec, "CanExec: not executable");
        assertEq(uint8(_action), uint8(VirtualModule.PoolAction.WITHDRAW), "PoolAction: not withdrawing from the pool");
        assertGt(_amount, 0);
    }

    function testChecker_When_TxIsOnQueue() public {
        _assertCheckerFalseNoDeficitNorSurplus();

        // queue a tx, leverage the `_transferOutBelowThreshold` function from base fixture
        _transferOutBelowThreshold();

        (bool canExec, bytes memory execPayload) = roboModule.checkUpkeep("");

        assertFalse(canExec);
        assertEq(execPayload, bytes("External transaction in queue, wait for it to be executed"));
    }

    function testChecker_When_NoStakedBalance() public {
        _assertCheckerFalseNoDeficitNorSurplus();

        // move out $EURe to get into `balance < dailyAllowance` flow and ensure BPT balance is null
        uint256 tokenAmountTargetToMove = _transferOutBelowThreshold();
        vm.warp(block.timestamp + COOLDOWN_PERIOD);
        bytes memory payload = abi.encodeWithSignature("transfer(address,uint256)", WETH, tokenAmountTargetToMove);
        delayModule.executeNextTx(EURE, 0, payload, Enum.Operation.Call);

        vm.mockCall(
            address(AURA_GAUGE_STEUR_EURE), abi.encodeWithSelector(IERC20.balanceOf.selector, address(safe)), abi.encode(0)
        );
        assertEq(IERC20(AURA_GAUGE_STEUR_EURE).balanceOf(address(safe)), 0);

        (bool canExec, bytes memory execPayload) = roboModule.checkUpkeep("");
        vm.clearMockedCalls();
        assertFalse(canExec);
        assertEq(execPayload, bytes("No staked BPT balance on the card"));
    }

    function testChecker_When_internalTxIsQueued() public {
        // 1. assert that internal tx is being queued and within cooldown
        vm.prank(keeper);
        roboModule.performUpkeep(abi.encode(VirtualModule.PoolAction.DEPOSIT, 1000));

        (bool canExec, bytes memory execPayload) = roboModule.checkUpkeep("");
        assertFalse(canExec);
        assertEq(execPayload, bytes("Internal transaction in cooldown status"));

        // 2.1 fwd time still within cooldown
        vm.warp(block.timestamp + 50);
        (canExec, execPayload) = roboModule.checkUpkeep("");
        assertFalse(canExec);
        assertEq(execPayload, bytes("Internal transaction in cooldown status"));

        // 2.2. fwd time beyond cooldown
        vm.warp(block.timestamp + COOLDOWN_PERIOD);

        // 3. assert that checker returns true and action type `EXEC_QUEUE_POOL_ACTION`
        (canExec, execPayload) = roboModule.checkUpkeep("");
        assertTrue(canExec);

        (VirtualModule.PoolAction _action, uint256 _amount) =
            abi.decode(execPayload, (VirtualModule.PoolAction, uint256));
        assertEq(uint8(_action), uint8(VirtualModule.PoolAction.EXEC_QUEUE_POOL_ACTION));
        assertEq(_amount, 0);
    }

    function testChecker_When_VirtualModuleDisabled() public {
        vm.prank(address(safe));
        // `disableModule(address prevModule, address module)`
        delayModule.disableModule(address(safe), address(roboModule));

        (bool canExec, bytes memory execPayload) = roboModule.checkUpkeep("");
        assertFalse(canExec);
        assertEq(execPayload, bytes("Virtual module is not enabled"));
    }
}
