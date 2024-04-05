// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {BaseFixture} from "./BaseFixture.sol";

import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {Enum} from "../lib/delay-module/node_modules/@gnosis.pm/safe-contracts/contracts/common/Enum.sol";

contract TransferErc20Test is BaseFixture {
    function test_transferErc20() public {
        uint256 tokenAmount = 10e18;

        roboModule.transferErc20(EUR_E, tokenAmount, WETH);

        vm.warp(block.timestamp + COOL_DOWN_PERIOD);

        bytes memory payload = abi.encodeWithSignature("transfer(address,uint256)", WETH, tokenAmount);

        vm.mockCall(EUR_E, abi.encodeWithSelector(IERC20.balanceOf.selector, GNOSIS_SAFE), abi.encode(tokenAmount));

        delayModule.executeNextTx(EUR_E, 0, payload, Enum.Operation.Call);
    }
}
