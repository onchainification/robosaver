// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IEURe {
    function mintTo(address to, uint256 amount) external returns (bool ok);
}
