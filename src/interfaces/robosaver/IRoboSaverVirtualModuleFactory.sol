// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IRoboSaverVirtualModuleFactory {
    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
    //////////////////////////////////////////////////////////////////////////*/
    event RoboSaverVirtualModuleCreated(address virtualModule, address card, uint256 upkeepId, uint256 timestamp);

    function createVirtualModule(address _delayModule, address _rolesModule, uint256 _buffer, uint16 _slippage)
        external;

    function virtualModules(address) external view returns (address virtualModuleAddress, uint256 upkeepId);
}
