// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IDelayModule} from "./interfaces/modules/IDelayModule.sol";

contract RoboSaverModule {
    IDelayModule public delayModule;

    constructor(address _delayModule) {
        delayModule = IDelayModule(_delayModule);
    }

    function transferErc20(address _token, uint256 _tokenTransferAmount, address _destination) public {
        bytes memory payload = abi.encodeWithSignature("transfer(address,uint256)", _destination, _tokenTransferAmount);
        delayModule.execTransactionFromModule(_token, 0, payload, 0);
    }
}
