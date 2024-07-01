// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

interface IRewardPoolDepositWrapper {
    struct JoinPoolRequest {
        address[] assets;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }

    function bVault() external view returns (address);
    function depositSingle(
        address _rewardPoolAddress,
        address _inputToken,
        uint256 _inputAmount,
        bytes32 _balancerPoolId,
        JoinPoolRequest memory _request
    ) external;
}
