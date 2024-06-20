// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IKeeperRegistryMaster {
    error ArrayHasNoEntries();
    error CannotCancel();
    error CheckDataExceedsLimit();
    error ConfigDigestMismatch();
    error DuplicateEntry();
    error DuplicateSigners();
    error GasLimitCanOnlyIncrease();
    error GasLimitOutsideRange();
    error IncorrectNumberOfFaultyOracles();
    error IncorrectNumberOfSignatures();
    error IncorrectNumberOfSigners();
    error IndexOutOfRange();
    error InsufficientFunds();
    error InvalidDataLength();
    error InvalidPayee();
    error InvalidRecipient();
    error InvalidReport();
    error InvalidSigner();
    error InvalidTransmitter();
    error InvalidTrigger();
    error InvalidTriggerType();
    error MaxCheckDataSizeCanOnlyIncrease();
    error MaxPerformDataSizeCanOnlyIncrease();
    error MigrationNotPermitted();
    error NotAContract();
    error OnlyActiveSigners();
    error OnlyActiveTransmitters();
    error OnlyCallableByAdmin();
    error OnlyCallableByLINKToken();
    error OnlyCallableByOwnerOrAdmin();
    error OnlyCallableByOwnerOrRegistrar();
    error OnlyCallableByPayee();
    error OnlyCallableByProposedAdmin();
    error OnlyCallableByProposedPayee();
    error OnlyCallableByUpkeepPrivilegeManager();
    error OnlyPausedUpkeep();
    error OnlySimulatedBackend();
    error OnlyUnpausedUpkeep();
    error ParameterLengthError();
    error PaymentGreaterThanAllLINK();
    error ReentrantCall();
    error RegistryPaused();
    error RepeatedSigner();
    error RepeatedTransmitter();
    error TargetCheckReverted(bytes reason);
    error TooManyOracles();
    error TranscoderNotSet();
    error UpkeepAlreadyExists();
    error UpkeepCancelled();
    error UpkeepNotCanceled();
    error UpkeepNotNeeded();
    error ValueNotChanged();

    event AdminPrivilegeConfigSet(address indexed admin, bytes privilegeConfig);
    event CancelledUpkeepReport(uint256 indexed id, bytes trigger);
    event ConfigSet(
        uint32 previousConfigBlockNumber,
        bytes32 configDigest,
        uint64 configCount,
        address[] signers,
        address[] transmitters,
        uint8 f,
        bytes onchainConfig,
        uint64 offchainConfigVersion,
        bytes offchainConfig
    );
    event DedupKeyAdded(bytes32 indexed dedupKey);
    event FundsAdded(uint256 indexed id, address indexed from, uint96 amount);
    event FundsWithdrawn(uint256 indexed id, uint256 amount, address to);
    event InsufficientFundsUpkeepReport(uint256 indexed id, bytes trigger);
    event OwnerFundsWithdrawn(uint96 amount);
    event OwnershipTransferRequested(address indexed from, address indexed to);
    event OwnershipTransferred(address indexed from, address indexed to);
    event Paused(address account);
    event PayeesUpdated(address[] transmitters, address[] payees);
    event PayeeshipTransferRequested(address indexed transmitter, address indexed from, address indexed to);
    event PayeeshipTransferred(address indexed transmitter, address indexed from, address indexed to);
    event PaymentWithdrawn(address indexed transmitter, uint256 indexed amount, address indexed to, address payee);
    event ReorgedUpkeepReport(uint256 indexed id, bytes trigger);
    event StaleUpkeepReport(uint256 indexed id, bytes trigger);
    event Transmitted(bytes32 configDigest, uint32 epoch);
    event Unpaused(address account);
    event UpkeepAdminTransferRequested(uint256 indexed id, address indexed from, address indexed to);
    event UpkeepAdminTransferred(uint256 indexed id, address indexed from, address indexed to);
    event UpkeepCanceled(uint256 indexed id, uint64 indexed atBlockHeight);
    event UpkeepCheckDataSet(uint256 indexed id, bytes newCheckData);
    event UpkeepGasLimitSet(uint256 indexed id, uint96 gasLimit);
    event UpkeepMigrated(uint256 indexed id, uint256 remainingBalance, address destination);
    event UpkeepOffchainConfigSet(uint256 indexed id, bytes offchainConfig);
    event UpkeepPaused(uint256 indexed id);
    event UpkeepPerformed(
        uint256 indexed id,
        bool indexed success,
        uint96 totalPayment,
        uint256 gasUsed,
        uint256 gasOverhead,
        bytes trigger
    );
    event UpkeepPrivilegeConfigSet(uint256 indexed id, bytes privilegeConfig);
    event UpkeepReceived(uint256 indexed id, uint256 startingBalance, address importedFrom);
    event UpkeepRegistered(uint256 indexed id, uint32 performGas, address admin);
    event UpkeepTriggerConfigSet(uint256 indexed id, bytes triggerConfig);
    event UpkeepUnpaused(uint256 indexed id);

    fallback() external;
    function acceptOwnership() external;
    function fallbackTo() external view returns (address);
    function latestConfigDetails()
        external
        view
        returns (uint32 configCount, uint32 blockNumber, bytes32 configDigest);
    function latestConfigDigestAndEpoch() external view returns (bool scanLogs, bytes32 configDigest, uint32 epoch);
    function onTokenTransfer(address sender, uint256 amount, bytes memory data) external;
    function owner() external view returns (address);
    function setConfig(
        address[] memory signers,
        address[] memory transmitters,
        uint8 f,
        bytes memory onchainConfigBytes,
        uint64 offchainConfigVersion,
        bytes memory offchainConfig
    ) external;
    function setConfigTypeSafe(
        address[] memory signers,
        address[] memory transmitters,
        uint8 f,
        IAutomationV21PlusCommon.OnchainConfigLegacy memory onchainConfig,
        uint64 offchainConfigVersion,
        bytes memory offchainConfig
    ) external;
    function simulatePerformUpkeep(uint256 id, bytes memory performData)
        external
        view
        returns (bool success, uint256 gasUsed);
    function transferOwnership(address to) external;
    function transmit(
        bytes32[3] memory reportContext,
        bytes memory rawReport,
        bytes32[] memory rs,
        bytes32[] memory ss,
        bytes32 rawVs
    ) external;
    function typeAndVersion() external view returns (string memory);

    function addFunds(uint256 id, uint96 amount) external;
    function cancelUpkeep(uint256 id) external;
    function checkCallback(uint256 id, bytes[] memory values, bytes memory extraData)
        external
        view
        returns (bool upkeepNeeded, bytes memory performData, uint8 upkeepFailureReason, uint256 gasUsed);
    function checkUpkeep(uint256 id, bytes memory triggerData)
        external
        view
        returns (
            bool upkeepNeeded,
            bytes memory performData,
            uint8 upkeepFailureReason,
            uint256 gasUsed,
            uint256 gasLimit,
            uint256 fastGasWei,
            uint256 linkNative
        );
    function checkUpkeep(uint256 id)
        external
        view
        returns (
            bool upkeepNeeded,
            bytes memory performData,
            uint8 upkeepFailureReason,
            uint256 gasUsed,
            uint256 gasLimit,
            uint256 fastGasWei,
            uint256 linkNative
        );
    function executeCallback(uint256 id, bytes memory payload)
        external
        returns (bool upkeepNeeded, bytes memory performData, uint8 upkeepFailureReason, uint256 gasUsed);
    function migrateUpkeeps(uint256[] memory ids, address destination) external;
    function receiveUpkeeps(bytes memory encodedUpkeeps) external;
    function registerUpkeep(
        address target,
        uint32 gasLimit,
        address admin,
        uint8 triggerType,
        bytes memory checkData,
        bytes memory triggerConfig,
        bytes memory offchainConfig
    ) external returns (uint256 id);
    function registerUpkeep(
        address target,
        uint32 gasLimit,
        address admin,
        bytes memory checkData,
        bytes memory offchainConfig
    ) external returns (uint256 id);
    function setUpkeepTriggerConfig(uint256 id, bytes memory triggerConfig) external;

    function acceptPayeeship(address transmitter) external;
    function acceptUpkeepAdmin(uint256 id) external;
    function getActiveUpkeepIDs(uint256 startIndex, uint256 maxCount) external view returns (uint256[] memory);
    function getAdminPrivilegeConfig(address admin) external view returns (bytes memory);
    function getAutomationForwarderLogic() external view returns (address);
    function getBalance(uint256 id) external view returns (uint96 balance);
    function getCancellationDelay() external pure returns (uint256);
    function getConditionalGasOverhead() external pure returns (uint256);
    function getFastGasFeedAddress() external view returns (address);
    function getForwarder(uint256 upkeepID) external view returns (address);
    function getLinkAddress() external view returns (address);
    function getLinkNativeFeedAddress() external view returns (address);
    function getLogGasOverhead() external pure returns (uint256);
    function getMaxPaymentForGas(uint8 triggerType, uint32 gasLimit) external view returns (uint96 maxPayment);
    function getMinBalance(uint256 id) external view returns (uint96);
    function getMinBalanceForUpkeep(uint256 id) external view returns (uint96 minBalance);
    function getMode() external view returns (uint8);
    function getPeerRegistryMigrationPermission(address peer) external view returns (uint8);
    function getPerPerformByteGasOverhead() external pure returns (uint256);
    function getPerSignerGasOverhead() external pure returns (uint256);
    function getSignerInfo(address query) external view returns (bool active, uint8 index);
    function getState()
        external
        view
        returns (
            IAutomationV21PlusCommon.StateLegacy memory state,
            IAutomationV21PlusCommon.OnchainConfigLegacy memory config,
            address[] memory signers,
            address[] memory transmitters,
            uint8 f
        );
    function getTransmitterInfo(address query)
        external
        view
        returns (bool active, uint8 index, uint96 balance, uint96 lastCollected, address payee);
    function getTriggerType(uint256 upkeepId) external pure returns (uint8);
    function getUpkeep(uint256 id)
        external
        view
        returns (IAutomationV21PlusCommon.UpkeepInfoLegacy memory upkeepInfo);
    function getUpkeepPrivilegeConfig(uint256 upkeepId) external view returns (bytes memory);
    function getUpkeepTriggerConfig(uint256 upkeepId) external view returns (bytes memory);
    function hasDedupKey(bytes32 dedupKey) external view returns (bool);
    function pause() external;
    function pauseUpkeep(uint256 id) external;
    function recoverFunds() external;
    function setAdminPrivilegeConfig(address admin, bytes memory newPrivilegeConfig) external;
    function setPayees(address[] memory payees) external;
    function setPeerRegistryMigrationPermission(address peer, uint8 permission) external;
    function setUpkeepCheckData(uint256 id, bytes memory newCheckData) external;
    function setUpkeepGasLimit(uint256 id, uint32 gasLimit) external;
    function setUpkeepOffchainConfig(uint256 id, bytes memory config) external;
    function setUpkeepPrivilegeConfig(uint256 upkeepId, bytes memory newPrivilegeConfig) external;
    function transferPayeeship(address transmitter, address proposed) external;
    function transferUpkeepAdmin(uint256 id, address proposed) external;
    function unpause() external;
    function unpauseUpkeep(uint256 id) external;
    function upkeepTranscoderVersion() external pure returns (uint8);
    function upkeepVersion() external pure returns (uint8);
    function withdrawFunds(uint256 id, address to) external;
    function withdrawOwnerFunds() external;
    function withdrawPayment(address from, address to) external;
}

