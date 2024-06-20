// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IKeeperRegistrar {
    struct InitialTriggerConfig {
        uint8 triggerType;
        uint8 autoApproveType;
        uint32 autoApproveMaxAllowed;
    }

    struct TriggerRegistrationStorage {
        uint8 autoApproveType;
        uint32 autoApproveMaxAllowed;
        uint32 approvedCount;
    }

    struct RegistrationParams {
        string name;
        bytes encryptedEmail;
        address upkeepContract;
        uint32 gasLimit;
        address adminAddress;
        uint8 triggerType;
        bytes checkData;
        bytes triggerConfig;
        bytes offchainConfig;
        uint96 amount;
    }

    error AmountMismatch();
    error FunctionNotPermitted();
    error HashMismatch();
    error InsufficientPayment();
    error InvalidAdminAddress();
    error InvalidDataLength();
    error LinkTransferFailed(address to);
    error OnlyAdminOrOwner();
    error OnlyLink();
    error RegistrationRequestFailed();
    error RequestNotFound();
    error SenderMismatch();

    event AutoApproveAllowedSenderSet(address indexed senderAddress, bool allowed);
    event ConfigChanged(address keeperRegistry, uint96 minLINKJuels);
    event OwnershipTransferRequested(address indexed from, address indexed to);
    event OwnershipTransferred(address indexed from, address indexed to);
    event RegistrationApproved(bytes32 indexed hash, string displayName, uint256 indexed upkeepId);
    event RegistrationRejected(bytes32 indexed hash);
    event RegistrationRequested(
        bytes32 indexed hash,
        string name,
        bytes encryptedEmail,
        address indexed upkeepContract,
        uint32 gasLimit,
        address adminAddress,
        uint8 triggerType,
        bytes triggerConfig,
        bytes offchainConfig,
        bytes checkData,
        uint96 amount
    );
    event TriggerConfigSet(uint8 triggerType, uint8 autoApproveType, uint32 autoApproveMaxAllowed);

    function LINK() external view returns (address);

    function acceptOwnership() external;

    function approve(
        string memory name,
        address upkeepContract,
        uint32 gasLimit,
        address adminAddress,
        uint8 triggerType,
        bytes memory checkData,
        bytes memory triggerConfig,
        bytes memory offchainConfig,
        bytes32 hash
    ) external;

    function cancel(bytes32 hash) external;

    function getAutoApproveAllowedSender(address senderAddress) external view returns (bool);

    function getConfig() external view returns (address keeperRegistry, uint256 minLINKJuels);

    function getPendingRequest(bytes32 hash) external view returns (address, uint96);

    function getTriggerRegistrationDetails(uint8 triggerType)
        external
        view
        returns (TriggerRegistrationStorage memory);

    function onTokenTransfer(address sender, uint256 amount, bytes memory data) external;

    function owner() external view returns (address);

    function register(
        string memory name,
        bytes memory encryptedEmail,
        address upkeepContract,
        uint32 gasLimit,
        address adminAddress,
        uint8 triggerType,
        bytes memory checkData,
        bytes memory triggerConfig,
        bytes memory offchainConfig,
        uint96 amount,
        address sender
    ) external;

    function registerUpkeep(RegistrationParams memory requestParams) external returns (uint256);

    function setAutoApproveAllowedSender(address senderAddress, bool allowed) external;

    function setConfig(address keeperRegistry, uint96 minLINKJuels) external;

    function setTriggerConfig(uint8 triggerType, uint8 autoApproveType, uint32 autoApproveMaxAllowed) external;

    function transferOwnership(address to) external;

    function typeAndVersion() external view returns (string memory);
}
