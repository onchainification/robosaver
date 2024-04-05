// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IDelayModule} from "./interfaces/modules/IDelayModule.sol";

contract RoboSaverModule {
    IDelayModule public delayModule;

    constructor(IDelayModule _delayModule) {
        delayModule = _delayModule;
    }

    function transferErc20(address to, uint256 value) public {
        bytes memory payload = abi.encodeWithSignature("transfer(address,uint256)", to, value);
        delayModule.execTransactionFromModule(to, value, payload, 0);
    }
}
