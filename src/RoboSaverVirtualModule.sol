// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

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
    /// @custom:value0 SAFE Top-up of the $EURe balance in the avatar.
    /// @custom:value1 BPT Top-up of the BPT pool with the excess $EURe funds.
    enum TopupType {
        SAFE,
        BPT
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    uint256 constant SLIPP = 9_800;
    uint256 constant MAX_BPS = 10_000;

    address public constant MULTICALL_V3 = 0xcA11bde05977b3631167028862bE2a173976CA11;

    IERC20 constant EURE = IERC20(0xcB444e90D8198415266c6a2724b7900fb12FC56E);
    IERC20 constant STEUR = IERC20(0x004626A008B1aCdC4c74ab51644093b155e59A23);
    IERC20 constant BPT_EURE_STEUR = IERC20(0x06135A9Ae830476d3a941baE9010B63732a055F4);

    IVault public constant BALANCER_VAULT = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    bytes32 public constant BPT_EURE_STEUR_POOL_ID = 0x06135a9ae830476d3a941bae9010b63732a055f4000000000000000000000065;
    bytes32 constant SET_ALLOWANCE_KEY = keccak256("SPENDING_ALLOWANCE");

    /*//////////////////////////////////////////////////////////////////////////
                                   PUBLIC STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    IDelayModifier public delayModule;
    IRolesModifier public rolesModule;

    address public topupAgent;

    uint256 public eureBuffer;

    /*//////////////////////////////////////////////////////////////////////////
                                       ERRORS
    //////////////////////////////////////////////////////////////////////////*/

    error NotTopupAgent(address agent);

    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    event SafeTopup(address indexed safe, uint256 amount, uint256 timestamp);
    event BptTopup(address indexed safe, uint256 amount, uint256 timestamp);

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/
    constructor(address _delayModule, address _rolesModule, address _topupAgent, uint256 _eureBuffer) {
        delayModule = IDelayModifier(_delayModule);
        rolesModule = IRolesModifier(_rolesModule);

        topupAgent = _topupAgent;

        eureBuffer = _eureBuffer;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      MODIFIERS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Checks whether a call is authorized to trigger top-up or exec queue txs
    modifier onlyTopupAgents() {
        if (msg.sender != topupAgent) revert NotTopupAgent(msg.sender);
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////
                    EXTERNAL METHODS: TOP-UP AGENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Check condition and determine whether a task should be executed by Gelato.
    function checker() external view returns (bool canExec, bytes memory execPayload) {
        address cachedAvatar = delayModule.avatar();

        uint256 balance = EURE.balanceOf(cachedAvatar);
        (, uint128 maxRefill,,,) = rolesModule.allowances(SET_ALLOWANCE_KEY);

        if (balance < maxRefill) {
            // @note it will queue the tx for topup $EURe
            uint256 topupAmount = maxRefill - balance;
            return (true, abi.encodeWithSelector(this.execTopup.selector, TopupType.SAFE, cachedAvatar, topupAmount));
        } else if (balance > maxRefill + eureBuffer) {
            // @note it will queue the tx for topup BPT with the excess $EURe funds
            uint256 excessEureFunds = balance - (maxRefill + eureBuffer);
            return (true, abi.encodeWithSelector(this.execTopup.selector, TopupType.BPT, cachedAvatar, excessEureFunds));
        }

        return (false, bytes("No queue tx and sufficient balance"));
    }

    function execTopup(TopupType _type, bytes memory _payload)
        external
        onlyTopupAgents
        returns (bytes memory execPayload_)
    {
        (address avatar, uint256 topupAmount) = abi.decode(_payload, (address, uint256));
        if (_type == TopupType.SAFE) {
            execPayload_ = abi.encode(_safeTopup(avatar, topupAmount));
        } else if (_type == TopupType.BPT) {
            execPayload_ = abi.encode(_bptTopup(avatar, topupAmount));
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                    INTERNAL METHODS: TOP-UPS & TX QUEUING
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice siphon eure out of the bpt pool
    /// @param _avatar The address of the avatar in which the virtual module is withdrawing in behalf of.
    /// @param _topupAmount The amount of eure to withdraw from the bpt pool.
    function _safeTopup(address _avatar, uint256 _topupAmount)
        internal
        returns (IVault.ExitPoolRequest memory request_)
    {
        /// @dev all asset (related) arrays should always follow this (alphabetical) order
        IAsset[] memory assets = new IAsset[](3);
        assets[0] = IAsset(address(STEUR));
        assets[1] = IAsset(address(BPT_EURE_STEUR));
        assets[2] = IAsset(address(EURE));

        /// allow for one wei of slippage
        uint256[] memory minAmountsOut = new uint256[](3);
        minAmountsOut[2] = _topupAmount - 1;

        /// ['uint256', 'uint256[]', 'uint256']
        /// [BPT_IN_FOR_EXACT_TOKENS_OUT, amountsOut, maxBPTAmountIn]
        uint256[] memory amountsOut = new uint256[](2);
        amountsOut[1] = _topupAmount;
        bytes memory userData =
            abi.encode(StablePoolUserData.ExitKind.BPT_IN_FOR_EXACT_TOKENS_OUT, amountsOut, type(uint256).max);

        request_ = IVault.ExitPoolRequest(assets, minAmountsOut, userData, false);

        /// siphon eure out of pool
        bytes memory payload = abi.encodeWithSelector(
            IVault.exitPool.selector, BPT_EURE_STEUR_POOL_ID, _avatar, payable(_avatar), request_
        );
        delayModule.execTransactionFromModule(address(BALANCER_VAULT), 0, payload, 0);

        emit SafeTopup(_avatar, _topupAmount, block.timestamp);
    }

    /// @notice siphon eure into the bpt pool
    /// @param _avatar The address of the avatar in which the virtual module is depositing in behalf of.
    /// @param _excessEureFunds The amount of eure to deposit into the bpt pool.
    function _bptTopup(address _avatar, uint256 _excessEureFunds) internal returns (IMulticall.Call[] memory) {
        // 1. approval of eure
        bytes memory approvalPayload =
            abi.encodeWithSignature("approve(address,uint256)", address(BALANCER_VAULT), _excessEureFunds);

        // 2. join bpt
        IAsset[] memory assets = new IAsset[](3);
        assets[0] = IAsset(address(STEUR));
        assets[1] = IAsset(address(BPT_EURE_STEUR));
        assets[2] = IAsset(address(EURE));

        uint256[] memory maxAmountsIn = new uint256[](3);
        maxAmountsIn[2] = _excessEureFunds;

        // ['uint256', 'uint256[]', 'uint256']
        // [EXACT_TOKENS_IN_FOR_BPT_OUT, amountsIn, minimumBPT]
        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[1] = _excessEureFunds;
        uint256 minimumBPT = (_excessEureFunds * SLIPP) / MAX_BPS;
        bytes memory userData =
            abi.encode(StablePoolUserData.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, amountsIn, minimumBPT);

        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest(assets, maxAmountsIn, userData, false);

        bytes memory joinPoolPayload =
            abi.encodeWithSelector(IVault.joinPool.selector, BPT_EURE_STEUR_POOL_ID, _avatar, _avatar, request);

        // 3. batch approval and join into a multicall
        IMulticall.Call[] memory calls_ = new IMulticall.Call[](2);
        calls_[0] = IMulticall.Call(address(EURE), approvalPayload);
        calls_[1] = IMulticall.Call(address(BALANCER_VAULT), joinPoolPayload);

        bytes memory multiCallPayalod = abi.encodeWithSelector(IMulticall.aggregate.selector, calls_);

        delayModule.execTransactionFromModule(MULTICALL_V3, 0, multiCallPayalod, 1);

        emit BptTopup(_avatar, _excessEureFunds, block.timestamp);

        return calls_;
    }
}
