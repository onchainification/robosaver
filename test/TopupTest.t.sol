// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {BaseFixture} from "./BaseFixture.sol";

import {IERC20} from "@gnosispay-kit/interfaces/IERC20.sol";

import {Enum} from "../lib/delay-module/node_modules/@gnosis.pm/safe-contracts/contracts/common/Enum.sol";

contract TopupTest is BaseFixture {
    function testTopupChecker() public {
        (bool canExec, bytes memory execPayload) = roboModule.checker();

        assertFalse(canExec);

        uint256 eureBalance = IERC20(EURE).balanceOf(GNOSIS_SAFE);

        (, uint128 maxRefill,,,) = rolesModule.allowances(SET_ALLOWANCE_KEY);

        uint256 tokenAmountTargetToMove = eureBalance - maxRefill + 1;

        roboModule.transferErc20(EURE, tokenAmountTargetToMove, WETH);

        vm.warp(block.timestamp + COOL_DOWN_PERIOD);

        bytes memory payload = abi.encodeWithSignature("transfer(address,uint256)", WETH, tokenAmountTargetToMove);

        delayModule.executeNextTx(EURE, 0, payload, Enum.Operation.Call);

        (canExec, execPayload) = roboModule.checker();

        assertTrue(canExec);
    }
}
