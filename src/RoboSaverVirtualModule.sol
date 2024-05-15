// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IMulticall} from "@gnosispay-kit/interfaces/IMulticall.sol";
import {IRolesModifier} from "@gnosispay-kit/interfaces/IRolesModifier.sol";
import {IDelayModifier} from "@gnosispay-kit/interfaces/IDelayModifier.sol";

import {IAsset} from "@balancer-v2/interfaces/contracts/vault/IAsset.sol";
import "@balancer-v2/interfaces/contracts/vault/IVault.sol";
import "@balancer-v2/interfaces/contracts/pool-stable/StablePoolUserData.sol";

contract RoboSaverVirtualModule {
    /*//////////////////////////////////////////////////////////////////////////
                                     DATA TYPES
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Enum representing the different possible top-up types.
    /// @custom:value0 SAFE Top-up of the $EURe balance in the card.
    /// @custom:value1 BPT Top-up of the BPT pool with the excess $EURe funds.
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

    IERC20 constant STEUR = IERC20(0x004626A008B1aCdC4c74ab51644093b155e59A23);
    IERC20 constant EURE = IERC20(0xcB444e90D8198415266c6a2724b7900fb12FC56E);
    IERC20 constant BPT_STEUR_EURE = IERC20(0x06135A9Ae830476d3a941baE9010B63732a055F4);

    IVault public constant BALANCER_VAULT = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    bytes32 public constant BPT_STEUR_EURE_POOL_ID = 0x06135a9ae830476d3a941bae9010b63732a055f4000000000000000000000065;
    bytes32 constant SET_ALLOWANCE_KEY = keccak256("SPENDING_ALLOWANCE");

    address public immutable CARD;

    /*//////////////////////////////////////////////////////////////////////////
                                   PUBLIC STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    IDelayModifier public delayModule;
    IRolesModifier public rolesModule;

    address public keeper;
    uint256 public buffer;

    /*//////////////////////////////////////////////////////////////////////////
                                       ERRORS
    //////////////////////////////////////////////////////////////////////////*/

    error NotKeeper(address agent);

    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    event PoolWithdrawal(address indexed safe, uint256 amount, uint256 timestamp);
    event PoolDeposit(address indexed safe, uint256 amount, uint256 timestamp);

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
                                      MODIFIERS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Checks whether a call is authorized to trigger top-up or exec queue txs
    modifier onlyKeeper() {
        if (msg.sender != keeper) revert NotKeeper(msg.sender);
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////
                    EXTERNAL METHODS: TOP-UP AGENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Check condition and determine whether a task should be executed by Gelato.
    function checker() external view returns (bool canExec, bytes memory execPayload) {
        uint256 balance = EURE.balanceOf(CARD);
        (, uint128 dailyAllowance,,,) = rolesModule.allowances(SET_ALLOWANCE_KEY);

        if (balance < dailyAllowance) {
            // @note it will queue the tx for topup $EURe
            uint256 deficit = dailyAllowance - balance;
            return (true, abi.encodeWithSelector(this.adjustPool.selector, PoolAction.WITHDRAW, deficit));
        } else if (balance > dailyAllowance + buffer) {
            // @note it will queue the tx for topup BPT with the excess $EURe funds
            uint256 surplus = balance - (dailyAllowance + buffer);
            return (true, abi.encodeWithSelector(this.adjustPool.selector, PoolAction.DEPOSIT, surplus));
        }

        return (false, bytes("No queue tx and sufficient balance"));
    }

    function adjustPool(PoolAction _action, uint256 _amount) external onlyKeeper returns (bytes memory execPayload_) {
        if (_action == PoolAction.WITHDRAW) {
            execPayload_ = abi.encode(_poolWithdrawal(CARD, _amount));
        } else if (_action == PoolAction.DEPOSIT) {
            execPayload_ = abi.encode(_poolDeposit(CARD, _amount));
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                    INTERNAL METHODS: TOP-UPS & TX QUEUING
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice siphon eure out of the bpt pool
    /// @param _card The address of the card in which the virtual module is withdrawing in behalf of.
    /// @param _deficit The amount of eure to withdraw from the bpt pool.
    function _poolWithdrawal(address _card, uint256 _deficit)
        internal
        returns (IVault.ExitPoolRequest memory request_)
    {
        /// @dev all asset (related) arrays should always follow this (alphabetical) order
        IAsset[] memory assets = new IAsset[](3);
        assets[0] = IAsset(address(STEUR));
        assets[1] = IAsset(address(BPT_STEUR_EURE));
        assets[2] = IAsset(address(EURE));

        /// allow for one wei of slippage
        uint256[] memory minAmountsOut = new uint256[](3);
        minAmountsOut[2] = _deficit - 1;

        /// ['uint256', 'uint256[]', 'uint256']
        /// [BPT_IN_FOR_EXACT_TOKENS_OUT, amountsOut, maxBPTAmountIn]
        uint256[] memory amountsOut = new uint256[](2);
        amountsOut[1] = _deficit;
        bytes memory userData =
            abi.encode(StablePoolUserData.ExitKind.BPT_IN_FOR_EXACT_TOKENS_OUT, amountsOut, type(uint256).max);

        request_ = IVault.ExitPoolRequest(assets, minAmountsOut, userData, false);

        /// siphon eure out of pool
        bytes memory payload =
            abi.encodeWithSelector(IVault.exitPool.selector, BPT_STEUR_EURE_POOL_ID, _card, payable(_card), request_);
        delayModule.execTransactionFromModule(address(BALANCER_VAULT), 0, payload, 0);

        emit PoolWithdrawal(_card, _deficit, block.timestamp);
    }

    /// @notice siphon eure into the bpt pool
    /// @param _card The address of the card in which the virtual module is depositing in behalf of.
    /// @param _surplus The amount of eure to deposit into the bpt pool.
    function _poolDeposit(address _card, uint256 _surplus) internal returns (IMulticall.Call[] memory) {
        // 1. approval of eure
        bytes memory approvalPayload =
            abi.encodeWithSignature("approve(address,uint256)", address(BALANCER_VAULT), _surplus);

        // 2. join bpt
        IAsset[] memory assets = new IAsset[](3);
        assets[0] = IAsset(address(STEUR));
        assets[1] = IAsset(address(BPT_STEUR_EURE));
        assets[2] = IAsset(address(EURE));

        uint256[] memory maxAmountsIn = new uint256[](3);
        maxAmountsIn[2] = _surplus;

        // ['uint256', 'uint256[]', 'uint256']
        // [EXACT_TOKENS_IN_FOR_BPT_OUT, amountsIn, minimumBPT]
        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[1] = _surplus;
        uint256 minimumBPT = (_surplus * SLIPP) / MAX_BPS;
        bytes memory userData =
            abi.encode(StablePoolUserData.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, amountsIn, minimumBPT);

        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest(assets, maxAmountsIn, userData, false);

        bytes memory joinPoolPayload =
            abi.encodeWithSelector(IVault.joinPool.selector, BPT_STEUR_EURE_POOL_ID, _card, _card, request);

        // 3. batch approval and join into a multicall
        IMulticall.Call[] memory calls_ = new IMulticall.Call[](2);
        calls_[0] = IMulticall.Call(address(EURE), approvalPayload);
        calls_[1] = IMulticall.Call(address(BALANCER_VAULT), joinPoolPayload);

        bytes memory multiCallPayalod = abi.encodeWithSelector(IMulticall.aggregate.selector, calls_);

        delayModule.execTransactionFromModule(MULTICALL3, 0, multiCallPayalod, 1);

        emit PoolDeposit(_card, _surplus, block.timestamp);

        return calls_;
    }
}
