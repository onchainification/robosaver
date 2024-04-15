// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "@gnosispay-kit/interfaces/IERC20.sol";
import {IRolesModifier} from "@gnosispay-kit/interfaces/IRolesModifier.sol";
import {IDelayModifier} from "@gnosispay-kit/interfaces/IDelayModifier.sol";

contract RoboSaverVirtualModule {
    /*//////////////////////////////////////////////////////////////////////////
                                   CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    IERC20 constant EUR_E = IERC20(0xcB444e90D8198415266c6a2724b7900fb12FC56E);

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
            uint256 balance = EUR_E.balanceOf(cachedAvatar);
            (, uint128 maxRefill,,,) = rolesModule.allowances(SET_ALLOWANCE_KEY);

            // @note it will queue the tx for topup
            if (balance < maxRefill) {
                uint256 topupAmount = maxRefill - balance;
                return (true, abi.encodeWithSelector(this.safeTopup.selector, cachedAvatar, topupAmount));
            }

            return (false, bytes("No queue tx and sufficient balance"));
        }
    }

    function safeTopup(address _avatar, uint256 _topupAmount) external onlyTopupAgents {
        // @note logic for top-up is to be defined <> amm
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
