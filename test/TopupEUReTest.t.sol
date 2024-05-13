// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {BaseFixture} from "./BaseFixture.sol";

import "@balancer-v2/interfaces/contracts/vault/IVault.sol";

import {Enum} from "../lib/delay-module/node_modules/@gnosis.pm/safe-contracts/contracts/common/Enum.sol";

import {RoboSaverVirtualModule} from "../src/RoboSaverVirtualModule.sol";

contract TopupTest is BaseFixture {
    function testTopupChecker() public {
        (bool canExec, bytes memory execPayload) = roboModule.checker();

        // @note since there is logic also on the buffer up, here the conditional will trigger bpt topup
        // but on this test we are not interested on that dynamic
        assertTrue(canExec);
        assertEq(bytes4(execPayload), ADJUST_POOL_SELECTOR);

        uint256 tokenAmountTargetToMove = _transferOutBelowThreshold();

        vm.warp(block.timestamp + COOL_DOWN_PERIOD);

        bytes memory payload = abi.encodeWithSignature("transfer(address,uint256)", WETH, tokenAmountTargetToMove);

        delayModule.executeNextTx(EURE, 0, payload, Enum.Operation.Call);

        (canExec, execPayload) = roboModule.checker();

        assertTrue(canExec, "CanExec: not executable");
        assertEq(bytes4(execPayload), ADJUST_POOL_SELECTOR, "Selector: not adjust pool (0xafd738d0)");
    }

    // @note ref for error codes: https://docs.balancer.fi/reference/contracts/error-codes.html#error-codes
    function testExitPool() public {
        uint256 initialBptBal = IERC20(BPT_STEUR_EURE).balanceOf(GNOSIS_SAFE);

        uint256 tokenAmountTargetToMove = _transferOutBelowThreshold();

        vm.warp(block.timestamp + COOL_DOWN_PERIOD);

        bytes memory payload = abi.encodeWithSignature("transfer(address,uint256)", WETH, tokenAmountTargetToMove);

        delayModule.executeNextTx(EURE, 0, payload, Enum.Operation.Call);

        (bool canExec, bytes memory execPayload) = roboModule.checker();
        (bytes memory dataWithoutSelector, bytes4 selector) = _extractEncodeDataWithoutSelector(execPayload);
        (RoboSaverVirtualModule.PoolAction _action, address _card, uint256 _amount) =
            abi.decode(dataWithoutSelector, (RoboSaverVirtualModule.PoolAction, address, uint256));

        assertTrue(canExec, "CanExec: not executable");
        assertEq(selector, ADJUST_POOL_SELECTOR, "Selector: not adjust pool (0xafd738d0)");
        assertEq(
            uint8(_action), uint8(RoboSaverVirtualModule.PoolAction.WITHDRAW), "PoolAction: not withdrawal from pool"
        );

        uint256 initialEureBal = IERC20(EURE).balanceOf(GNOSIS_SAFE);

        vm.prank(TOP_UP_AGENT);
        bytes memory execPayload_ = roboModule.adjustPool(_action, _card, _amount);

        vm.warp(block.timestamp + COOL_DOWN_PERIOD);

        IVault.ExitPoolRequest memory request = abi.decode(execPayload_, (IVault.ExitPoolRequest));

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
