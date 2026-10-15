// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IsCUR.sol";
import "../interfaces/ICURStaking.sol";
import "../interfaces/IIncentiveGauge.sol";

/**
 * @title RevenueRebatePool
 * @author CUR Protocol Team
 * @notice Protocol revenue collection and injection pool
 * @dev Collects protocol revenue and injects CUR into sCUR to increase exchange rate
 *
 * Features:
 * - Collect protocol revenue (fees, ecosystem income)
 * - Inject accumulated revenue into sCUR pool
 * - Automatic injection threshold mechanism
 * - Emergency pause functionality
 */
contract RevenueRebatePool is Pausable, Ownable, ReentrancyGuard {
    IERC20 public immutable curToken;
    IsCUR public immutable sCURToken;
    ICURStaking public immutable curStaking;
    IIncentiveGauge public gauge;

    uint256 public totalRevenue;
    uint256 public totalUnallocatedEmission;
    uint256 public threshold = 1000 * 1e18;

    // ============================================
    // Events
    // ============================================

    /// @notice Emitted when revenue is deposited
    event RevenueDeposited(address indexed user, uint256 amount);
    /// @notice Emitted when revenue is injected into sCUR
    event RevenueInjected(uint256 amount);
    /// @notice Emitted when all accumulated revenue is injected
    event RevenueInjectedAll(uint256 amount);
    /// @notice Emitted when injection threshold is updated
    event ThresholdUpdated(uint256 newthreshold);
    /// @notice Emitted when unallocated emission is recorded
    event UnallocatedEmissionRecorded(uint256 amount);
    /// @notice Emitted when IncentiveGauge address is updated
    event GaugeUpdated(address indexed oldGauge, address indexed newGauge);

    // ============================================
    // Errors
    // ============================================

    /// @notice Thrown when zero address is provided
    error ZeroAddress();
    /// @notice Thrown when zero amount is provided
    error ZeroAmount();
    /// @notice Thrown when injection amount exceeds total revenue
    error ExceedsRevenue();
    /// @notice Thrown when contract has insufficient CUR balance
    error InsufficientBalance();
    /// @notice Thrown when total revenue is below threshold for injectAll
    error BelowThreshold();
    /// @notice Thrown when caller is not authorized
    error Unauthorized();
    /// @notice Thrown when sCUR total supply is zero (cannot inject)
    error NoSCURSupply();

    // ============================================
    // Modifiers
    // ============================================

    /**
     * @notice Restricts function access to the IncentiveGauge contract only
     * @dev Reverts with Unauthorized if caller is not gauge
     */
    modifier onlyGauge() {
        if (msg.sender != address(gauge)) revert Unauthorized();
        _;
    }

    // ============================================
    // Constructor
    // ============================================

    /**
     * @notice Initializes the RevenueRebatePool contract
     * @param _curToken Address of the CUR token
     * @param _sCURToken Address of the sCUR token
     * @param _curStaking Address of the CURStaking contract
     */
    constructor(address _curToken, address _sCURToken, address _curStaking) Ownable(msg.sender) {
        if (_curToken == address(0)) revert ZeroAddress();
        if (_sCURToken == address(0)) revert ZeroAddress();
        if (_curStaking == address(0)) revert ZeroAddress();

        curToken = IERC20(_curToken);
        sCURToken = IsCUR(_sCURToken);
        curStaking = ICURStaking(_curStaking);

        totalRevenue = 0;
        totalUnallocatedEmission = 0;
    }

    // ============================================
    // Revenue Collection
    // ============================================

    /**
     * @notice Deposits protocol revenue into the pool
     * @dev Anyone can deposit, typically called by protocol income sources
     * @param amount Amount of CUR to deposit
     */
    function depositRevenue(uint256 amount) public nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        curToken.transferFrom(msg.sender, address(this), amount);
        totalRevenue += amount;
        emit RevenueDeposited(msg.sender, amount);
    }

    /**
     * @notice Records unallocated emission from IncentiveGauge
     * @dev Only callable by IncentiveGauge when totalWeight == 0 (no stakers).
     *      Increases totalUnallocatedEmission accounting.
     * @param amount Amount of unallocated emission to record
     */
    function recordUnallocatedEmission(uint256 amount) public onlyGauge {
        if (amount == 0) revert ZeroAmount();
        totalUnallocatedEmission += amount;
        emit UnallocatedEmissionRecorded(amount);
    }

    // ============================================
    // Revenue Injection
    // ============================================

    /**
     * @notice Injects specified amount of CUR into sCUR pool
     * @dev Only callable by contract owner
     * @param amount Amount of CUR to inject
     */
    function injectToSCUR(uint256 amount) public onlyOwner nonReentrant whenNotPaused {
        _injectToSCUR(amount);
    }

    /**
     * @notice Internal logic to inject revenue into the sCUR pool
     * @dev Must be called within a nonReentrant context
     * @param amount Amount of CUR to inject
     */
    function _injectToSCUR(uint256 amount) internal {
        //检查amount是否大于0
        if (amount == 0) revert ZeroAmount();
        //检查totalRevenue是否有足够
        if (amount > totalRevenue) revert ExceedsRevenue();
        if (address(curStaking) == address(0)) revert ZeroAddress();

        if (sCURToken.totalSupply() == 0) revert NoSCURSupply();

        //检查cur是否充足
        uint256 balance = curToken.balanceOf(address(this));
        if (amount > balance) revert InsufficientBalance();

        //更新taotalRevenue
        totalRevenue -= amount;

        sCURToken.updateExchangeRate(amount);

        curToken.transfer(address(curStaking), amount);

        //发送注入事件
        emit RevenueInjected(amount);
    }

    /**
     * @notice Injects all accumulated revenue into sCUR pool
     * @dev Only callable by contract owner, requires totalRevenue >= threshold
     */
    function injectAll() public onlyOwner nonReentrant whenNotPaused {
        if (totalRevenue < threshold) revert BelowThreshold();

        uint256 amount = totalRevenue;
        _injectToSCUR(amount);

        emit RevenueInjectedAll(amount);
    }

    // ============================================
    // Configuration
    // ============================================

    /**
     * @notice Updates the automatic injection threshold
     * @dev Only callable by contract owner
     * @param newthreshold New threshold value (in CUR with 18 decimals)
     */
    function setNewthreshold(uint256 newthreshold) public onlyOwner {
        threshold = newthreshold;
        emit ThresholdUpdated(newthreshold);
    }

    /**
     * @notice Updates the IncentiveGauge contract address
     * @dev Only callable by owner (TimelockController)
     * @param _gauge New IncentiveGauge address
     */
    function setGauge(address _gauge) external onlyOwner {
        if (_gauge == address(0)) revert ZeroAddress();

        address oldGauge = address(gauge);
        gauge = IIncentiveGauge(_gauge);

        emit GaugeUpdated(oldGauge, _gauge);
    }

    // ============================================
    // View Functions
    // ============================================

    /**
     * @notice Gets the current CUR balance of this contract
     * @return Current CUR balance
     */
    function getContractBalance() public view returns (uint256) {
        return curToken.balanceOf(address(this));
    }

    // ============================================
    // Pause Functions
    // ============================================

    /**
     * @notice Pauses the contract (emergency stop)
     * @dev Only callable by contract owner
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the contract
     * @dev Only callable by contract owner
     */
    function unpause() public onlyOwner {
        _unpause();
    }
}
