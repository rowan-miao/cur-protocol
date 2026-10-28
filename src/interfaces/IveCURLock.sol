// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IveCURLock
 * @dev Interface for veCURLock;
 */
interface IveCURLock {
    function lock(uint256 duration) external;
    function unlock() external;
    function earlyUnlock() external;

    function getBonusByDuration(uint256 duration) external pure returns (uint256);
    function isValidDuration(uint256 duration) external pure returns (bool);
    function getMaxLockDuration(address user) external view returns (uint256);
    function calculatePenalty(address user) external view returns (uint256);
    function emergencyBreakLock(address user) external returns (uint256);

    function getRemainingTime(address user) external view returns (uint256);
    function getBonus(address user) external view returns (uint256);
    function isLocked(address user) external view returns (bool);
    function paused() external view returns (bool);

    event Locked(address indexed user, uint256 duration, uint256 bonusFactor, uint256 endTime);
    event Unlocked(address indexed user, uint256 amount);
    event EarlyUnlocked(address indexed user, uint256 amount, uint256 penalty);
}
