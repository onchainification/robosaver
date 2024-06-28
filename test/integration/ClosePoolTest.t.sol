// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@gnosispay-kit/interfaces/IERC20.sol";

import {BaseFixture} from "../BaseFixture.sol";

import {VirtualModule} from "../../src/types/DataTypes.sol";

contract ClosePoolTest is BaseFixture {
    function testClosePool() public {
        _assertCheckerFalseNoDeficitNorSurplus();

        // balance=240, dailyAllowance=200, buffer=50
        // deposit 100
        vm.startPrank(keeper);
        roboModule.performUpkeep(abi.encode(VirtualModule.PoolAction.DEPOSIT, 100e18));
        vm.warp(block.timestamp + COOLDOWN_PERIOD);
        roboModule.performUpkeep(abi.encode(VirtualModule.PoolAction.EXEC_QUEUE_POOL_ACTION, 1));
        vm.stopPrank();

        // // set buffer to > dailyAllowance + ~poolBalance
        vm.prank(address(safe));
        roboModule.setBuffer(500e18);

        // this should now trigger a pool close
        (bool canExec, bytes memory execPayload) = roboModule.checkUpkeep("");
        assertTrue(canExec);
        (VirtualModule.PoolAction _action,) = abi.decode(execPayload, (VirtualModule.PoolAction, uint256));
        assertEq(uint8(_action), uint8(VirtualModule.PoolAction.CLOSE));

        // exec it and check if pool is closed
        vm.startPrank(keeper);
        roboModule.performUpkeep(execPayload);
        vm.warp(block.timestamp + COOLDOWN_PERIOD);
        roboModule.performUpkeep(abi.encode(VirtualModule.PoolAction.EXEC_QUEUE_POOL_ACTION, 0));
        assertEq(IERC20(BPT_STEUR_EURE).balanceOf(address(safe)), 0);
    }
}
