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

        uint256 eureBeforeCloseBalance = IERC20(EURE).balanceOf(address(safe));

        // this should now trigger a pool close
        // first part: unstake and claim rewards
        (bool canExec, bytes memory execPayload) = roboModule.checkUpkeep("");
        assertTrue(canExec);
        (VirtualModule.PoolAction _action, uint256 _amount) =
            abi.decode(execPayload, (VirtualModule.PoolAction, uint256));

        assertEq(uint8(_action), uint8(VirtualModule.PoolAction.CLOSE));
        assertEq(IERC20(BPT_STEUR_EURE).balanceOf(address(safe)), 0, "clean up residual bpt first!");

        // exec it and check if stake and bpt are gone
        vm.startPrank(keeper);
        roboModule.performUpkeep(execPayload);
        vm.warp(block.timestamp + COOLDOWN_PERIOD);
        roboModule.performUpkeep(abi.encode(VirtualModule.PoolAction.EXEC_QUEUE_POOL_ACTION, 0));

        assertEq(IERC20(AURA_GAUGE_STEUR_EURE).balanceOf(address(safe)), 0);
        assertEq(IERC20(BPT_STEUR_EURE).balanceOf(address(safe)), 0);
        assertGe(IERC20(EURE).balanceOf(address(safe)), eureBeforeCloseBalance + _amount);

        // @todo check for claimed rewards (bal, aura)
    }
}
