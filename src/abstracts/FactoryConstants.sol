// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@chainlink/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {IKeeperRegistryMaster} from "@chainlink/automation/interfaces/v2_1/IKeeperRegistryMaster.sol";
import {IKeeperRegistrar} from "../interfaces/chainlink/IKeeperRegistrar.sol";

abstract contract FactoryConstants {
    IERC20 constant LINK = IERC20(0xE2e73A1c69ecF83F464EFCE6A5be353a37cA09b2);
    IKeeperRegistryMaster constant CL_REGISTRY = IKeeperRegistryMaster(0x299c92a219F61a82E91d2062A262f7157F155AC1);
    IKeeperRegistrar constant CL_REGISTRAR = IKeeperRegistrar(0x0F7E163446AAb41DB5375AbdeE2c3eCC56D9aA32);
}
