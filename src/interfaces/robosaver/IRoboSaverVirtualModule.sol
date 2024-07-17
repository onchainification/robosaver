// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IRoboSaverVirtualModule {
    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a transaction to close the pool has been queued up
    /// @param safe The address of the card
    /// @param amount The minimum amount of $EURe to receive from the pool closure
    /// @param timestamp The timestamp of the transaction
    event PoolCloseQueued(address indexed safe, uint256 amount, uint256 timestamp);

    /// @notice Emitted when a transaction to withdrawal from the pool has been queued up
    /// @param safe The address of the card
    /// @param amount The amount of $EURe to withdraw from the pool
    /// @param timestamp The timestamp of the transaction
    event PoolWithdrawalQueued(address indexed safe, uint256 amount, uint256 timestamp);

    /// @notice Emitted when a transaction to deposit into the pool has been queued up
    /// @param safe The address of the card
    /// @param amount The amount of $EURe to deposit into the pool
    /// @param timestamp The timestamp of the transaction
    event PoolDepositQueued(address indexed safe, uint256 amount, uint256 timestamp);

    /// @notice Emitted when a transaction to stake the residual bpt on the card has been queued up
    /// @param safe The address of the card
    /// @param amount The amount of bpt that is being staked
    /// @param timestamp The timestamp of the transaction
    event StakeQueued(address indexed safe, uint256 amount, uint256 timestamp);

    /// @notice Emitted when a transaction to shutdown RoboSaver has been queued up
    /// @param safe The address of the card
    /// @param amount The minimum amount of $EURe to receive from the pool closure
    /// @param timestamp The timestamp of the transaction
    event PoolShutdownQueued(address indexed safe, uint256 amount, uint256 timestamp);

    /// @notice Emitted when an adjustment pool transaction is being queued up
    /// @dev Event is leverage by off-chain service to execute the queued transaction
    /// @param target The address of the target contract
    /// @param payload The payload of the transaction to be executed on the target contract
    /// @param queueNonce The nonce of the queued transaction
    event AdjustPoolTxDataQueued(address indexed target, bytes payload, uint256 queueNonce);

    /// @notice Emitted when an adjustment pool transaction is executed in the delay module
    /// @param target The address of the target contract
    /// @param payload The payload of the transaction executed on the target contract
    /// @param nonce The nonce of the executed transaction tracking the delay module counting
    /// @param timestamp The timestamp of the transaction
    event AdjustPoolTxExecuted(address indexed target, bytes payload, uint256 nonce, uint256 timestamp);

    /// @notice Emitted when the admin sets a new keeper address
    /// @param admin The address of the admin
    /// @param oldKeeper The address of the old keeper
    /// @param newKeeper The address of the new keeper
    event SetKeeper(address indexed admin, address oldKeeper, address newKeeper);

    /// @notice Emitted when the admin sets a new buffer value
    /// @param admin The address of the contract admin
    /// @param oldBuffer The value of the old buffer
    /// @param newBuffer The value of the new buffer
    event SetBuffer(address indexed admin, uint256 oldBuffer, uint256 newBuffer);

    /// @notice Emitted when the admin sets a new slippage value
    /// @param admin The address of the admin
    /// @param oldSlippage The value of the old slippage
    /// @param newSlippage The value of the new slippage
    event SetSlippage(address indexed admin, uint256 oldSlippage, uint256 newSlippage);

    function CARD() external view returns (address);

    function FACTORY() external view returns (address);

    function name() external pure returns (string memory);

    function queuedTx() external view returns (uint256 nonce, address target, bytes memory payload);

    function setBuffer(uint256 _buffer) external;

    function setKeeper(address _keeper) external;

    function setSlippage(uint16 _slippage) external;

    function shutdown() external;

    function slippage() external view returns (uint16);

    function version() external pure returns (string memory);
}
