// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IRewardPoolDepositWrapper} from "../interfaces/aura/IRewardPoolDepositWrapper.sol";
import {IBoosterLite} from "../interfaces/aura/IBoosterLite.sol";
import {IBaseRewardPool4626} from "../interfaces/aura/IBaseRewardPool4626.sol";

import "@balancer-v2/interfaces/contracts/vault/IVault.sol";
import "@balancer-v2/interfaces/contracts/solidity-utils/misc/IERC4626.sol";

abstract contract RoboSaverConstants {
    uint16 constant MAX_BPS = 10_000;

    uint256 constant EURE_TOKEN_BPT_INDEX = 2;
    uint256 constant EURE_TOKEN_BPT_INDEX_USER = 1;
    uint256 constant MODULE_PAGE_SIZE = 1;
    uint256 constant OPERATION_DELEGATECALL = 1;

    address constant MULTICALL3 = 0xcA11bde05977b3631167028862bE2a173976CA11;

    IVault constant BALANCER_VAULT = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    bytes32 constant BPT_STEUR_EURE_POOL_ID = 0x06135a9ae830476d3a941bae9010b63732a055f4000000000000000000000065;
    bytes32 constant SET_ALLOWANCE_KEY = keccak256("SPENDING_ALLOWANCE");

    IERC4626 constant AURA_GAUGE_STEUR_EURE = IERC4626(0x408883E983695DeC78CF66480e6eFeF907a73c21);

    IRewardPoolDepositWrapper constant AURA_DEPOSITOR =
        IRewardPoolDepositWrapper(0x0Fec3d212BcC29eF3E505B555D7a7343DF0B7F76);
    IBoosterLite constant AURA_BOOSTER = IBoosterLite(0x98Ef32edd24e2c92525E59afc4475C1242a30184);
}
