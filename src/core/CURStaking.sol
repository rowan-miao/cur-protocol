// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IsCUR.sol";
import "../interfaces/IIncentiveGauge.sol";
import "../interfaces/IveCURLock.sol";
import "../interfaces/IRevenueRebatePool.sol";

/**
 * @title CURStaking - Main Staking Contract
 * @notice Core contract for CUR token staking
 * @dev Handles staking CUR to mint sCUR, gauge operations for yield, and user weight management
 * 
 * Features:
 * - Stake CUR to receive sCUR (yield-bearing token)
 * - Enter/exit gauge to participate in inflation rewards
 * - Lock positions to get bonus weights (via veCURLock)
 * - Emergency pause functionality
 */
contract CURStaking is Pausable, Ownable, ReentrancyGuard {
    IERC20 public immutable curToken;
    IsCUR public immutable sCURToken;
    IIncentiveGauge public gauge;
    IveCURLock public veLock;
    IRevenueRebatePool public revenueRebatePool;

    uint256 private constant PRECISION = 1e18;

    // ============================================
    // Structs
    // ============================================

    /**
     * @title UserInfo
     * @notice User-specific staking information
     * @dev Stores all relevant data for each staker
     */
    struct UserInfo {
        uint256 stakedSCUR;
        uint256 depositedGauge;
    }

    mapping(address => UserInfo) public users;

    // ============================================
    // Events
    // ============================================
    
    /// @notice Emitted when a user stakes CUR and receives sCUR
    event Staked(address indexed user, uint256 CURAmount, uint256 sCURAmount);

    /// @notice Emitted when a user unstakes sCUR and receives CUR
    event UnStaked(address indexed user, uint256 sCURAmount, uint256 CURAmount);

    /// @notice Emitted when sCUR is deposited into the gauge
    event EnterGauge(address indexed user, uint256 sCURAmount);

    /// @notice Emitted when sCUR is withdrawn from the gauge
    event ExitGauge(address indexed user, uint256 sCURAmount);

    /// @notice Emitted during emergency withdrawal when contract is paused
    event EmergencyWithdrawn(address indexed user, uint256 sCURAmount, uint256 CURAmount);

    /// @notice Emitted when penalty CUR is withdrawn to RevenueRebatePool
    event PenaltyWithdrawn(address indexed receiver, uint256 CURAmount);

    // ============================================
    // Errors
    // ============================================

    /// @notice Thrown when the provided amount is zero
    error ZeroAmount();

    /// @notice Thrown when a zero address is provided
    error ZeroAddress();

    /// @notice Thrown when the user has insufficient balance
    error InsufficientAmount();

    /// @notice Thrown when the user has insufficient free sCUR (not in gauge)
    error InsufficientFreeSCUR();

    /// @notice Thrown when the contract has insufficient CUR balance
    error InsufficientCURBalance();

    /// @notice Thrown when the user has no assets to withdraw
    error NoAssets();

    /// @notice Thrown when the caller is not authorized
    error Unauthorized();

    // ============================================
    // Constructor
    // ============================================
    
    /**
     * @notice Initializes the CURStaking contract
     * @dev Sets up all required contract references
     * @param _curToken Address of the CUR token contract
     * @param _sCURToken Address of the sCUR token contract
     * @param _gauge Address of the IncentiveGauge contract
     * @param _veLock Address of the veCURLock contract
     */
    constructor(address _curToken, address _sCURToken, address _gauge, address _veLock, address _revenueRebatePool) Ownable(msg.sender){
        if (_curToken == address(0)) revert ZeroAddress();
        if (_sCURToken == address(0)) revert ZeroAddress();
        if (_gauge == address(0)) revert ZeroAddress();
        if (_veLock == address(0)) revert ZeroAddress();
        if (_revenueRebatePool == address(0)) revert ZeroAddress();
        
        curToken = IERC20(_curToken);
        sCURToken = IsCUR(_sCURToken);
        gauge = IIncentiveGauge(_gauge);
        veLock = IveCURLock(_veLock);
        revenueRebatePool = IRevenueRebatePool(_revenueRebatePool);
    }
    
    
    // ============================================
    // Stake Functions
    // ============================================
    
    /**
     * @notice Stakes CUR tokens and receives sCUR
     * @dev User must approve CUR token spending before calling
     * @param CURAmount Amount of CUR tokens to stake
     */
    function stake(uint256 CURAmount) public nonReentrant whenNotPaused {
        //判断CURAmount是否大于0
        if(CURAmount == 0) revert ZeroAmount();

        //计算应获得的sCUR
        uint256 exchangeRate = sCURToken.getExchangeRate();
        uint256 sCURAmount = (CURAmount * PRECISION) / exchangeRate;

        //更新用户状态
        users[msg.sender].stakedSCUR += sCURAmount;
        //铸造
        sCURToken.mint(msg.sender, sCURAmount);
        //转账CUR
        curToken.transferFrom(msg.sender, address(this), CURAmount);
        //发送事件
        emit Staked(msg.sender, CURAmount, sCURAmount);

    }

    // ============================================
    // Unstake Functions
    // ============================================
    
    /**
     * @notice Unstakes sCUR tokens and receives underlying CUR
     * @dev Can only unstake sCUR that is NOT locked in the gauge
     * @param sCURAmount Amount of sCUR tokens to unstake
     */
    function unstake(uint256 sCURAmount) public nonReentrant whenNotPaused {
        //检查scur是否大于零
        if(sCURAmount == 0) revert ZeroAmount();
         
        UserInfo storage user = users[msg.sender];
        //判断当前可赎回的scur < scuramount的数量
        uint256 freeSCUR = user.stakedSCUR - user.depositedGauge;
        if(freeSCUR < sCURAmount) revert InsufficientFreeSCUR();

        //更新用户状态
        user.stakedSCUR -= sCURAmount;

        //销毁
        uint256 CURAmount = sCURToken.redeem(msg.sender, sCURAmount);
        curToken.transfer(msg.sender, CURAmount);
        //发送事件
        emit UnStaked(msg.sender, sCURAmount, CURAmount);
        
    }

    // ============================================
    // Gauge Functions
    // ============================================
    
    /**
     * @notice Enters the gauge with sCUR tokens to earn inflation rewards
     * @dev Deposited sCUR cannot be unstaked until gauge exit
     * @param sCURAmount Amount of sCUR to deposit into gauge
     */
    function enterGauge(uint256 sCURAmount) public nonReentrant whenNotPaused {
        //检查amount
        if(sCURAmount == 0) revert ZeroAmount();
        UserInfo storage user = users[msg.sender];
        //计算可用的scur
        uint256 availableSCUR = user.stakedSCUR - user.depositedGauge;
        if(availableSCUR < sCURAmount) revert InsufficientAmount();
        //更新全局变量
        user.depositedGauge += sCURAmount; 

        sCURToken.transferFrom(msg.sender, address(gauge), sCURAmount);
        
        //通知矿池
        gauge.deposit(msg.sender, sCURAmount);
        //发送事件
        emit EnterGauge(msg.sender, sCURAmount);            
    
    }

    /**
     * @notice Exits the gauge and withdraws sCUR tokens
     * @param sCURAmount Amount of sCUR to withdraw from gauge
     */
    function exitGauge(uint256 sCURAmount) public nonReentrant whenNotPaused {
        //检查scuramount是否小于零
        if(sCURAmount == 0) revert ZeroAmount();
        //获得用户信息
        UserInfo storage user = users[msg.sender];
        //计算可赎回的scur
        uint256 exitSCUR = user.depositedGauge;
        if(exitSCUR < sCURAmount) revert InsufficientAmount();

        //更新全局变量
        user.depositedGauge -= sCURAmount;
        
        //通知矿池
        gauge.withdraw(msg.sender, sCURAmount);
        //发送事件
        emit ExitGauge(msg.sender, sCURAmount);

    }

    /**
     * @notice Emergency withdrawal when contract is paused
     * @dev Users forfeit all pending rewards. Only available when contract is paused.
     */
    function emergencyWithdraw() public nonReentrant whenPaused{
        UserInfo storage user = users[msg.sender];

        uint256 sCURAmount = user.stakedSCUR;
        uint256 gaugeAmount = user.depositedGauge;

        if(sCURAmount == 0) revert NoAssets();

        if(gaugeAmount > 0){
            gauge.gaugeEmergencyWithdraw(msg.sender);
        }

        user.stakedSCUR = 0;
        user.depositedGauge = 0;
    
        gauge.emergencyClearReward(msg.sender);

        uint256 CURAmount = sCURToken.emergencyRedeem(msg.sender, sCURAmount);
        curToken.transfer(msg.sender, CURAmount);

        emit EmergencyWithdrawn(msg.sender, sCURAmount, CURAmount);
    }


    /**
     * @notice Withdraws penalty CUR to RevenueRebatePool
     * @dev Only callable by IncentiveGauge
     * @param CURAmount Amount of CUR to withdraw as penalty
     */
    function withdrawPenalty(uint256 CURAmount) external nonReentrant whenNotPaused {
        if (msg.sender != address(gauge)) revert Unauthorized();
        if (CURAmount == 0) revert ZeroAmount();
        if (address(revenueRebatePool) == address(0)) revert ZeroAddress();

        uint256 balance = curToken.balanceOf(address(this));
        if (balance < CURAmount) revert InsufficientCURBalance();

        curToken.transfer(address(revenueRebatePool), CURAmount);

        emit PenaltyWithdrawn(address(revenueRebatePool), CURAmount);
    }

    // ============================================
    // View Functions
    // ============================================
    
    /**
     * @notice Gets comprehensive information about a user
     * @param user Address of the user to query
     * @return stakedSCUR Total sCUR staked by the user
     * @return depositedGauge Amount of sCUR currently deposited in gauge
     */
    function getUserInfo(address user) public view returns (
        uint256 stakedSCUR,
        uint256 depositedGauge
    ) {
        UserInfo storage userInfo = users[user];
        return (userInfo.stakedSCUR, userInfo.depositedGauge);
    }


    /**
     * @notice Returns the total amount of CUR currently staked in the protocol.
     * @dev Equal to the total supply of sCUR.
     * @return Total amount of staked CUR.
     */
    function getTotalStaked() public view returns(uint256) {
        return sCURToken.totalSupply();
    }

     
    // ============================================
    // Admin Functions
    // ============================================

    /**
     * @notice Pauses all staking operations
     * @dev Only callable by contract owner
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses staking operations, restoring normal functionality
     * @dev Only callable by contract owner
     */
    function unpause() public onlyOwner {
        _unpause();
    }

    /**
     * @notice Updates the IncentiveGauge contract address
     * @dev Only callable by owner for protocol upgrades
     * @param _gauge New IncentiveGauge contract address
     */
    function setGauge(address _gauge) public onlyOwner {
        if(_gauge == address(0)) revert ZeroAddress();
        gauge = IIncentiveGauge(_gauge);
    }

    /**
     * @notice Updates the veCURLock contract address
     * @dev Only callable by owner for protocol upgrades
     * @param _veLock New veCURLock contract address
     */
    function setVeLock(address _veLock) public onlyOwner {
        if(_veLock == address(0)) revert ZeroAddress();
        veLock = IveCURLock(_veLock);
    }


}
