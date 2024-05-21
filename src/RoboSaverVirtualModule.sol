// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IMulticall} from "@gnosispay-kit/interfaces/IMulticall.sol";
import {IRolesModifier} from "@gnosispay-kit/interfaces/IRolesModifier.sol";
import {IDelayModifier} from "@gnosispay-kit/interfaces/IDelayModifier.sol";

import {IAsset} from "@balancer-v2/interfaces/contracts/vault/IAsset.sol";
import "@balancer-v2/interfaces/contracts/vault/IVault.sol";
import "@balancer-v2/interfaces/contracts/pool-stable/StablePoolUserData.sol";

/// @title RoboSaver: turn your Gnosis Pay card into an automated savings account!
/// @author onchainification.xyz
/// @notice Deposit and withdraw $EURe from your Gnosis Pay card to a liquidity pool
contract RoboSaverVirtualModule {
    /*//////////////////////////////////////////////////////////////////////////
                                     DATA TYPES
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Enum representing the different types of pool actions
    /// @custom:value0 WITHDRAW Withdraw $EURe from the pool to the card
    /// @custom:value1 DEPOSIT Deposit $EURe from the card into the pool
    enum PoolAction {
        WITHDRAW,
        DEPOSIT
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    uint256 constant SLIPP = 9_800;
    uint256 constant MAX_BPS = 10_000;

    address public constant MULTICALL3 = 0xcA11bde05977b3631167028862bE2a173976CA11;
    address public immutable CARD;

    IERC20 constant STEUR = IERC20(0x004626A008B1aCdC4c74ab51644093b155e59A23);
    IERC20 constant EURE = IERC20(0xcB444e90D8198415266c6a2724b7900fb12FC56E);
    IERC20 constant BPT_STEUR_EURE = IERC20(0x06135A9Ae830476d3a941baE9010B63732a055F4);

    IVault public constant BALANCER_VAULT = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    bytes32 public constant BPT_STEUR_EURE_POOL_ID = 0x06135a9ae830476d3a941bae9010b63732a055f4000000000000000000000065;
    bytes32 constant SET_ALLOWANCE_KEY = keccak256("SPENDING_ALLOWANCE");

    /*//////////////////////////////////////////////////////////////////////////
                                   PUBLIC STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    IDelayModifier public delayModule;
    IRolesModifier public rolesModule;

    address public keeper;
    uint256 public buffer;

    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a withdrawal pool transaction is being queued up.
    /// @param safe The address of the card.
    /// @param amount The amount of $EURe to withdraw from the pool
    /// @param timestamp The timestamp of the transaction.
    event PoolWithdrawalQueued(address indexed safe, uint256 amount, uint256 timestamp);

    /// @notice Emitted when a deposit pool transaction is being queued up.
    /// @param safe The address of the card.
    /// @param amount The amount of $EURe to deposit into the pool
    /// @param timestamp The timestamp of the transaction.
    event PoolDepositQueued(address indexed safe, uint256 amount, uint256 timestamp);

    /// @notice Emitted when an adjustment pool transaction is being queued up.
    /// @param target The address of the target contract.
    /// @param payload The payload of the transaction to be executed on the target contract.
    event AdjustPoolTxDataQueued(address indexed target, bytes payload);

    /// @notice Emitted when the admin sets a new buffer value.
    /// @param admin The address of the contract admin.
    /// @param oldBuffer The value of the old buffer.
    /// @param newBuffer The value of the new buffer.
    event SetBuffer(address indexed admin, uint256 oldBuffer, uint256 newBuffer);

    /// @notice Emitted when the admin sets a new keeper address.
    /// @param admin The address of the contract admin.
    /// @param oldKeeper The address of the old keeper.
    /// @param newKeeper The address of the new keeper.
    event SetKeeper(address indexed admin, address oldKeeper, address newKeeper);

    /*//////////////////////////////////////////////////////////////////////////
                                       ERRORS
    //////////////////////////////////////////////////////////////////////////*/

    error NotKeeper(address agent);
    error NotAdmin(address agent);

    error ZeroAddressValue();
    error ZeroUintValue();

    /*//////////////////////////////////////////////////////////////////////////
                                      MODIFIERS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Enforce that the function is called by the keeper only
    modifier onlyKeeper() {
        if (msg.sender != keeper) revert NotKeeper(msg.sender);
        _;
    }

    /// @notice Enforce that the function is called by the admin only
    modifier onlyAdmin() {
        if (msg.sender != CARD) revert NotAdmin(msg.sender);
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    constructor(address _delayModule, address _rolesModule, address _keeper, uint256 _buffer) {
        delayModule = IDelayModifier(_delayModule);
        rolesModule = IRolesModifier(_rolesModule);
        keeper = _keeper;
        buffer = _buffer;

        CARD = delayModule.avatar();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                  EXTERNAL METHODS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Assigns a new value for the buffer responsible for deciding when there is a surplus
    /// @param _buffer The value of the new buffer
    function setBuffer(uint256 _buffer) external onlyAdmin {
        if (_buffer == 0) revert ZeroUintValue();

        uint256 oldBuffer = buffer;
        buffer = _buffer;

        emit SetBuffer(msg.sender, oldBuffer, buffer);
    }

    /// @notice Assigns a new keeper address
    /// @param _keeper The address of the new keeper
    function setKeeper(address _keeper) external onlyAdmin {
        if (_keeper == address(0)) revert ZeroAddressValue();

        address oldKeeper = keeper;
        keeper = _keeper;

        emit SetKeeper(msg.sender, oldKeeper, keeper);
    }

    /// @notice Check if there is a surplus or deficit of $EURe on the card
    /// @return adjustPoolNeeded True if there is a deficit or surplus; false otherwise
    /// @return execPayload The payload of the needed transaction
    function checker() external view returns (bool adjustPoolNeeded, bytes memory execPayload) {
        uint256 balance = EURE.balanceOf(CARD);
        (, uint128 dailyAllowance,,,) = rolesModule.allowances(SET_ALLOWANCE_KEY);

        if (balance < dailyAllowance) {
            /// @notice there is a deficit; we need to withdraw from the pool
            uint256 deficit = dailyAllowance - balance;
            return (true, abi.encodeWithSelector(this.adjustPool.selector, PoolAction.WITHDRAW, deficit));
        } else if (balance > dailyAllowance + buffer) {
            /// @notice there is a surplus; we need to deposit into the pool
            uint256 surplus = balance - (dailyAllowance + buffer);
            return (true, abi.encodeWithSelector(this.adjustPool.selector, PoolAction.DEPOSIT, surplus));
        }

        /// @notice neither deficit nor surplus; no action needed
        return (false, bytes("Neither deficit nor surplus; no action needed"));
    }

    /// @notice Adjust the pool by depositing or withdrawing $EURe
    /// @param _action The action to take: deposit or withdraw
    /// @param _amount The amount of $EURe to deposit or withdraw
    /// @return execPayload_ The payload of the transaction to execute
    function adjustPool(PoolAction _action, uint256 _amount) external onlyKeeper returns (bytes memory execPayload_) {
        if (_action == PoolAction.WITHDRAW) {
            execPayload_ = abi.encode(_poolWithdrawal(CARD, _amount));
        } else if (_action == PoolAction.DEPOSIT) {
            execPayload_ = abi.encode(_poolDeposit(CARD, _amount));
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   INTERNAL METHODS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Withdraw $EURe from the pool
    /// @param _card The address of the card to withdraw to
    /// @param _deficit The amount of $EURe to withdraw from the pool
    /// @return request_ The exit pool request as per Balancer's interface
    function _poolWithdrawal(address _card, uint256 _deficit)
        internal
        returns (IVault.ExitPoolRequest memory request_)
    {
        /// @dev All asset related arrays should always follow this (alphabetical) order
        IAsset[] memory assets = new IAsset[](3);
        assets[0] = IAsset(address(STEUR));
        assets[1] = IAsset(address(BPT_STEUR_EURE));
        assets[2] = IAsset(address(EURE));

        /// @dev Allow for one wei of slippage
        uint256[] memory minAmountsOut = new uint256[](3);
        minAmountsOut[2] = _deficit - 1;

        /// @dev For some reason the `amountsOut` array does NOT include the bpt token itself
        uint256[] memory amountsOut = new uint256[](2);
        amountsOut[1] = _deficit;

        // @todo do we need more math to calculate the exact amount of bpt to withdraw?
        // @todo if not, explain why not in a @dev comment here
        bytes memory userData =
            abi.encode(StablePoolUserData.ExitKind.BPT_IN_FOR_EXACT_TOKENS_OUT, amountsOut, type(uint256).max);

        /// @dev Queue the transaction into the delay module
        request_ = IVault.ExitPoolRequest(assets, minAmountsOut, userData, false);
        bytes memory payload =
            abi.encodeWithSelector(IVault.exitPool.selector, BPT_STEUR_EURE_POOL_ID, _card, payable(_card), request_);
        delayModule.execTransactionFromModule(address(BALANCER_VAULT), 0, payload, 0);

        emit AdjustPoolTxDataQueued(address(BALANCER_VAULT), payload);
        emit PoolWithdrawalQueued(_card, _deficit, block.timestamp);
    }

    /// @notice Deposit $EURe into the pool
    /// @param _card The address of the card to deposit from
    /// @param _surplus The amount of $EURe to deposit into the pool
    /// @return calls_ The calls needed approve $EURe and join the pool
    function _poolDeposit(address _card, uint256 _surplus) internal returns (IMulticall.Call[] memory) {
        /// @dev Approve our $EURe to the Balancer Vault
        bytes memory approvalPayload =
            abi.encodeWithSignature("approve(address,uint256)", address(BALANCER_VAULT), _surplus);

        /// @dev Prepare the join pool request
        IAsset[] memory assets = new IAsset[](3);
        assets[0] = IAsset(address(STEUR));
        assets[1] = IAsset(address(BPT_STEUR_EURE));
        assets[2] = IAsset(address(EURE));

        uint256[] memory maxAmountsIn = new uint256[](3);
        maxAmountsIn[2] = _surplus;

        // @todo is there an assumption here that 1 bpt = 1 eure? is that always correct?
        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[1] = _surplus;
        uint256 minimumBPT = (_surplus * SLIPP) / MAX_BPS;
        bytes memory userData =
            abi.encode(StablePoolUserData.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, amountsIn, minimumBPT);

        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest(assets, maxAmountsIn, userData, false);

        bytes memory joinPoolPayload =
            abi.encodeWithSelector(IVault.joinPool.selector, BPT_STEUR_EURE_POOL_ID, _card, _card, request);

        /// @dev Batch approval and pool join into a multicall
        IMulticall.Call[] memory calls_ = new IMulticall.Call[](2);
        calls_[0] = IMulticall.Call(address(EURE), approvalPayload);
        calls_[1] = IMulticall.Call(address(BALANCER_VAULT), joinPoolPayload);
        bytes memory multicallPayload = abi.encodeWithSelector(IMulticall.aggregate.selector, calls_);

        /// @dev Queue the transaction into the delay module
        /// @dev Last argument `1` stands for `OperationType.DelegateCall`
        delayModule.execTransactionFromModule(MULTICALL3, 0, multicallPayload, 1);

        emit AdjustPoolTxDataQueued(MULTICALL3, multicallPayload);
        emit PoolDepositQueued(_card, _surplus, block.timestamp);

        return calls_;
    }
}
