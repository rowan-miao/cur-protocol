// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
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
    using SafeERC20 for IERC20;
    IERC20 public immutable curToken;
    IsCUR public immutable sCURToken;
    ICURStaking public curStake;
    IveCURLock public veLock;
    IRevenueRebatePool public revenueRebatePool;

    uint256 public constant PRECISION = 1e18;

    uint256 public constant YEAR = 365 days;

    uint256 public constant ALLOCATION_Y1 = 15_000_000 * 1e18;
    uint256 public constant ALLOCATION_Y2 = 12_000_000 * 1e18;
    uint256 public constant ALLOCATION_Y3 = 8_000_000 * 1e18;
    uint256 public constant ALLOCATION_Y4 = 5_000_000 * 1e18;

    uint256 public constant MAX_EMISSION = 40_000_000 * 1e18;
    uint256 public constant IDLE_REWARD_THRESHOLD = 1000 * 1e18;

    uint256 public startTime;
    uint256 public rewardPerToken;
    uint256 public lastUpdateTime;
    uint256 public totalWeight;
    uint256 public accumulatedIdleRewards;
    uint256 public totalEmitted;

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

    /// @notice Emitted when a lock is executed
    event LockExecuted(address indexed user);

    /// @notice Emitted when an unlock is executed
    event UnlockExecuted(address indexed user);

    /// @notice Emitted when an early unlock is executed (penalty applied)
    event EarlyUnlockExecuted(address indexed user, uint256 penalty, uint256 oldWeight, uint256 newWeight);

    /// @notice Emitted during emergency withdrawal
    event EmergencyWithdrawn(address indexed user, uint256 amount);

    /// @notice Emitted when idle rewards are accumulated (no stakers)
    event IdleRewardsAccumulated(uint256 rewardAdded);

    /// @notice Emitted when accumulated idle rewards are flushed to RevenueRebatePool
    event IdleRewardsFlushed(uint256 amount);

    /// @notice Emitted when a user's pending rewards are confiscated due to early unlock
    event RewardsConfiscated(address indexed user, uint256 pendingReward);

    /// @notice Emitted when the CURStaking contract address is updated
    event CurStakeUpdated(address indexed oldAddress, address indexed newAddress);

    /// @notice Emitted when the veCURLock contract address is updated
    event VeLockUpdated(address indexed oldAddress, address indexed newAddress);

    /// @notice Emitted when the RevenueRebatePool contract address is updated
    event RevenuePoolUpdated(address indexed oldAddress, address indexed newAddress);

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

    /// @notice Thrown when an invalid address is provided
    error InvalidAddress();

    /// @notice Thrown when the new address is identical to the current one
    error SameAddress();

    // ============================================
    // modifiers
    // ============================================

    /**
     * @notice Restricts function access to the CURStaking contract only
     * @dev Reverts with Unauthorized if caller is not curStake
     */
    modifier onlyCurStake() {
        if (msg.sender != address(curStake)) revert Unauthorized();
        _;
    }

    /**
     * @notice Restricts function access to the veCURLock contract only
     * @dev Reverts with Unauthorized if caller is not veLock
     */
    modifier onlyVeLock() {
        if (msg.sender != address(veLock)) revert Unauthorized();
        _;
    }

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
    constructor(address _curToken, address _sCURToken, address _curStake, address _veLock, address _revenueRebatePool)
        Ownable(msg.sender)
    {
        if (_curToken == address(0)) revert ZeroAddress();
        if (_sCURToken == address(0)) revert ZeroAddress();

        curToken = IERC20(_curToken);
        sCURToken = IsCUR(_sCURToken);

        if (_curStake != address(0)) curStake = ICURStaking(_curStake);
        if (_veLock != address(0)) veLock = IveCURLock(_veLock);
        if (_revenueRebatePool != address(0)) revenueRebatePool = IRevenueRebatePool(_revenueRebatePool);

        startTime = block.timestamp;
        lastUpdateTime = block.timestamp;
    }

    // ============================================
    // Internal Functions
    // ============================================

    /**
     * @notice Gets the current emission rate based on elapsed time
     * @dev Rate decreases over 4 years according to schedule
     * @return Current emission rate (CUR per second)
     */
    function _getCurrentEmissionRate() internal view returns (uint256) {
        if (block.timestamp <= startTime) return ALLOCATION_Y1 / YEAR;
        uint256 elapsed = block.timestamp - startTime;
        if (elapsed < YEAR) return ALLOCATION_Y1 / YEAR;
        if (elapsed < 2 * YEAR) return ALLOCATION_Y2 / YEAR;
        if (elapsed < 3 * YEAR) return ALLOCATION_Y3 / YEAR;
        if (elapsed < 4 * YEAR) return ALLOCATION_Y4 / YEAR;
        return 0;
    }

    /**
     * @notice Calculates the emission rewards for the elapsed time
     * @dev Uses current emission rate multiplied by time delta
     * @return rewardAdded Amount of CUR emitted since last update
     */
    function _calculateEmission() internal view returns (uint256 rewardAdded) {
        uint256 timeNow = block.timestamp;

        if (timeNow <= lastUpdateTime || timeNow <= startTime) {
            return 0;
        }

        uint256 from = lastUpdateTime > startTime ? startTime : lastUpdateTime;
        uint256 elapsedStart = from - startTime;
        uint256 elapsedEnd = timeNow - startTime;

        uint256[5] memory boundaries = [uint256(0), YEAR, YEAR * 2, YEAR * 3, YEAR * 4];
        uint256[4] memory allocations = [ALLOCATION_Y1, ALLOCATION_Y2, ALLOCATION_Y3, ALLOCATION_Y4];

        for (uint256 i = 0; i < 4; i++) {
            uint256 yearStart = boundaries[i];
            uint256 yearEnd = boundaries[i + 1];

            if (elapsedEnd <= yearStart) break;

            uint256 overlapStart = elapsedStart > yearStart ? elapsedStart : yearStart;
            uint256 overlapEnd = elapsedEnd < yearEnd ? elapsedEnd : yearEnd;

            if (overlapStart >= overlapEnd) continue;

            uint256 emissionAtStart = allocations[i] * (overlapStart - yearStart) / YEAR;
            uint256 emissionAtEnd = allocations[i] * (overlapEnd - yearStart) / YEAR;
            rewardAdded += emissionAtEnd - emissionAtStart;
        }
    }

    /**
     * @notice Updates global reward index and settles user rewards
     * @dev If totalWeight > 0, distributes rewards. Otherwise accumulates idle rewards.
     * @param user User address (address(0) for global update only)
     */
    function _updateReward(address user) internal {
        uint256 rewardAdded = _calculateEmission();

        if (totalEmitted >= MAX_EMISSION) {
            rewardAdded = 0;
        } else {
            uint256 remainingBudget = MAX_EMISSION - totalEmitted;
            if (rewardAdded > remainingBudget) {
                rewardAdded = remainingBudget;
            }
        }

        totalEmitted += rewardAdded;

        if (rewardAdded > 0) {
            if (totalWeight > 0) {
                rewardPerToken += (rewardAdded * PRECISION) / totalWeight;
            } else {
                accumulatedIdleRewards += rewardAdded;
                emit IdleRewardsAccumulated(rewardAdded);
            }
        }

        lastUpdateTime = block.timestamp;

        if (user != address(0)) {
            _updateUserReward(user);
        }
    }

    /**
     * @notice Recalculates user's weight based on current lock bonus
     * @dev Called before any state-changing operation to sync weight
     * @param user User address
     */
    function _updateWeight(address user) internal {
        UserInfo storage userInfo = users[user];

        uint256 bonus = veLock.getBonus(user);

        uint256 newWeight = (userInfo.amount * bonus) / PRECISION;

        if (newWeight != userInfo.weight) {
            totalWeight = totalWeight - userInfo.weight + newWeight;
            userInfo.weight = newWeight;
        }
    }

    /**
     * @notice Settles user's pending rewards using current weight
     * @dev Does NOT recalculate weight (that's _updateWeight's job)
     * @param user User address
     */
    function _updateUserReward(address user) internal {
        UserInfo storage userInfo = users[user];

        uint256 rewardDelta = rewardPerToken - userInfo.rewardPerTokenPaid;
        if (rewardDelta > 0 && userInfo.weight > 0) {
            uint256 pending = (userInfo.weight * rewardDelta) / PRECISION;
            userInfo.pendingRewards += pending;
        }

        userInfo.rewardPerTokenPaid = rewardPerToken;
    }

    /**
     * @notice Manually flushes accumulated idle rewards to RevenueRebatePool
     * @dev Anyone can call. Protected by nonReentrant for external callers.
     */
    function flushIdleRewards() public nonReentrant whenNotPaused {
        _flushIdleRewards();
    }

    /**
     * @notice Internal logic to flush idle rewards
     * @dev Must be called within a nonReentrant context (deposit/withdraw).
     *      Emits IdleRewardsFlushed when rewards are actually flushed.
     */
    function _flushIdleRewards() internal {
        uint256 amount = accumulatedIdleRewards;
        if (amount == 0) return;
        if (address(revenueRebatePool) == address(0)) revert ZeroAddress();

        accumulatedIdleRewards = 0;
        revenueRebatePool.recordUnallocatedEmission(amount);

        curToken.safeTransfer(address(revenueRebatePool), amount);
        emit IdleRewardsFlushed(amount);
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
    function deposit(address user, uint256 amount) public onlyCurStake nonReentrant whenNotPaused {
        //检查amount是否大于零
        if (amount == 0) revert ZeroAmount();
        //更新结算历史权重
        _updateReward(user);
        _flushIdleRewards();

        UserInfo storage userInfo = users[user];
        userInfo.amount += amount;

        _updateWeight(user);

        //发送事件
        emit Deposit(user, amount);
    }

    /**
     * @notice Withdraws sCUR from the gauge
     * @dev Only callable by CURStaking contract
     * @param user User address
     * @param amount Amount of sCUR to withdraw
     */
    function withdraw(address user, uint256 amount) public onlyCurStake nonReentrant {
        if (amount == 0) revert ZeroAmount();

        _updateReward(user);
        _flushIdleRewards();

        UserInfo storage userInfo = users[user];
        if (userInfo.amount < amount) revert InsufficientAmount();
        userInfo.amount -= amount;

        _updateWeight(user);

        IERC20(address(sCURToken)).safeTransfer(user, amount);

        emit Withdraw(user, amount);
    }

    /**
     * @notice Claims pending rewards for caller
     * @dev Updates reward, flushes idle rewards, transfers pending CUR
     */
    function getReward() public nonReentrant whenNotPaused {
        _updateReward(msg.sender);
        _flushIdleRewards();
        _updateWeight(msg.sender);
        //获得用户信息
        UserInfo storage userInfo = users[msg.sender];
        //计算用户获得的奖励
        uint256 reward = userInfo.pendingRewards;
        //检查奖励是否大于零
        if (reward == 0) revert ZeroReward();

        //重置待领取奖励
        userInfo.pendingRewards = 0;
        //转账cur
        curToken.safeTransfer(msg.sender, reward);
        //发送事件
        emit GetReward(msg.sender, reward);
    }

    // ============================================
    // Lock Management Functions
    // ============================================

    /**
     * @notice Executes lock - updates user weight based on bonus
     * @dev Only callable by veCURLock contract
     * @param user User address
     */
    function executeLock(address user) public onlyVeLock nonReentrant whenNotPaused {
        _updateReward(user);
        _flushIdleRewards();
        //更新用户权重
        _updateWeight(user);

        //发送时间
        emit LockExecuted(user);
    }

    /**
     * @notice Executes unlock - updates user weight after unlock
     * @dev Only callable by veCURLock contract
     * @param user User address
     */
    function executeUnlock(address user) public onlyVeLock nonReentrant {
        //结算历史奖励
        _updateReward(user);
        _flushIdleRewards();
        //更新用户权重
        _updateWeight(user);
        //发送时间
        emit UnlockExecuted(user);
    }

    /**
     * @notice Executes early unlock - applies penalty and updates weight
     * @dev Only callable by veCURLock contract
     * @param user User address
     * @param penalty Penalty amount to burn
     */
    function executeEarlyUnlock(address user, uint256 penalty) public onlyVeLock nonReentrant {
        //结算历史奖励
        _updateReward(user);
        _flushIdleRewards();

        UserInfo storage userInfo = users[user];
        uint256 oldWeight = userInfo.weight;

        uint256 curAmount = 0;
        if (penalty > 0) {
            if (userInfo.amount < penalty) revert InsufficientAmount();
            userInfo.amount -= penalty;
            curAmount = sCURToken.burnGaugePenalty(penalty);
        }

        _updateWeight(user);

        uint256 pendingReward = userInfo.pendingRewards;
        if (pendingReward > 0) {
            userInfo.pendingRewards = 0;
        }

        if (curAmount > 0) {
            curStake.executePenalty(user, curAmount);
        }

        if (pendingReward > 0) {
            curToken.safeTransfer(address(revenueRebatePool), pendingReward);
            emit RewardsConfiscated(user, pendingReward);
        }

        //发送事件
        emit EarlyUnlockExecuted(user, penalty, oldWeight, userInfo.weight);
    }

    // ============================================
    // Emergency Functions
    // ============================================

    /**
     * @notice Emergency withdrawal (only available when paused)
     * @dev User forfeits all pending rewards, only receives sCUR
     * @param user User address to withdraw for
     */
    function gaugeEmergencyWithdraw(address user) public onlyCurStake nonReentrant {
        UserInfo storage userInfo = users[user];
        uint256 amount = userInfo.amount;

        if (amount == 0) revert NoAssets();

        totalWeight -= userInfo.weight;

        userInfo.amount = 0;
        userInfo.weight = 0;
        userInfo.pendingRewards = 0;
        userInfo.rewardPerTokenPaid = 0;

        IERC20(address(sCURToken)).safeTransfer(user, amount);

        emit EmergencyWithdrawn(user, amount);
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

    /**
     * @notice Gets the amount of sCUR a user has deposited in the gauge
     * @param user User address
     * @return Amount of sCUR deposited
     */
    function getUserAmount(address user) public view returns (uint256) {
        return users[user].amount;
    }

    /**
     * @notice Updates the CURStaking contract address
     * @dev Reverts if the address is zero, self-referential, or unchanged.
     * @param _curStake The new CURStaking contract address
     */
    function setCurStake(address _curStake) external onlyOwner {
        if (_curStake == address(0)) revert ZeroAddress();
        if (_curStake == address(this)) revert InvalidAddress();
        if (_curStake == address(curStake)) revert SameAddress();

        address oldStake = address(curStake);
        curStake = ICURStaking(_curStake);

        emit CurStakeUpdated(oldStake, _curStake);
    }

    /**
     * @notice Updates the veCURLock contract address
     * @dev Reverts if the address is zero, self-referential, or unchanged.
     * @param _veLock The new veCURLock contract address
     */
    function setVeLock(address _veLock) external onlyOwner {
        if (_veLock == address(0)) revert ZeroAddress();
        if (_veLock == address(this)) revert InvalidAddress();
        if (_veLock == address(veLock)) revert SameAddress();

        address oldVeLock = address(veLock);
        veLock = IveCURLock(_veLock);
        emit VeLockUpdated(oldVeLock, _veLock);
    }

    /**
     * @notice Updates the RevenueRebatePool contract address
     * @dev Reverts if the address is zero, self-referential, or unchanged.
     * @param _revenueRebatePool The new RevenueRebatePool contract address
     */
    function setRevenueRebatePool(address _revenueRebatePool) external onlyOwner {
        if (_revenueRebatePool == address(0)) revert ZeroAddress();
        if (_revenueRebatePool == address(this)) revert InvalidAddress();
        if (_revenueRebatePool == address(revenueRebatePool)) revert SameAddress();

        address oldPool = address(revenueRebatePool);
        revenueRebatePool = IRevenueRebatePool(_revenueRebatePool);
        emit RevenuePoolUpdated(oldPool, _revenueRebatePool);
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