interface IAutomationV21PlusCommon {
    struct OnchainConfigLegacy {
        uint32 paymentPremiumPPB;
        uint32 flatFeeMicroLink;
        uint32 checkGasLimit;
        uint24 stalenessSeconds;
        uint16 gasCeilingMultiplier;
        uint96 minUpkeepSpend;
        uint32 maxPerformGas;
        uint32 maxCheckDataSize;
        uint32 maxPerformDataSize;
        uint32 maxRevertDataSize;
        uint256 fallbackGasPrice;
        uint256 fallbackLinkPrice;
        address transcoder;
        address[] registrars;
        address upkeepPrivilegeManager;
    }

    struct StateLegacy {
        uint32 nonce;
        uint96 ownerLinkBalance;
        uint256 expectedLinkBalance;
        uint96 totalPremium;
        uint256 numUpkeeps;
        uint32 configCount;
        uint32 latestConfigBlockNumber;
        bytes32 latestConfigDigest;
        uint32 latestEpoch;
        bool paused;
    }

    struct UpkeepInfoLegacy {
        address target;
        uint32 performGas;
        bytes checkData;
        uint96 balance;
        address admin;
        uint64 maxValidBlocknumber;
        uint32 lastPerformedBlockNumber;
        uint96 amountSpent;
        bool paused;
        bytes offchainConfig;
    }
}
