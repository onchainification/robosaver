// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {BaseFixture} from "./BaseFixture.sol";

import "@balancer-v2/interfaces/contracts/vault/IVault.sol";

import {Enum} from "../lib/delay-module/node_modules/@gnosis.pm/safe-contracts/contracts/common/Enum.sol";

contract TopupTest is BaseFixture {
    function testTopupChecker() public {
        (bool canExec, bytes memory execPayload) = roboModule.checker();

        assertFalse(canExec);

        uint256 tokenAmountTargetToMove = _transferOutBelowThreshold();

        vm.warp(block.timestamp + COOL_DOWN_PERIOD);

        bytes memory payload = abi.encodeWithSignature("transfer(address,uint256)", WETH, tokenAmountTargetToMove);

        delayModule.executeNextTx(EURE, 0, payload, Enum.Operation.Call);

        (canExec, execPayload) = roboModule.checker();

        assertTrue(canExec);
    }

    // @note ref for error codes: https://docs.balancer.fi/reference/contracts/error-codes.html#error-codes
    function testExitPool() public {
        uint256 initialBptBal = IERC20(BPT_EURE_STEUR).balanceOf(GNOSIS_SAFE);

        uint256 tokenAmountTargetToMove = _transferOutBelowThreshold();

        vm.warp(block.timestamp + COOL_DOWN_PERIOD);

        bytes memory payload = abi.encodeWithSignature("transfer(address,uint256)", WETH, tokenAmountTargetToMove);

        delayModule.executeNextTx(EURE, 0, payload, Enum.Operation.Call);

        (bool canExec, bytes memory execPayload) = roboModule.checker();

        assertTrue(canExec);
        assertEq(bytes4(execPayload), SAFE_TOP_UP_SELECTOR);

        uint256 initialEureBal = IERC20(EURE).balanceOf(GNOSIS_SAFE);

        vm.prank(TOP_UP_AGENT);
        (bool success, bytes memory data) = address(roboModule).call(execPayload);
        assertTrue(success);

        vm.warp(block.timestamp + COOL_DOWN_PERIOD);

        IVault.ExitPoolRequest memory request = abi.decode(data, (IVault.ExitPoolRequest));

        bytes memory execTxPayload = abi.encodeWithSelector(
            IVault.exitPool.selector, roboModule.BPT_EURE_STEUR_POOL_ID(), GNOSIS_SAFE, payable(GNOSIS_SAFE), request
        );
        delayModule.executeNextTx(address(roboModule.BALANCER_VAULT()), 0, execTxPayload, Enum.Operation.Call);

        assertLt(IERC20(BPT_EURE_STEUR).balanceOf(GNOSIS_SAFE), initialBptBal);
        assertGt(IERC20(EURE).balanceOf(GNOSIS_SAFE), initialEureBal);
    }

    function _transferOutBelowThreshold() internal returns (uint256 tokenAmountTargetToMove_) {
        uint256 eureBalance = IERC20(EURE).balanceOf(GNOSIS_SAFE);

        (, uint128 maxRefill,,,) = rolesModule.allowances(SET_ALLOWANCE_KEY);

        tokenAmountTargetToMove_ = eureBalance - maxRefill + 100e18;

        roboModule.transferErc20(EURE, tokenAmountTargetToMove_, WETH);
    }
}
