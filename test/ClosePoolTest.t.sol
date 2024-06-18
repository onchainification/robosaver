// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@gnosispay-kit/interfaces/IERC20.sol";

import {BaseFixture} from "./BaseFixture.sol";

import {RoboSaverVirtualModule} from "../src/RoboSaverVirtualModule.sol";

contract ClosePoolTest is BaseFixture {
    function testClosePool() public {
        _assertCheckerFalseNoDeficitNorSurplus();

        // balance=240, dailyAllowance=200, buffer=50
        // deposit 100
        vm.startPrank(KEEPER);
        roboModule.adjustPool(RoboSaverVirtualModule.PoolAction.DEPOSIT, 100e18);
        vm.warp(block.timestamp + COOLDOWN_PERIOD);
        roboModule.adjustPool(RoboSaverVirtualModule.PoolAction.EXEC_QUEUE_POOL_ACTION, 1);
        vm.stopPrank();

        // // set buffer to > dailyAllowance + ~poolBalance
        vm.prank(address(safe));
        roboModule.setBuffer(500e18);

        // this should now trigger a pool close
        (bool canExec, bytes memory execPayload) = roboModule.checker();
        assertTrue(canExec);
        (bytes memory dataWithoutSelector,) = _extractEncodeDataWithoutSelector(execPayload);
        (RoboSaverVirtualModule.PoolAction _action, uint256 _amount) =
            abi.decode(dataWithoutSelector, (RoboSaverVirtualModule.PoolAction, uint256));
        assertEq(uint8(_action), uint8(RoboSaverVirtualModule.PoolAction.CLOSE));

        // exec it and check if pool is closed
        vm.startPrank(KEEPER);
        roboModule.adjustPool(_action, _amount);
        vm.warp(block.timestamp + COOLDOWN_PERIOD);
        roboModule.adjustPool(RoboSaverVirtualModule.PoolAction.EXEC_QUEUE_POOL_ACTION, 0);
        assertEq(IERC20(BPT_STEUR_EURE).balanceOf(address(safe)), 0);
    }
}
