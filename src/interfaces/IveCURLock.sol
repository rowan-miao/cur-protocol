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

    function bindNFT(address nftContract, uint256 tokenId) external;
    function unbindNFT() external;

    function getMaxLockDuration(address user) external view returns(uint256);
    function getRemainingTime(address user) external view returns(uint256);
    function getBonus(address user) external view returns(uint256);
    function isValidDuration(uint256 duration) external view returns(bool);
    function calculatePenalty(address user) external view returns(uint256);
    
    function getUserLockInfo(address user) external view returns(
        uint256 amount,
        uint256 startTime,
        uint256 endTime,
        uint256 duration,
        uint256 bonusFactor,
        bool isLocked
    );
    function getBonusByDuration(uint256 duration) external pure returns(uint256);
    function setIncentiveGauge(address _incentiveGauge) external;


    event Locked(address indexed user, uint256 duration, uint256 bonusFactor, uint256 endTime);
    event Unlocked(address indexed user, uint256 amount);
    event EarlyUnlocked(address indexed user, uint256 amount, uint256 penalty);
    event NFTBound(address indexed user, address indexed nftContract, uint256 tokenId, uint8 tier);
    event NFTUnbound(address indexed user, address indexed nftContract, uint256 tokenId, uint8 tier);
    event NFTCheckerUpdated(address indexed newChecker);
    event IncentiveGaugeUpdated(address indexed newGauge);


}