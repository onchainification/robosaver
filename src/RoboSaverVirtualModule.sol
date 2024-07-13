// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IMulticall} from "@gnosispay-kit/interfaces/IMulticall.sol";
import {IRolesModifier} from "@gnosispay-kit/interfaces/IRolesModifier.sol";
import {IDelayModifier} from "@gnosispay-kit/interfaces/IDelayModifier.sol";

import {IRewardPoolDepositWrapper} from "./interfaces/aura/IRewardPoolDepositWrapper.sol";
import {IBoosterLite} from "./interfaces/aura/IBoosterLite.sol";
import {IComposableStablePool} from "./interfaces/balancer/IComposableStablePool.sol";

import {IAsset} from "@balancer-v2/interfaces/contracts/vault/IAsset.sol";
import "@balancer-v2/interfaces/contracts/vault/IVault.sol";
import "@balancer-v2/interfaces/contracts/pool-stable/StablePoolUserData.sol";
import "@balancer-v2/interfaces/contracts/solidity-utils/misc/IERC4626.sol";

import {KeeperCompatibleInterface} from "@chainlink/automation/interfaces/KeeperCompatibleInterface.sol";

import {VirtualModule} from "./types/DataTypes.sol";
import {Errors} from "./libraries/Errors.sol";

import {RoboSaverConstants} from "./abstracts/RoboSaverConstants.sol";

