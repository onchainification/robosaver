// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {console} from "forge-std/Test.sol";

import {BaseFixture} from "./BaseFixture.sol";

import {IMulticall} from "@gnosispay-kit/interfaces/IMulticall.sol";

import "@balancer-v2/interfaces/contracts/vault/IVault.sol";

import {Enum} from "../lib/delay-module/node_modules/@gnosis.pm/safe-contracts/contracts/common/Enum.sol";

contract TopupBptTest is BaseFixture {
    function testTopupBpt() public {
        uint256 initialEureBal = IERC20(EURE).balanceOf(GNOSIS_SAFE);
        uint256 initialBptBal = IERC20(BPT_EURE_STEUR).balanceOf(GNOSIS_SAFE);

        (bool canExec, bytes memory execPayload) = roboModule.checker();

        // since initially it was minted 1000 it should be way above the buffer
        assertTrue(canExec);
        assertEq(bytes4(execPayload), EXEC_TOP_UP_SELECTOR);

        vm.prank(TOP_UP_AGENT);
        (bool success, bytes memory data) = address(roboModule).call(execPayload);
        assertTrue(success);

        vm.warp(block.timestamp + COOL_DOWN_PERIOD);

        // two actions:
        // 1. eure exact appproval to `BALANCER_VAULT`
        // 2. join the pool single sided with the excess
        IMulticall.Call[] memory calls_ = abi.decode(data, (IMulticall.Call[]));

        bytes memory multiCallPayalod = abi.encodeWithSelector(IMulticall.aggregate.selector, calls_);
        delayModule.executeNextTx(roboModule.MULTICALL_V3(), 0, multiCallPayalod, Enum.Operation.DelegateCall);

        assertLt(IERC20(EURE).balanceOf(GNOSIS_SAFE), initialEureBal);
        assertGt(IERC20(BPT_EURE_STEUR).balanceOf(GNOSIS_SAFE), initialBptBal);
    }
}
