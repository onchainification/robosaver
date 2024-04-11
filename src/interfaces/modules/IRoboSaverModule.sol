// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IRoboSaverModule {
    function safeTopup(address _avatar, uint256 _topupAmount) external;
}