/// @title RoboSaver: turn your Gnosis Pay card into an automated savings account!
/// @author onchainification.xyz
/// @notice Deposit and withdraw $EURe from your Gnosis Pay card to a liquidity pool
contract RoboSaverVirtualModule is
    KeeperCompatibleInterface, // 1 inherited component
    RoboSaverConstants // 1 inherited component
{
    /*//////////////////////////////////////////////////////////////////////////
                                  IMMUTABLES
    //////////////////////////////////////////////////////////////////////////*/
    address public immutable CARD;

    IERC20 immutable STEUR;
    IERC20 immutable EURE;

    IComposableStablePool immutable BPT_STEUR_EURE;

    address public immutable FACTORY;

    /*//////////////////////////////////////////////////////////////////////////
                                   PUBLIC STORAGE
    //////////////////////////////////////////////////////////////////////////*/
    IDelayModifier public delayModule;
    IRolesModifier public rolesModule;

    address public keeper;
    uint256 public buffer;
    uint16 public slippage;

    /// @dev Keeps track of the transaction queued up by the virtual module and allows internally to call `executeNextTx`
    VirtualModule.QueuedTx public queuedTx;

    /*//////////////////////////////////////////////////////////////////////////
                                  PRIVATE STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev All asset related arrays should always follow this (alphabetical) order
    IAsset[] public poolAssets;

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

    /*//////////////////////////////////////////////////////////////////////////
                                      MODIFIERS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Enforce that the function is called by the keeper only
    modifier onlyKeeper() {
        if (msg.sender != keeper) revert Errors.NotKeeper(msg.sender);
        _;
    }

    /// @notice Enforce that the function is called by the admin only
    modifier onlyAdmin() {
        if (msg.sender != CARD) revert Errors.NotAdmin(msg.sender);
        _;
    }

    /// @notice Enforce that the function is called by the admin or the factory only
    modifier onlyAdminOrFactory() {
        if (msg.sender != CARD && msg.sender != FACTORY) revert Errors.NeitherAdminNorFactory(msg.sender);
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    constructor(address _factory, address _delayModule, address _rolesModule, uint256 _buffer, uint16 _slippage) {
        FACTORY = _factory;

        delayModule = IDelayModifier(_delayModule);
        rolesModule = IRolesModifier(_rolesModule);

        _setBuffer(_buffer);
        _setSlippage(_slippage);

        CARD = delayModule.avatar();

        /// @dev Get all the pool tokens and write them to constants and storage
        /// @dev This will make it easier to support multiple pools in a future version
        (IERC20[] memory tokens,,) = BALANCER_VAULT.getPoolTokens(BPT_STEUR_EURE_POOL_ID);

        STEUR = tokens[0];
        BPT_STEUR_EURE = IComposableStablePool(address(tokens[1]));
        EURE = tokens[2];

        /// @dev dynamic pool assets array initialization
        poolAssets = new IAsset[](tokens.length);
        for (uint256 i; i < tokens.length; i++) {
            poolAssets[i] = IAsset(address(tokens[i]));
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    PUBLIC VIEWS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice A function that returns name of the virtual module and its base currency concatenated
    function name() public pure returns (string memory) {
        // @todo once the base currency is dynamic, this should be updated to read directly the symbol of it
        // `string.concat("RoboSaverVirtualModule-", BASE_CURRENCY.symbol());`
        return "RoboSaverVirtualModule-EURE";
    }

    /// @notice A function that returns version of the virtual module
    function version() public pure returns (string memory) {
        return "v0.1.0";
    }

    /*//////////////////////////////////////////////////////////////////////////
                                  EXTERNAL METHODS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Assigns a new keeper address
    /// @param _keeper The address of the new keeper
    function setKeeper(address _keeper) external onlyAdminOrFactory {
        if (_keeper == address(0)) revert Errors.ZeroAddressValue();

        address oldKeeper = keeper;
        keeper = _keeper;

        emit SetKeeper(msg.sender, oldKeeper, keeper);
    }

    /// @notice Assigns a new value for the buffer responsible for deciding when there is a surplus
    /// @param _buffer The value of the new buffer
    function setBuffer(uint256 _buffer) external onlyAdmin {
        _setBuffer(_buffer);
    }

    /// @notice Adjust the maximum slippage the user is comfortable with
    /// @param _slippage The value of the new slippage in bps (so 10_000 is 100%)
    function setSlippage(uint16 _slippage) external onlyAdmin {
        _setSlippage(_slippage);
    }

    /// @notice Check if there is a surplus or deficit of $EURe on the card
    /// @return adjustPoolNeeded True if there is a deficit or surplus; false otherwise
    /// @return execPayload The payload of the needed transaction
    function checkUpkeep(bytes calldata /* checkData */ )
        external
        view
        override
        returns (bool adjustPoolNeeded, bytes memory execPayload)
    {
        if (!delayModule.isModuleEnabled(address(this))) return (false, bytes("Virtual module is not enabled"));

        /// @dev check if there is a transaction queued up in the delay module by an external entity
        if (_isExternalTxQueued()) {
            return (false, bytes("External transaction in queue, wait for it to be executed"));
        }

        /// @dev check if there is a transaction queued up in the delay module by the virtual module itself
        if (queuedTx.nonce != 0) {
            /// @notice check if the transaction is still in cooldown or ready to exec
            if (_isInCoolDown(queuedTx.nonce)) return (false, bytes("Internal transaction in cooldown status"));
            return (true, abi.encode(VirtualModule.PoolAction.EXEC_QUEUE_POOL_ACTION, 0));
        }

        uint256 bptBalance = BPT_STEUR_EURE.balanceOf(CARD);
        if (bptBalance > 0) {
            return (true, abi.encode(VirtualModule.PoolAction.STAKE, 0));
        }

        uint256 balance = EURE.balanceOf(CARD);
        (, uint128 dailyAllowance,,,) = rolesModule.allowances(SET_ALLOWANCE_KEY);

        if (balance < dailyAllowance) {
            /// @notice there is a deficit; we need to withdraw from the pool
            uint256 stakedBptBalance = AURA_GAUGE_STEUR_EURE.balanceOf(CARD);
            if (stakedBptBalance == 0) return (false, bytes("No staked BPT balance on the card"));

            uint256 deficit = dailyAllowance - balance + buffer;
            uint256 withdrawableEure =
                stakedBptBalance * BPT_STEUR_EURE.getRate() * (MAX_BPS - slippage) / 1e18 / MAX_BPS;
            if (withdrawableEure < deficit) {
                return (true, abi.encode(VirtualModule.PoolAction.CLOSE, withdrawableEure));
            } else {
                return (true, abi.encode(VirtualModule.PoolAction.WITHDRAW, deficit));
            }
        } else if (balance > dailyAllowance + buffer) {
            /// @notice there is a surplus; we need to deposit into the pool
            uint256 surplus = balance - (dailyAllowance + buffer);
            return (true, abi.encode(VirtualModule.PoolAction.DEPOSIT, surplus));
        }

        /// @notice neither deficit nor surplus; no action needed
        return (false, bytes("Neither deficit nor surplus; no action needed"));
    }

    /// @notice The actual execution of the action determined by the `checkUpkeep` method
    /// @param _performData Decodes into the exact action to take and its corresponding amount
    function performUpkeep(bytes calldata _performData) external override onlyKeeper {
        (VirtualModule.PoolAction action, uint256 amount) =
            abi.decode(_performData, (VirtualModule.PoolAction, uint256));
        _adjustPool(action, amount);
    }

    /// @notice Turn off the RoboSaver; withdraw all funds and disable the virtual module
    function shutdown() external onlyAdmin {
        uint256 stakedBptBalance = AURA_GAUGE_STEUR_EURE.balanceOf(CARD);
        if (stakedBptBalance > 0) {
            _adjustPool(VirtualModule.PoolAction.SHUTDOWN, stakedBptBalance);
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   INTERNAL METHODS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Adjust the pool by depositing or withdrawing $EURe
    /// @param _action The action to take: deposit or withdraw
    /// @param _amount The amount of $EURe to deposit or withdraw
    function _adjustPool(VirtualModule.PoolAction _action, uint256 _amount) internal {
        if (!delayModule.isModuleEnabled(address(this))) revert Errors.VirtualModuleNotEnabled();
        if (_isCleanQueueRequired()) delayModule.skipExpired();
        if (_isExternalTxQueued()) revert Errors.ExternalTxIsQueued();

        if (_action == VirtualModule.PoolAction.WITHDRAW) {
            _poolWithdrawal(_amount);
        } else if (_action == VirtualModule.PoolAction.DEPOSIT) {
            _poolDeposit(_amount);
        } else if (_action == VirtualModule.PoolAction.CLOSE) {
            _poolClose(_amount);
        } else if (_action == VirtualModule.PoolAction.STAKE) {
            _stakeAllBpt();
        } else if (_action == VirtualModule.PoolAction.SHUTDOWN) {
            _shutdown(_amount);
        } else if (_action == VirtualModule.PoolAction.EXEC_QUEUE_POOL_ACTION) {
            _executeQueuedTx();
        }
    }

    /// @notice Close the pool position by unstaking and withdrawing all to $EURe
    /// @param _minAmountOut The minimum amount of $EURe to withdraw from the pool
    /// @return request_ The exit pool request as per Balancer's interface
    function _poolClose(uint256 _minAmountOut) internal returns (IVault.ExitPoolRequest memory request_) {
        /// @dev Payload 1: Unstake and claim all pending rewards from the Aura gauge
        uint256 stakedBptBalance = AURA_GAUGE_STEUR_EURE.balanceOf(CARD);
        bytes memory unstakeAndClaimPayload =
            abi.encodeWithSignature("withdrawAndUnwrap(uint256,bool)", stakedBptBalance, true);

        /// @dev Payload 2: Withdraw all $EURe from the pool
        uint256[] memory minAmountsOut = new uint256[](3);
        minAmountsOut[EURE_TOKEN_BPT_INDEX] = _minAmountOut;
        bytes memory userData = abi.encode(
            StablePoolUserData.ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, stakedBptBalance, EURE_TOKEN_BPT_INDEX_USER
        );
        request_ = IVault.ExitPoolRequest(poolAssets, minAmountsOut, userData, false);
        bytes memory exitPoolPayload =
            abi.encodeWithSelector(IVault.exitPool.selector, BPT_STEUR_EURE_POOL_ID, CARD, payable(CARD), request_);

        /// @dev Batch all payloads into a multicall
        IMulticall.Call[] memory calls_ = new IMulticall.Call[](2);
        calls_[0] = IMulticall.Call(address(AURA_GAUGE_STEUR_EURE), unstakeAndClaimPayload);
        calls_[1] = IMulticall.Call(address(BALANCER_VAULT), exitPoolPayload);
        bytes memory multicallPayload = abi.encodeWithSelector(IMulticall.aggregate.selector, calls_);

        _queueTx(MULTICALL3, multicallPayload);

        emit PoolCloseQueued(CARD, _minAmountOut, block.timestamp);
    }

    /// @notice Withdraw $EURe from the pool
    /// @param _deficit The amount of $EURe to withdraw from the pool
    /// @return request_ The exit pool request as per Balancer's interface
    function _poolWithdrawal(uint256 _deficit) internal returns (IVault.ExitPoolRequest memory request_) {
        /// @dev Payload 1: Unstake and claim all pending rewards from the Aura gauge
        uint256 stakedBptBalance = AURA_GAUGE_STEUR_EURE.balanceOf(CARD);
        uint256 maxBPTAmountIn = _deficit * MAX_BPS * 1e18 / (MAX_BPS - slippage) / BPT_STEUR_EURE.getRate();
        if (stakedBptBalance < maxBPTAmountIn) {
            revert Errors.TooLowStakedBptBalance(stakedBptBalance, maxBPTAmountIn);
        }
        bytes memory unstakeAndClaimPayload =
            abi.encodeWithSignature("withdrawAndUnwrap(uint256,bool)", maxBPTAmountIn, true);

        /// @dev Payload 2: Withdraw the necessary $EURe from the pool
        uint256[] memory minAmountsOut = new uint256[](3);
        minAmountsOut[EURE_TOKEN_BPT_INDEX] = _deficit;

        /// @dev For some reason the `amountsOut` array does NOT include the bpt token itself
        uint256[] memory amountsOut = new uint256[](2);
        amountsOut[1] = _deficit;

        /// @dev Naive calculation of the `maxBPTAmountIn` based on the bpt rate and slippage %
        bytes memory userData =
            abi.encode(StablePoolUserData.ExitKind.BPT_IN_FOR_EXACT_TOKENS_OUT, amountsOut, maxBPTAmountIn);

        /// @dev Queue the transaction into the delay module
        request_ = IVault.ExitPoolRequest(poolAssets, minAmountsOut, userData, false);
        bytes memory exitPoolPayload =
            abi.encodeWithSelector(IVault.exitPool.selector, BPT_STEUR_EURE_POOL_ID, CARD, payable(CARD), request_);

        /// @dev Batch all payloads into a multicall
        IMulticall.Call[] memory calls_ = new IMulticall.Call[](2);
        calls_[0] = IMulticall.Call(address(AURA_GAUGE_STEUR_EURE), unstakeAndClaimPayload);
        calls_[1] = IMulticall.Call(address(BALANCER_VAULT), exitPoolPayload);
        bytes memory multicallPayload = abi.encodeWithSelector(IMulticall.aggregate.selector, calls_);

        _queueTx(MULTICALL3, multicallPayload);

        emit PoolWithdrawalQueued(CARD, _deficit, block.timestamp);
    }

    /// @notice Deposit $EURe into the pool
    /// @param _surplus The amount of $EURe to deposit into the pool
    /// @return calls_ The calls needed approve $EURe and join the pool
    function _poolDeposit(uint256 _surplus) internal returns (IMulticall.Call[] memory) {
        /// @dev Build the payload to approve our $EURe to the Aura Depositor
        bytes memory approveEurePayload =
            abi.encodeWithSignature("approve(address,uint256)", address(AURA_DEPOSITOR), _surplus);

        /// @dev Build the payload to join the pool
        uint256[] memory maxAmountsIn = new uint256[](3);
        maxAmountsIn[EURE_TOKEN_BPT_INDEX] = _surplus;

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[1] = _surplus;

        /// @dev Naive calculation of the `minimumBPT` to receive based on the bpt rate and slippage %
        uint256 minimumBPT = _surplus * (MAX_BPS - slippage) * 1e18 / MAX_BPS / BPT_STEUR_EURE.getRate();
        bytes memory userData =
            abi.encode(StablePoolUserData.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, amountsIn, minimumBPT);

        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest(poolAssets, maxAmountsIn, userData, false);
        bytes memory depositAndStakePayload = abi.encodeWithSelector(
            IRewardPoolDepositWrapper.depositSingle.selector,
            address(AURA_GAUGE_STEUR_EURE),
            address(EURE),
            _surplus,
            BPT_STEUR_EURE_POOL_ID,
            request
        );

        /// @dev Batch all payloads into a multicall
        IMulticall.Call[] memory calls_ = new IMulticall.Call[](2);
        calls_[0] = IMulticall.Call(address(EURE), approveEurePayload);
        calls_[1] = IMulticall.Call(address(AURA_DEPOSITOR), depositAndStakePayload);
        bytes memory multicallPayload = abi.encodeWithSelector(IMulticall.aggregate.selector, calls_);

        _queueTx(MULTICALL3, multicallPayload);

        emit PoolDepositQueued(CARD, _surplus, block.timestamp);

        return calls_;
    }

    /// @notice Stake all BPT on its Aura gauge
    function _stakeAllBpt() internal {
        uint256 bptBalance = BPT_STEUR_EURE.balanceOf(CARD);

        bytes memory approveBptPayload =
            abi.encodeWithSignature("approve(address,uint256)", address(AURA_BOOSTER), bptBalance);
        bytes memory stakePayload = abi.encodeWithSignature("depositAll(uint256,bool)", 22, true);

        /// @dev Batch all payloads into a multicall
        IMulticall.Call[] memory calls_ = new IMulticall.Call[](2);
        calls_[0] = IMulticall.Call(address(BPT_STEUR_EURE), approveBptPayload);
        calls_[1] = IMulticall.Call(address(AURA_BOOSTER), stakePayload);
        bytes memory multicallPayload = abi.encodeWithSelector(IMulticall.aggregate.selector, calls_);

        _queueTx(MULTICALL3, multicallPayload);

        emit StakeQueued(CARD, bptBalance, block.timestamp);
    }

    /// @notice Internal function of `shutdown()`
    /// @param _stakedBptBalance The total amount of BPT staked on the Aura gauge
    function _shutdown(uint256 _stakedBptBalance) internal {
        /// @dev Payload 1: Unstake and claim all pending rewards from the Aura gauge
        bytes memory unstakeAndClaimPayload =
            abi.encodeWithSignature("withdrawAndUnwrap(uint256,bool)", _stakedBptBalance, true);

        /// @dev Payload 2: Withdraw all $EURe from the staked pool + from any residual BPT
        /// @dev We also consider the BPT so that `shutdown()` can be called at any time;
        ///      even when the keeper is not doing what it should be doing (immediately staking any residual bpt)
        uint256 totalBptBalance = _stakedBptBalance + BPT_STEUR_EURE.balanceOf(CARD);
        uint256 withdrawableEure = totalBptBalance * BPT_STEUR_EURE.getRate() * (MAX_BPS - slippage) / 1e18 / MAX_BPS;
        uint256[] memory minAmountsOut = new uint256[](3);
        minAmountsOut[EURE_TOKEN_BPT_INDEX] = withdrawableEure;
        bytes memory userData = abi.encode(
            StablePoolUserData.ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, totalBptBalance, EURE_TOKEN_BPT_INDEX_USER
        );
        IVault.ExitPoolRequest memory request_ = IVault.ExitPoolRequest(poolAssets, minAmountsOut, userData, false);
        bytes memory exitPoolPayload =
            abi.encodeWithSelector(IVault.exitPool.selector, BPT_STEUR_EURE_POOL_ID, CARD, payable(CARD), request_);

        /// @dev Payload 3: Disable the virtual module
        /// @dev address(0x1) is the sentinel address in the DelayModifier's linked list
        address prevModule = _getPrevModule(address(0x1));
        bytes memory disableModulePayload =
            abi.encodeWithSignature("disableModule(address,address)", prevModule, address(this));

        /// @dev Batch all payloads into a multicall
        IMulticall.Call[] memory calls_ = new IMulticall.Call[](3);
        calls_[0] = IMulticall.Call(address(AURA_GAUGE_STEUR_EURE), unstakeAndClaimPayload);
        calls_[1] = IMulticall.Call(address(BALANCER_VAULT), exitPoolPayload);
        calls_[2] = IMulticall.Call(address(delayModule), disableModulePayload);
        bytes memory multicallPayload = abi.encodeWithSelector(IMulticall.aggregate.selector, calls_);

        _queueTx(MULTICALL3, multicallPayload);

        emit PoolShutdownQueued(CARD, withdrawableEure, block.timestamp);
    }

    /// @dev Execute the next transaction in the queue using the storage variable `queuedTx`
    function _executeQueuedTx() internal {
        address cachedTarget = queuedTx.target;
        bytes memory cachedPayload = queuedTx.payload;
        /// @dev since all actions go through multicall3, operation is set to 1 (DelegateCall)
        delayModule.executeNextTx(cachedTarget, 0, cachedPayload, 1);

        emit AdjustPoolTxExecuted(cachedTarget, cachedPayload, queuedTx.nonce, block.timestamp);

        // sets every field in the struct to its default value
        delete queuedTx;
    }

    /// @notice Check if there is a transaction queued up in the delay module by an external entity. Not our own virtual module.
    /// @return isTxQueued_ True if there is a transaction queued up; false otherwise
    function _isExternalTxQueued() internal view returns (bool isTxQueued_) {
        uint256 cachedQueueNonce = delayModule.queueNonce();
        if (delayModule.txNonce() != cachedQueueNonce && cachedQueueNonce != queuedTx.nonce) isTxQueued_ = true;
    }

    /// @notice Queue the transaction into the delay module
    /// @param _target The address of the target of the transaction
    /// @param _payload The payload of the transaction
    function _queueTx(address _target, bytes memory _payload) internal {
        /// @dev since all actions go through multicall3, operation is set to 1 (DelegateCall)
        delayModule.execTransactionFromModule(_target, 0, _payload, 1);
        uint256 cachedQueueNonce = delayModule.queueNonce();
        queuedTx = VirtualModule.QueuedTx(cachedQueueNonce, _target, _payload);

        emit AdjustPoolTxDataQueued(_target, _payload, cachedQueueNonce);
    }

    /// @notice Check if the transaction is still in cooldown or ready to exec
    /// @param _nonce The nonce of the transaction
    /// @return isInCoolDown_ True if the transaction is still in cooldown; false otherwise
    function _isInCoolDown(uint256 _nonce) internal view returns (bool isInCoolDown_) {
        /// @dev Requires deducting 1 from the storage nonce, since the delay module increments after writing timestamp in their internal storage
        if (block.timestamp - delayModule.getTxCreatedAt(_nonce - 1) <= delayModule.txCooldown()) isInCoolDown_ = true;
    }

    /// @notice Check if any transactions are expired
    /// @return anyExpiredTxs_ True if any transactions are expired; false otherwise
    function _isCleanQueueRequired() internal view returns (bool anyExpiredTxs_) {
        /// @dev Pick latest `txNonce` as reference to check if it is expired, then trigger clean-up
        if (
            block.timestamp - delayModule.getTxCreatedAt(delayModule.txNonce())
                > delayModule.txCooldown() + delayModule.txExpiration()
        ) {
            anyExpiredTxs_ = true;
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                                  GETTERS & SETTERS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Retrieve the previous module in the Delay module's linked list
    /// @param _start The address of the module the previous module is pointing at
    /// @return prevModule_ The address of the previous module relative to `_start`
    function _getPrevModule(address _start) internal view returns (address prevModule_) {
        /// @dev Retrieve the module _start points to in the linked list
        (address[] memory nextModules,) = delayModule.getModulesPaginated(_start, MODULE_PAGE_SIZE);
        if (nextModules[0] == address(this)) {
            return _start;
        }
        prevModule_ = _getPrevModule(nextModules[0]);
    }

    function _setSlippage(uint16 _slippage) internal {
        if (_slippage >= MAX_BPS) revert Errors.TooHighBps();

        uint16 oldSlippage = slippage;
        slippage = _slippage;

        emit SetSlippage(msg.sender, oldSlippage, slippage);
    }

    function _setBuffer(uint256 _buffer) internal {
        if (_buffer == 0) revert Errors.ZeroUintValue();

        uint256 oldBuffer = buffer;
        buffer = _buffer;

        emit SetBuffer(msg.sender, oldBuffer, buffer);
    }
}
