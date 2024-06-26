// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IDelayModifier {
    /// @notice Operation type of module transaction
    /// @custom:value0 Call Executes a specific function within that contract's context
    /// @custom:value1 DelegateCall Executes the called contract's code within the context of the calling contract
    enum DelayModuleOperation {
        Call,
        DelegateCall
    }

    error AlreadyDisabledModule(address module);
    error AlreadyEnabledModule(address module);
    error HashAlreadyConsumed(bytes32);
    error InvalidInitialization();
    error InvalidModule(address module);
    error InvalidPageSize();
    error NotAuthorized(address sender);
    error NotInitializing();
    error OwnableInvalidOwner(address owner);
    error OwnableUnauthorizedAccount(address account);
    error SetupModulesAlreadyCalled();

    event AvatarSet(address indexed previousAvatar, address indexed newAvatar);
    event DelaySetup(address indexed initiator, address indexed owner, address indexed avatar, address target);
    event DisabledModule(address module);
    event EnabledModule(address module);
    event ExecutionFromModuleFailure(address indexed module);
    event ExecutionFromModuleSuccess(address indexed module);
    event HashExecuted(bytes32);
    event HashInvalidated(bytes32);
    event Initialized(uint64 version);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event TargetSet(address indexed previousTarget, address indexed newTarget);
    event TransactionAdded(
        uint256 indexed queueNonce,
        bytes32 indexed txHash,
        address to,
        uint256 value,
        bytes data,
        DelayModuleOperation DelayModuleOperation
    );
    event TxCooldownSet(uint256 cooldown);
    event TxExpirationSet(uint256 expiration);
    event TxNonceSet(uint256 nonce);

    function avatar() external view returns (address);

    function consumed(address, bytes32) external view returns (bool);

    function disableModule(address prevModule, address module) external;

    function enableModule(address module) external;

    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes memory data,
        DelayModuleOperation DelayModuleOperation
    ) external returns (bool success);

    function execTransactionFromModuleReturnData(
        address to,
        uint256 value,
        bytes memory data,
        DelayModuleOperation DelayModuleOperation
    ) external returns (bool success, bytes memory returnData);

    function executeNextTx(address to, uint256 value, bytes memory data, DelayModuleOperation DelayModuleOperation)
        external;

    function getModulesPaginated(address start, uint256 pageSize)
        external
        view
        returns (address[] memory array, address next);

    function getTransactionHash(address to, uint256 value, bytes memory data, DelayModuleOperation DelayModuleOperation)
        external
        pure
        returns (bytes32);

    function getTxCreatedAt(uint256 _nonce) external view returns (uint256);

    function getTxHash(uint256 _nonce) external view returns (bytes32);

    function invalidate(bytes32 hash) external;

    function isModuleEnabled(address _module) external view returns (bool);

    function moduleTxHash(bytes memory data, bytes32 salt) external view returns (bytes32);

    function owner() external view returns (address);

    function queueNonce() external view returns (uint256);

    function renounceOwnership() external;

    function setAvatar(address _avatar) external;

    function setTarget(address _target) external;

    function setTxCooldown(uint256 _txCooldown) external;

    function setTxExpiration(uint256 _txExpiration) external;

    function setTxNonce(uint256 _txNonce) external;

    function setUp(bytes memory initParams) external;

    function skipExpired() external;

    function transferOwnership(address newOwner) external;

    function txCooldown() external view returns (uint256);

    function txCreatedAt(uint256) external view returns (uint256);

    function txExpiration() external view returns (uint256);

    function txHash(uint256) external view returns (bytes32);

    function txNonce() external view returns (uint256);
}
