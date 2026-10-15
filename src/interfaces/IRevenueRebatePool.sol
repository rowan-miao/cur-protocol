// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IRevenueRebatePool
 * @dev Interface for RevenueRebatePool;
 */
interface IRevenueRebatePool {
    function depositRevenue(uint256 amount) external;
    function getContractBalance() external view returns (uint256);
    function recordUnallocatedEmission(uint256 amount) external;

    event RevenueDeposited(address indexed user, uint256 amount);
    event UnallocatedEmissionRecorded(uint256 amount);
}
