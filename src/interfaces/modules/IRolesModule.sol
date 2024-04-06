// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.4;

interface Roles {
    type ExecutionOptions is uint8;
    type Operation is uint8;
    type Operator is uint8;
    type ParameterType is uint8;
    type Status is uint8;

    struct ConditionFlat {
        uint8 parent;
        ParameterType paramType;
        Operator operator;
        bytes compValue;
    }

    error AlreadyDisabledModule(address module);
    error AlreadyEnabledModule(address module);
    error ArraysDifferentLength();
    error CalldataOutOfBounds();
    error ConditionViolation(Status status, bytes32 info);
    error FunctionSignatureTooShort();
    error HashAlreadyConsumed(bytes32);
    error InvalidInitialization();
    error InvalidModule(address module);
    error InvalidPageSize();
    error MalformedMultiEntrypoint();
    error ModuleTransactionFailed();
    error NoMembership();
    error NotAuthorized(address sender);
    error NotInitializing();
    error OwnableInvalidOwner(address owner);
    error OwnableUnauthorizedAccount(address account);
    error SetupModulesAlreadyCalled();

    event AllowFunction(bytes32 roleKey, address targetAddress, bytes4 selector, ExecutionOptions options);
    event AllowTarget(bytes32 roleKey, address targetAddress, ExecutionOptions options);
    event AssignRoles(address module, bytes32[] roleKeys, bool[] memberOf);
    event AvatarSet(address indexed previousAvatar, address indexed newAvatar);
    event ConsumeAllowance(bytes32 allowanceKey, uint128 consumed, uint128 newBalance);
    event DisabledModule(address module);
    event EnabledModule(address module);
    event ExecutionFromModuleFailure(address indexed module);
    event ExecutionFromModuleSuccess(address indexed module);
    event HashExecuted(bytes32);
    event HashInvalidated(bytes32);
    event Initialized(uint64 version);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event RevokeFunction(bytes32 roleKey, address targetAddress, bytes4 selector);
    event RevokeTarget(bytes32 roleKey, address targetAddress);
    event RolesModSetup(address indexed initiator, address indexed owner, address indexed avatar, address target);
    event ScopeFunction(
        bytes32 roleKey, address targetAddress, bytes4 selector, ConditionFlat[] conditions, ExecutionOptions options
    );
    event ScopeTarget(bytes32 roleKey, address targetAddress);
    event SetAllowance(
        bytes32 allowanceKey, uint128 balance, uint128 maxRefill, uint128 refill, uint64 period, uint64 timestamp
    );
    event SetDefaultRole(address module, bytes32 defaultRoleKey);
    event SetUnwrapAdapter(address to, bytes4 selector, address adapter);
    event TargetSet(address indexed previousTarget, address indexed newTarget);

    function allowFunction(bytes32 roleKey, address targetAddress, bytes4 selector, ExecutionOptions options)
        external;
    function allowTarget(bytes32 roleKey, address targetAddress, ExecutionOptions options) external;
    function allowances(bytes32)
        external
        view
        returns (uint128 refill, uint128 maxRefill, uint64 period, uint128 balance, uint64 timestamp);
    function assignRoles(address module, bytes32[] memory roleKeys, bool[] memory memberOf) external;
    function avatar() external view returns (address);
    function consumed(address, bytes32) external view returns (bool);
    function defaultRoles(address) external view returns (bytes32);
    function disableModule(address prevModule, address module) external;
    function enableModule(address module) external;
    function execTransactionFromModule(address to, uint256 value, bytes memory data, Operation operation)
        external
        returns (bool success);
    function execTransactionFromModuleReturnData(address to, uint256 value, bytes memory data, Operation operation)
        external
        returns (bool success, bytes memory returnData);
    function execTransactionWithRole(
        address to,
        uint256 value,
        bytes memory data,
        Operation operation,
        bytes32 roleKey,
        bool shouldRevert
    ) external returns (bool success);
    function execTransactionWithRoleReturnData(
        address to,
        uint256 value,
        bytes memory data,
        Operation operation,
        bytes32 roleKey,
        bool shouldRevert
    ) external returns (bool success, bytes memory returnData);
    function getModulesPaginated(address start, uint256 pageSize)
        external
        view
        returns (address[] memory array, address next);
    function invalidate(bytes32 hash) external;
    function isModuleEnabled(address _module) external view returns (bool);
    function moduleTxHash(bytes memory data, bytes32 salt) external view returns (bytes32);
    function owner() external view returns (address);
    function renounceOwnership() external;
    function revokeFunction(bytes32 roleKey, address targetAddress, bytes4 selector) external;
    function revokeTarget(bytes32 roleKey, address targetAddress) external;
    function scopeFunction(
        bytes32 roleKey,
        address targetAddress,
        bytes4 selector,
        ConditionFlat[] memory conditions,
        ExecutionOptions options
    ) external;
    function scopeTarget(bytes32 roleKey, address targetAddress) external;
    function setAllowance(
        bytes32 key,
        uint128 balance,
        uint128 maxRefill,
        uint128 refill,
        uint64 period,
        uint64 timestamp
    ) external;
    function setAvatar(address _avatar) external;
    function setDefaultRole(address module, bytes32 roleKey) external;
    function setTarget(address _target) external;
    function setTransactionUnwrapper(address to, bytes4 selector, address adapter) external;
    function setUp(bytes memory initParams) external;
    function target() external view returns (address);
    function transferOwnership(address newOwner) external;
    function unwrappers(bytes32) external view returns (address);
}
