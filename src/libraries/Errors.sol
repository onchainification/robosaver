// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @title Errors
/// @notice Library containing all custom errors the smart contracts may revert with.
library Errors {
    /*//////////////////////////////////////////////////////////////////////////
                                VIRTUAL MODULE
    //////////////////////////////////////////////////////////////////////////*/
    error NotKeeper(address agent);
    error NotAdmin(address agent);
    error NeitherAdminNorFactory(address agent);

    error ZeroAddressValue();
    error ZeroUintValue();

    error TooHighBps();

    error ExternalTxIsQueued();
    error VirtualModuleNotEnabled();

    /*//////////////////////////////////////////////////////////////////////////
                                   FACTORY
    //////////////////////////////////////////////////////////////////////////*/
    error UpkeepZero();

    error CallerNotMatchingAvatar(string moduleName, address caller);
}
