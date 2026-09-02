// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
 
/**
 * @title IRevenueRebatePool
 * @dev Interface for RevenueRebatePool;
 */
interface IRevenueRebatePool {
    function depositRevenue(uint256 amount) external;
    function injectToSCUR(uint256 amount) external;
    function injectAll() external;
    function setNewthreshold(uint256 newthreshold) external;
    function getContractBalance() external;

    event RevenueDeposited(address indexed user, uint256 amount);
    event RevenueInjected(uint256 amount);
    event RevenueInjectedAll(uint256 amount);
    event ThresholdUpdated(uint256 newthreshold);
}