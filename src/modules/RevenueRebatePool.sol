// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IsCUR.sol";
import "../interfaces/ICURStaking.sol";

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
    address public curStaking;

    uint256 public totalRevenue;
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

    // ============================================
    // Constructor
    // ============================================
    
    /**
     * @notice Initializes the RevenueRebatePool contract
     * @param _curToken Address of the CUR token
     * @param _sCURToken Address of the sCUR token
     */
    constructor(address _curToken, address _sCURToken, address _curStaking) Ownable(msg.sender){
        if(_curToken == address(0)) revert ZeroAddress();
        if(_sCURToken == address(0)) revert ZeroAddress();
        if(_curStaking == address(0)) revert ZeroAddress();

        curToken = IERC20(_curToken);
        sCURToken = IsCUR(_sCURToken);
        curStaking = _curStaking;

        totalRevenue = 0;
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
        if(amount == 0) revert ZeroAmount();
        curToken.transferFrom(msg.sender, address(this), amount);
        totalRevenue += amount;
        emit RevenueDeposited(msg.sender, amount);
    

    }


    // ============================================
    // Revenue Injection
    // ============================================
    
    /**
     * @notice Injects accumulated CUR revenue into the sCUR value pool
     * @dev Converts protocol revenue into underlying value growth for sCUR holders by updating the sCUR exchange rate
     * @param amount Amount of CUR revenue to inject into the sCUR pool
     */
    function _injectToSCUR(uint256 amount) internal {
        //检查amount是否大于0
        if(amount == 0) revert ZeroAmount();
        //检查totalRevenue是否有足够
        if(amount > totalRevenue) revert ExceedsRevenue();
        //检查cur是否充足
        uint256 balance = curToken.balanceOf(address(this));
        if(amount > balance) revert InsufficientBalance();
        
        curToken.transfer(curStaking, amount);
        //更新汇率
        sCURToken.updateExchangeRate(amount);

        //更新taotalRevenue
        totalRevenue -= amount;
        //发送注入事件
        emit RevenueInjected(amount);

    }

    /**
     * @notice Injects specified amount of CUR into sCUR pool
     * @dev Only callable by contract owner
     * @param amount Amount of CUR to inject
     */
    function injectToSCUR(uint256 amount) public nonReentrant onlyOwner whenNotPaused{
        _injectToSCUR(amount);
    }

    /**
     * @notice Injects all accumulated revenue into sCUR pool
     * @dev Only callable by contract owner, requires totalRevenue >= threshold
     */
    function injectAll() public nonReentrant onlyOwner whenNotPaused{
        if(totalRevenue < threshold) revert BelowThreshold();

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

    // ============================================
    // View Functions
    // ============================================
    
    /**
     * @notice Gets the current CUR balance of this contract
     * @return Current CUR balance
     */
    function getContractBalance() public view returns(uint256) {
        return curToken.balanceOf(address(this));
    } 

    // ============================================
    // Admin Functions
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