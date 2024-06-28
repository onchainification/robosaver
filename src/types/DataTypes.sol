// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @notice Namespace for the structs used in {RoboSaverVirtualModule}.
library VirtualModule {
    /// @notice Enum representing the different types of pool actions
    /// @custom:value0 WITHDRAW Withdraw $EURe from the pool to the card
    /// @custom:value1 DEPOSIT Deposit $EURe from the card into the pool
    /// @custom:value2 CLOSE Close the pool position by withdrawing all to $EURe
    /// @custom:value3 EXEC_QUEUE_POOL_ACTION Execute the queued pool action
    enum PoolAction {
        WITHDRAW,
        DEPOSIT,
        CLOSE,
        EXEC_QUEUE_POOL_ACTION
    }

    /// @notice Struct representing the data needed to execute a queued transaction
    /// @dev Nonce allows us to determine if the transaction queued originated from this virtual module
    /// @param nonce The nonce of the queued transaction
    /// @param target The address of the target contract
    /// @param payload The payload of the transaction to be executed on the target contract
    struct QueuedTx {
        uint256 nonce;
        address target;
        bytes payload;
    }
}

/// @notice Namespace for the structs used in {RoboSaverVirtualModuleFactory}.
library Factory {
    /// @notice Struct representing the data details of each registered virtual module in the Chainlink automation service
    /// @param virtualModuleAddress The address of the virtual module
    /// @param upkeepId The ID of the upkeep registered in Chainlink for the virtual module
    struct VirtualModuleDetails {
        address virtualModuleAddress;
        uint256 upkeepId;
    }
}
