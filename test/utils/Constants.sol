// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IBalancerQueries} from "@balancer-v2/interfaces/contracts/standalone-utils/IBalancerQueries.sol";

import {ISafeProxyFactory} from "@gnosispay-kit/interfaces/ISafeProxyFactory.sol";

import {FactoryConstants} from "../../src/abstracts/FactoryConstants.sol";
import {RoboSaverConstants} from "../../src//abstracts/RoboSaverConstants.sol";

abstract contract Constants is FactoryConstants, RoboSaverConstants {
    uint256 constant DIFF_MIN_OUT_CALC_ALLOWED = 70000000000000; // 0.00007 ether units

    uint16 constant SLIPPAGE = 200; // 2%

    // @note eure mint: daily allowance + buffer - 1 (to trigger a state of `canExec` = false)
    uint256 constant EURE_TO_MINT = 240e18;
    uint128 constant MIN_EURE_ALLOWANCE = 200e18;
    uint256 constant EURE_BUFFER = 50e18;

    ISafeProxyFactory constant SAFE_FACTORY = ISafeProxyFactory(0xa6B71E26C5e0845f74c812102Ca7114b6a896AB2);
    address constant SAFE_SINGLETON = 0xd9Db270c1B5E3Bd161E8c8503c55cEABeE709552;
    address constant SAFE_EOA_SIGNER = address(5454656565);

    // delay config
    uint256 constant COOLDOWN_PERIOD = 180; // 3 minutes
    uint256 constant EXPIRATION_PERIOD = 1800; // 30 minutes

    // roles config
    uint64 constant ALLOWANCE_PERIOD = 1 days;
    bytes4 constant TRANSFER_SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));

    // bouncer config
    bytes4 constant SET_ALLOWANCE_SELECTOR =
        bytes4(keccak256(bytes("setAllowance(bytes32,uint128,uint128,uint128,uint64,uint64)"))); // 0xa8ec43ee

    // tokens
    address constant EURE = 0xcB444e90D8198415266c6a2724b7900fb12FC56E;
    address constant WETH = 0x6A023CCd1ff6F2045C3309768eAd9E68F978f6e1;
    address constant BPT_STEUR_EURE = 0x06135A9Ae830476d3a941baE9010B63732a055F4;

    address constant EURE_MINTER = 0x882145B1F9764372125861727d7bE616c84010Ef;

    bytes4 constant ADJUST_POOL_SELECTOR = 0xba2f0056;

    // balancer helper
    IBalancerQueries constant BALANCER_QUERIES = IBalancerQueries(0x0F3e0c4218b7b0108a3643cFe9D3ec0d4F57c54e);

    uint96 constant LINK_FOR_TASK_TOP_UP = 1_000e18; // plenty of funds
}
