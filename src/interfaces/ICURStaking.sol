// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title ICURStaking
 * @dev Interface for CURStaking;
 */
interface ICURStaking {
    function stake(uint256 CURAmount) external;
    function unstake(uint256 sCURAmount) external;
    function enterGauge(uint256 sCURAmount) external;
    function exitGauge(uint256 sCURAmount) external;
    function emergencyWithdraw() external;
    function getUserInfo(address user) external view returns (uint256 stakedSCUR, uint256 depositedGauge);
    function getTotalStaked() external view returns (uint256);
    function withdrawPenalty(uint256 CURAmount) external;
    function setGauge(address _gauge) external;
    function setVeLock(address _veLock) external;
    function setRevenueRebatePool(address _revenueRebatePool) external;

    event Staked(address indexed user, uint256 CURAmount, uint256 sCURAmount);
    event UnStaked(address indexed user, uint256 sCURAmount, uint256 CURAmount);
    event EnterGauge(address indexed user, uint256 sCURAmount);
    event ExitGauge(address indexed user, uint256 sCURAmount);
    event EmergencyWithdrawn(address indexed user, uint256 amount);
    event PenaltyWithdrawn(address indexed receiver, uint256 CURAmount);
}
