// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IIncentiveGauge
 * @dev Interface for IncentiveGauge;
 */
interface IIncentiveGauge {
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user);
    event GetReward(address indexed user, uint256 reward);
    event LockExecuted(address indexed user, uint256 additialWeight);
    event UnlockExecuted(address indexed user, uint256 removeWeight);
    event EarlyUnlockExecuted(address indexed user, uint256 penalty, uint256 removeWeight);
    event EmergencyWithdrawn(address indexed user, uint256 amount);
    event RewardsCleared(address indexed user, uint256 amount);

    function deposit(address user, uint256 amount) external;
    function withdraw(address user, uint256 amount) external;
    function getReward() external;
    function executeLock(address user) external;
    function executeUnlock(address user) external;
    function executeEarlyUnlock(address user, uint256 penalty) external;
    function gaugeEmergencyWithdraw(address user) external;
    function emergencyClearReward(address user) external;
    function getPendingReward(address user) external view returns (uint256);
    function getRemainingRewards() external view returns (uint256);
    function getCurrentEmissionRate() external view returns (uint256);
}
