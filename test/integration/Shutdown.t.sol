// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@gnosispay-kit/interfaces/IERC20.sol";

import {BaseFixture} from "../BaseFixture.sol";
import {VirtualModule} from "../../src/types/DataTypes.sol";

contract ShutdownTest is BaseFixture {
    function testShutdown() public {
        // create a residual bpt balance to confirm it also gets processed in the shutdown
        deal(BPT_STEUR_EURE, address(roboModule.CARD()), 1e18);

        // confirm there are (staked) pool positions
        assertGt(AURA_GAUGE_STEUR_EURE.balanceOf(address(roboModule.CARD())), 0);
        assertGt(IERC20(BPT_STEUR_EURE).balanceOf(address(roboModule.CARD())), 0);
        uint256 initialEureBalance = IERC20(EURE).balanceOf(roboModule.CARD());

        // trigger the shutdown and execute it on the delay module
        vm.prank(roboModule.CARD());
        roboModule.shutdown();
        vm.warp(block.timestamp + COOLDOWN_PERIOD);
        vm.startPrank(keeper);
        roboModule.performUpkeep(abi.encode(VirtualModule.PoolAction.EXEC_QUEUE_POOL_ACTION, 0));

        // confirm all (staked) pool positions are now gone and the $eure balance increased
        assertEq(AURA_GAUGE_STEUR_EURE.balanceOf(address(roboModule.CARD())), 0);
        assertEq(IERC20(BPT_STEUR_EURE).balanceOf(address(roboModule.CARD())), 0);
        assertGt(IERC20(EURE).balanceOf(roboModule.CARD()), initialEureBalance);

        // confirm the virtual module is turned off
        assertFalse(delayModule.isModuleEnabled(address(roboModule)));
    }
}
