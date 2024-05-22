// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {BaseFixture} from "./BaseFixture.sol";

import {RoboSaverVirtualModule} from "../src/RoboSaverVirtualModule.sol";

contract SettersTest is BaseFixture {
    function test_RevertWhen_BufferZeroValue() public {
        vm.prank(roboModule.CARD());
        vm.expectRevert(abi.encodeWithSelector(RoboSaverVirtualModule.ZeroUintValue.selector));
        roboModule.setBuffer(0);
    }

    function test_RevertWhen_KeeperZeroAddress() public {
        vm.prank(roboModule.CARD());
        vm.expectRevert(abi.encodeWithSelector(RoboSaverVirtualModule.ZeroAddressValue.selector));
        roboModule.setKeeper(address(0));
    }

    function test_RevertWhen_CallerNotAdmin() public {
        address randomCaller = address(4343534);

        vm.prank(randomCaller);
        vm.expectRevert(abi.encodeWithSelector(RoboSaverVirtualModule.NotAdmin.selector, randomCaller));
        roboModule.setBuffer(1000);

        vm.prank(randomCaller);
        vm.expectRevert(abi.encodeWithSelector(RoboSaverVirtualModule.NotAdmin.selector, randomCaller));
        roboModule.setKeeper(address(554));
    }

    function testSetBuffer() public {
        uint256 newBuffer = 1000;
        uint256 oldBuffer = roboModule.buffer();

        vm.expectEmit(true, true, true, true);
        emit RoboSaverVirtualModule.SetBuffer(roboModule.CARD(), oldBuffer, newBuffer);

        vm.prank(roboModule.CARD());
        roboModule.setBuffer(newBuffer);

        assertEq(roboModule.buffer(), newBuffer, "Buffer: not matching newBuffer value");
    }

    function testSetKeeper() public {
        address newKeeper = address(0x123);
        address oldKeeper = roboModule.keeper();

        vm.expectEmit(true, true, true, true);
        emit RoboSaverVirtualModule.SetKeeper(roboModule.CARD(), oldKeeper, newKeeper);

        vm.prank(roboModule.CARD());
        roboModule.setKeeper(newKeeper);

        assertEq(roboModule.keeper(), newKeeper, "Keeper: not matching newKeeper address");
    }
}
