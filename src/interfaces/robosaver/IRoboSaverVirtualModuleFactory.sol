// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IRoboSaverVirtualModuleFactory {
    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
    //////////////////////////////////////////////////////////////////////////*/
    event RoboSaverVirtualModuleCreated(address virtualModule, address card, uint256 upkeepId, uint256 timestamp);
}
