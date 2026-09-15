// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IsCUR
 * @dev Interface for sCUR
 */
interface IsCUR {
    function mint(address to, uint256 CURAmount) external returns (uint256);
    function redeem(address from, uint256 sCURAmount) external returns (uint256);
    function updateExchangeRate(uint256 additionalCUR) external returns (uint256);
    function emergencyRedeem(address from, uint256 sCURAmount) external returns (uint256);
    function getExchangeRate() external view returns (uint256);
    function addMinter(address minter) external;
    function removeMinter(address minter) external;
    function balanceOf(address user) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function totalSupply() external view returns (uint256);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function burnGauge(uint256 sCURAmount) external returns (uint256);
    function setIncentiveGauge(address _incentiveGauge) external;

    event Mint(address indexed to, uint256 CURAmount, uint256 sCURAmount);
    event Redeem(address indexed from, uint256 CURAmount, uint256 sCURAmount);
    event UpdateExchangeRate(uint256 oldRate, uint256 newRate);
    event MinterAdded(address indexed minter);
    event MinterRemoved(address indexed minter);
    event IncentiveGaugeUpdated(address indexed oldGauge, address indexed newGauge);
}
