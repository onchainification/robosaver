// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IVoterProxyLite {
    function balanceOfPool(address _gauge) external view returns (uint256);
    function claimCrv(address _gauge) external returns (uint256);
    function claimRewards(address _gauge) external returns (bool);
    function crv() external view returns (address);
    function deposit(address _token, address _gauge) external returns (bool);
    function execute(address _to, uint256 _value, bytes memory _data) external returns (bool, bytes memory);
    function getName() external pure returns (string memory);
    function initialize(address _mintr, address _crv, address _owner) external;
    function mintr() external view returns (address);
    function operator() external view returns (address);
    function owner() external view returns (address);
    function rewardDeposit() external view returns (address);
    function setOperator(address _operator) external;
    function setOwner(address _owner) external;
    function setRewardDeposit(address _withdrawer, address _rewardDeposit) external;
    function setStashAccess(address _stash, bool _status) external returns (bool);
    function setSystemConfig(address _mintr) external returns (bool);
    function withdraw(address _asset) external returns (uint256 balance);
    function withdraw(address _token, address _gauge, uint256 _amount) external returns (bool);
    function withdrawAll(address _token, address _gauge) external returns (bool);
    function withdrawer() external view returns (address);
}
