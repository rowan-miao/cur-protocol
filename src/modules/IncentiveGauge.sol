// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IsCUR.sol";
import "../interfaces/IveCURLock.sol";
import "../interfaces/ICURStaking.sol";
import "../interfaces/IRevenueRebatePool.sol";

/**
 * @title IncentiveGauge
 * @author CUR Protocol Team
 * @notice Incentive gauge contract for distributing inflation rewards
 * @dev Manages user weights and distributes CUR rewards based on locked positions
 * 
 * Features:
 * - Users deposit sCUR to earn inflation rewards
 * - Weights are calculated based on lock bonuses from veCURLock
 * - Rewards are distributed using a rewardPerToken accumulation model
 * - Emergency withdrawal functions for pause scenarios
 */
contract IncentiveGauge is Pausable, Ownable, ReentrancyGuard {
    IERC20 public immutable curToken;
    IsCUR public immutable sCURToken;
    ICURStaking public curStake; 
    IveCURLock public veLock;
    IRevenueRebatePool public revenueRebatePool;

    uint256 public constant PRECISION = 1e18;

    uint256 public constant SECONDS_PER_YEAR = 365 days;

    uint256 public constant EMISSION_RATE_Y1 = (15_000_000 * 1e18) / SECONDS_PER_YEAR;
    uint256 public constant EMISSION_RATE_Y2 = (12_000_000 * 1e18) / SECONDS_PER_YEAR;
    uint256 public constant EMISSION_RATE_Y3 = (8_000_000 * 1e18) / SECONDS_PER_YEAR;
    uint256 public constant EMISSION_RATE_Y4 = (5_000_000 * 1e18) / SECONDS_PER_YEAR;

    uint256 public startTime;
    uint256 public rewardPerToken;
    uint256 public lastUpdateTime;
    uint256 public emissionRate;
    uint256 public totalWeight;

    // ============================================
    // Structs
    // ============================================

    /**
     * @title UserInfo
     * @notice User-specific staking information
     */
    struct UserInfo {
        uint256 amount;
        uint256 weight;
        uint256 rewardPerTokenPaid;
        uint256 pendingRewards;
    }
 
    /// @notice Mapping of user addresses to their staking information
    mapping(address => UserInfo) public users;

    // ============================================
    // Events
    // ============================================
    
    /// @notice Emitted when a user deposits sCUR
    event Deposit(address indexed user, uint256 amount);
    /// @notice Emitted when a user withdraws sCUR
    event Withdraw(address indexed user, uint256 amount);
    /// @notice Emitted when a user claims rewards
    event GetReward(address indexed user, uint256 reward);
    /// @notice Emitted when a lock is executed (weight increased)
    event LockExecuted(address indexed user, uint256 additialWeight);
    /// @notice Emitted when an unlock is executed (weight decreased)
    event UnlockExecuted(address indexed user, uint256 removeWeight);
    /// @notice Emitted when an early unlock is executed (penalty applied)
    event EarlyUnlockExecuted(address indexed user, uint256 penalty, uint256 removeWeight);
    /// @notice Emitted during emergency withdrawal
    event EmergencyWithdrawn(address indexed user, uint256 amount);
    /// @notice Emitted when rewards are cleared during emergency
    event RewardsCleared(address indexed user, uint256 amount);

    // ============================================
    // Errors
    // ============================================
    
    /// @notice Thrown when zero address is provided
    error ZeroAddress();
    /// @notice Thrown when caller is not authorized
    error Unauthorized();
    /// @notice Thrown when amount is zero
    error ZeroAmount();
    /// @notice Thrown when reward is zero
    error ZeroReward();
    /// @notice Thrown when amount exceeds available balance
    error InsufficientAmount();
    /// @notice Thrown when user has no assets to withdraw
    error NoAssets();


    // ============================================
    // Constructor
    // ============================================
    
    /**
     * @notice Initializes the IncentiveGauge contract
     * @param _curToken Address of the CUR token
     * @param _sCURToken Address of the sCUR token
     * @param _curStake Address of the CURStaking contract
     * @param _veLock Address of the veCURLock contract
     * @param _revenueRebatePool Address of the RevenueRebatePool contract
     */
    constructor(address _curToken, address _sCURToken, address _curStake, address _veLock, address _revenueRebatePool) Ownable(msg.sender){
        if(_curToken == address(0)) revert ZeroAddress();
        if(_sCURToken == address(0)) revert ZeroAddress();
        if(_curStake == address(0)) revert ZeroAddress();
        if(_veLock == address(0)) revert ZeroAddress();
        if(_revenueRebatePool == address(0)) revert ZeroAddress();

        curToken = IERC20(_curToken);
        sCURToken = IsCUR(_sCURToken);
        curStake = ICURStaking(_curStake);
        veLock = IveCURLock(_veLock);
        revenueRebatePool = IRevenueRebatePool(_revenueRebatePool);

        startTime = block.timestamp;
        lastUpdateTime = block.timestamp;
        emissionRate = EMISSION_RATE_Y1;  
        rewardPerToken = 0;  
        totalWeight = 0; 
        
    }

    // ============================================
    // Internal Functions
    // ============================================
    
    /**
     * @notice Gets the current emission rate based on elapsed time
     * @dev Rate decreases over 4 years according to schedule
     * @return Current emission rate (CUR per second)
     */
    function _getCurrentEmissionRate() internal view returns (uint256){
        uint256 elapsed = block.timestamp - startTime;
        if(elapsed < 365 days) return EMISSION_RATE_Y1;
        if(elapsed < 730 days) return EMISSION_RATE_Y2;
        if(elapsed < 1095 days) return EMISSION_RATE_Y3;
        if(elapsed < 1460 days) return EMISSION_RATE_Y4;
        return 0;

    }

    /**
     * @notice Updates reward accumulator for a specific user
     * @dev Called before any state-changing operation
     * @param user User address (can be zero for global update only)
     */
    function _updateReward(address user) internal {
        uint256 timeDelta  = block.timestamp - lastUpdateTime;
        if(totalWeight > 0 && timeDelta > 0){
            uint256 rewardAdded = _getCurrentEmissionRate() * timeDelta; 
            rewardPerToken += (rewardAdded * PRECISION) / totalWeight;
        }

        lastUpdateTime = block.timestamp;

        if(user != address(0)){
            UserInfo storage userInfo = users[user];
            uint256 pending = userInfo.weight * (rewardPerToken - userInfo.rewardPerTokenPaid) / PRECISION;
            if(pending > 0) {
                userInfo.pendingRewards += pending;
        
            }
            userInfo.rewardPerTokenPaid = rewardPerToken;
        }


    }

   
    // ============================================
    // Core Functions
    // ============================================
    
    /**
     * @notice Deposits sCUR into the gauge
     * @dev Only callable by CURStaking contract
     * @param user User address
     * @param amount Amount of sCUR to deposit
     */
    function deposit(address user, uint256 amount) public nonReentrant whenNotPaused {
        //检查curstaking权限
        if(msg.sender != address(curStake)) revert Unauthorized();
        //检查amount是否大于零
        if(amount == 0) revert ZeroAmount();
        //更新结算历史权重
        _updateReward(user);

        UserInfo storage userInfo = users[user];

        uint256 bonus = veLock.getBonus(user);

        uint256 addedWeight = (amount * bonus) / PRECISION;

        //更新用户权重
        userInfo.amount += amount;
        userInfo.weight += addedWeight;
        //更新总权重
        totalWeight += addedWeight;
     
        //发送事件
        emit Deposit(user, amount);


    }
    
    /**
     * @notice Withdraws sCUR from the gauge
     * @dev Only callable by CURStaking contract
     * @param user User address
     * @param amount Amount of sCUR to withdraw
     */
    function withdraw(address user, uint256 amount) public nonReentrant whenNotPaused {
        if(msg.sender != address(curStake)) revert Unauthorized();
        if(amount == 0) revert ZeroAmount();

        _updateReward(user);

        UserInfo storage userInfo = users[user];

        if(userInfo.amount < amount) revert InsufficientAmount();

        uint256 removedWeight = (userInfo.weight * amount) / userInfo.amount;

        userInfo.amount -= amount;
        userInfo.weight -= removedWeight;

        totalWeight -= removedWeight;
        
        sCURToken.transfer(user, amount);
       
        emit Withdraw(user, amount);

    }

    /**
     * @notice Claims pending rewards for caller
     */
    function getReward() public nonReentrant whenNotPaused {
        //更新权重
        _updateReward(msg.sender);
        //获得用户信息
        UserInfo storage userInfo = users[msg.sender];
        //计算用户获得的奖励
        uint256 reward = userInfo.pendingRewards;
        //检查奖励是否大于零
        if(reward == 0) revert ZeroReward();
        
        //重置待领取奖励
        userInfo.pendingRewards = 0;
        //转账cur
        curToken.transfer(msg.sender, reward);
        //发送事件
        emit GetReward(msg.sender, reward);
    }

    // ============================================
    // Lock Management Functions (called by veCURLock)
    // ============================================
    
    /**
     * @notice Executes lock - updates user weight based on bonus
     * @dev Only callable by veCURLock contract
     * @param user User address
     */
    function executeLock(address user) public nonReentrant whenNotPaused {
        //检查是否拥有veCurLock权限 
        if(msg.sender != address(veLock)) revert Unauthorized();
        //结算历史奖励
        _updateReward(user);
        //更新用户权重
        UserInfo storage userInfo = users[user];
        uint256 oldWeight = userInfo.weight;
        uint256 currentBonus = veLock.getBonus(user);
        uint256 newWeight = (userInfo.amount * currentBonus) / PRECISION;
        userInfo.weight = newWeight;

        totalWeight = totalWeight - oldWeight + newWeight;
    
        //发送时间
        emit LockExecuted(user, newWeight - oldWeight);
    }


     /**
     * @notice Executes unlock - updates user weight after unlock
     * @dev Only callable by veCURLock contract
     * @param user User address
     */
    function executeUnlock(address user) public nonReentrant whenNotPaused {
        //检查是否拥有veCurLock权限 
        if(msg.sender != address(veLock)) revert Unauthorized();
        //结算历史奖励
        _updateReward(user);
        //更新用户权重
        UserInfo storage userInfo = users[user];
        uint256 oldWeight = userInfo.weight; 
    
        uint256 currentBonus = veLock.getBonus(user);

        uint256 newWeight = (userInfo.amount * currentBonus) / PRECISION;

        userInfo.weight = newWeight;
        //更新全局权重
        totalWeight = totalWeight - oldWeight + newWeight;
        //发送时间
        emit UnlockExecuted(user, oldWeight - newWeight);

    }

    /**
     * @notice Executes early unlock - applies penalty and updates weight
     * @dev Only callable by veCURLock contract
     * @param user User address
     * @param penalty Penalty amount to burn
     */
    function executeEarlyUnlock(address user, uint256 penalty) public nonReentrant whenNotPaused {
        //检查是否拥有veCurLock权限 
        if(msg.sender != address(veLock)) revert Unauthorized();
        //结算历史奖励
        _updateReward(user);
        //更新用户权重
        UserInfo storage userInfo = users[user];
        uint256 oldWeight = userInfo.weight;

        if(penalty > 0) {
            if(userInfo.amount < penalty) revert InsufficientAmount();
            
            userInfo.amount -= penalty;
            uint256 curAmount = sCURToken.burnGauge(penalty);

            curStake.withdrawPenalty(curAmount);
        }
        uint256 newWeight = userInfo.amount;

        userInfo.weight = newWeight;
       
        //更新全局权重
        totalWeight = totalWeight - oldWeight + newWeight;

        uint256 pendingReward = userInfo.pendingRewards;

        if(pendingReward > 0){
            userInfo.pendingRewards = 0;
            curToken.transfer(address(revenueRebatePool), pendingReward);
        }

        uint256 weightRemoved = oldWeight - newWeight;
        //发送时间
        emit EarlyUnlockExecuted(user, penalty, weightRemoved);
    }


    // ============================================
    // Emergency Functions
    // ============================================
    
    /**
     * @notice Emergency withdrawal (only available when paused)
     * @dev User forfeits all pending rewards, only receives sCUR
     * @param user User address to withdraw for
     */
    function gaugeEmergencyWithdraw(address user) public nonReentrant whenPaused {
        if (msg.sender != address(curStake)) revert Unauthorized();
    
        UserInfo storage userInfo = users[user];
        uint256 amount = userInfo.amount;
        uint256 userWeight = userInfo.weight;
    
        if (amount == 0) revert NoAssets();
    
        totalWeight -= userWeight;

        userInfo.amount = 0;
        userInfo.weight = 0;
        userInfo.pendingRewards = 0; 
        userInfo.rewardPerTokenPaid = 0;
    
        // 返还 sCUR 给用户
        sCURToken.transfer(user, amount);
    
        emit EmergencyWithdrawn(user, amount);
    }

    /**
     * @notice Clears user's pending rewards during emergency
     * @dev Only callable by CURStaking when paused
     * @param user User address to clear rewards for
     */
    function emergencyClearReward(address user) public nonReentrant whenPaused {
        if (msg.sender != address(curStake)) revert Unauthorized();
    
        UserInfo storage userInfo = users[user];

        uint256 pending = userInfo.pendingRewards + (userInfo.weight * (rewardPerToken - userInfo.rewardPerTokenPaid) / PRECISION);
    
        userInfo.pendingRewards = 0;
        userInfo.rewardPerTokenPaid = rewardPerToken;

        if (pending > 0) {
            emit RewardsCleared(user, pending);
        }
    }

    // ============================================
    // View Functions
    // ============================================
    
    /**
     * @notice Calculates pending reward for a user
     * @param user User address
     * @return Total pending reward amount
     */
    function getPendingReward(address user) public view returns (uint256) {
        UserInfo storage userInfo = users[user];
        uint256 pending = userInfo.weight * (rewardPerToken - userInfo.rewardPerTokenPaid) / PRECISION;
        return userInfo.pendingRewards + pending;
    }

    /**
     * @notice Returns the remaining CUR reward balance held by the gauge.
     * @dev Represents the amount of CUR available for reward distribution.
     * @return Remaining CUR reward amount.
     */
    function getRemainingRewards() public view returns (uint256) {
        return curToken.balanceOf(address(this));
    }

    /**
     * @notice Returns the current CUR emission rate.
     * @dev Calculates the current reward emission speed based on the protocol schedule.
     * @return Current emission rate.
     */
    function getCurrentEmissionRate() public view returns (uint256) {
        return _getCurrentEmissionRate();
    }

    // ============================================
    // Admin Functions
    // ============================================
    
    /**
     * @notice Pauses the contract
     * @dev Only callable by owner
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the contract
     * @dev Only callable by owner
     */
    function unpause() public onlyOwner {
        _unpause();
    }

   

}