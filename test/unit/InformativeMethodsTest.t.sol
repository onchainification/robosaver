// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.25;

import {BaseFixture} from "../BaseFixture.sol";

/// @notice Suite is focus mainly in the following methods for coverage:
/// - `RoboSaverVirtualModule.name()`
/// - `RoboSaverVirtualModule.version()`
contract InformativeMethodsTest is BaseFixture {
    function testName() public view {
        assertEq(roboModule.name(), "RoboSaverVirtualModule-EURE", "Name: not matching");
    }

    function testVersion() public view {
        assertEq(roboModule.version(), "v0.1.0", "Version: not matching");
    }

    /// @dev include here any other method which may be simply informative. e.g: assets, balances etc
}
