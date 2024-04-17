// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {BaseFixture} from "./BaseFixture.sol";

import {IERC20} from "@gnosispay-kit/interfaces/IERC20.sol";

import {Enum} from "../lib/delay-module/node_modules/@gnosis.pm/safe-contracts/contracts/common/Enum.sol";

contract TransferErc20Test is BaseFixture {
    function test_transferErc20() public {
        uint256 tokenAmount = 1e18;

        uint256 prevEureBalance = IERC20(EURE).balanceOf(WETH);

        roboModule.transferErc20(EURE, tokenAmount, WETH);

        vm.warp(block.timestamp + COOL_DOWN_PERIOD);

        bytes memory payload = abi.encodeWithSignature("transfer(address,uint256)", WETH, tokenAmount);

        delayModule.executeNextTx(EURE, 0, payload, Enum.Operation.Call);

        assertEq(IERC20(EURE).balanceOf(WETH), prevEureBalance + tokenAmount);
    }
}
