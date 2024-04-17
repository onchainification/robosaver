// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IRolesModifier} from "@gnosispay-kit/interfaces/IRolesModifier.sol";
import {IDelayModifier} from "@gnosispay-kit/interfaces/IDelayModifier.sol";
import {IAsset} from "@balancer-v2/interfaces/contracts/vault/IAsset.sol";

import "@balancer-v2/interfaces/contracts/vault/IVault.sol";
import "@balancer-v2/interfaces/contracts/pool-stable/StablePoolUserData.sol";

contract RoboSaverVirtualModule {
    /*//////////////////////////////////////////////////////////////////////////
                                   CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////////////////
                                       ERRORS
    //////////////////////////////////////////////////////////////////////////*/

    error NotTopupAgent(address agent);

    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    event SafeTopup(address indexed safe, uint256 amount, uint256 timestamp);

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/
    constructor(address _delayModule, address _rolesModule, address _topupAgent) {
        delayModule = IDelayModifier(_delayModule);
        rolesModule = IRolesModifier(_rolesModule);

        topupAgent = _topupAgent;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      MODIFIERS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Checks whether a call is authorized to trigger top-up or exec queue txs
    modifier onlyTopupAgents() {
        if (msg.sender != topupAgent) revert NotTopupAgent(msg.sender);
        _;
    }

    /// @dev Check condition and determine whether a task should be executed by Gelato.
    function checker() external view returns (bool canExec, bytes memory execPayload) {
        address cachedAvatar = delayModule.avatar();

        uint256 queueNonce = delayModule.queueNonce();
        uint256 txNonce = delayModule.txNonce();

        if (txNonce != queueNonce) {
            uint256 txQueuedAt = delayModule.getTxCreatedAt(queueNonce - 1);
            // @note triggers the condition for exec the pendant tx in the delay module
            if (block.timestamp - txQueuedAt >= delayModule.txCooldown()) {
                return (true, abi.encodeWithSelector(IDelayModifier.executeNextTx.selector));
            }

            return (false, bytes("Tx cooldown not reached"));
        } else {
            uint256 balance = EURE.balanceOf(cachedAvatar);
            (, uint128 maxRefill,,,) = rolesModule.allowances(SET_ALLOWANCE_KEY);

            // @note it will queue the tx for topup
            if (balance < maxRefill) {
                uint256 topupAmount = maxRefill - balance;
                return (true, abi.encodeWithSelector(this.safeTopup.selector, cachedAvatar, topupAmount));
            }

            return (false, bytes("No queue tx and sufficient balance"));
        }
    }

    /// @notice siphon eure out of the bpt pool
    function safeTopup(address _avatar, uint256 _topupAmount)
        external
        onlyTopupAgents
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
        bytes memory userData = abi.encode(
            StablePoolUserData.ExitKind.BPT_IN_FOR_EXACT_TOKENS_OUT, amountsOut, BPT_EURE_STEUR.balanceOf(_avatar)
        );

        request_ = IVault.ExitPoolRequest(assets, minAmountsOut, userData, false);

        /// siphon eure out of pool
        bytes memory payload = abi.encodeWithSelector(
            IVault.exitPool.selector, BPT_EURE_STEUR_POOL_ID, _avatar, payable(_avatar), request_
        );
        delayModule.execTransactionFromModule(address(BALANCER_VAULT), 0, payload, 0);

        emit SafeTopup(_avatar, _topupAmount, block.timestamp);
    }

    function execQueuedTransaction() external onlyTopupAgents {
        // @note it will execute the pending tx in the delay module
    }

    function transferErc20(address _token, uint256 _tokenTransferAmount, address _destination) external {
        _transferErc20(_token, _tokenTransferAmount, _destination);
    }

    function _transferErc20(address _token, uint256 _tokenTransferAmount, address _destination) internal {
        bytes memory payload = abi.encodeWithSignature("transfer(address,uint256)", _destination, _tokenTransferAmount);
        delayModule.execTransactionFromModule(_token, 0, payload, 0);
    }
}
