// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IsCUR.sol";
import "../interfaces/INFTChecker.sol";
import "../interfaces/IIncentiveGauge.sol";
import "../interfaces/ICURStaking.sol";

/**
 * @title veCURLock - Lock Bonus Manager
 * @author CUR Protocol Team
 * @notice Manages lock commitments and provides bonus multipliers for stakers
 * @dev Non-custodial: only records lock commitments, does not hold sCUR assets
 *      (sCUR is held by IncentiveGauge, not by this contract)
 *
 * Features:
 * - Lock sCUR for 30-730 days to get bonus multipliers (1.15x - 2.50x)
 * - Different lock durations give different bonus factors
 * - Early unlock triggers penalty calculation (up to 50% of locked amount)
 * - NFT integration for higher lock tiers (via NFTChecker)
 * - Notifies IncentiveGauge on lock/unlock to update user weight
 * - Lock-aware NFT unbinding: NFTChecker prevents unbinding while locked
 */
contract veCURLock is Pausable, Ownable, ReentrancyGuard {
    IsCUR public immutable sCURToken;
    INFTChecker public immutable nftChecker;
    IIncentiveGauge public incentiveGauge;
    ICURStaking public curStaking;

    // ============================================
    // Constants
    // ============================================

    uint256 public constant PRECISION = 1e18;

    uint256 public constant DURATION_30 = 30 days;
    uint256 public constant DURATION_90 = 90 days;
    uint256 public constant DURATION_180 = 180 days;
    uint256 public constant DURATION_365 = 365 days;
    uint256 public constant DURATION_730 = 730 days;

    uint256 public constant BONUS_30 = 1.15e18;
    uint256 public constant BONUS_90 = 1.35e18;
    uint256 public constant BONUS_180 = 1.65e18;
    uint256 public constant BONUS_365 = 2.0e18;
    uint256 public constant BONUS_730 = 2.5e18;

    uint256 public constant PENALTY_RATE = 5000;

    uint256 public totalLocked;

    // ============================================
    // Structs
    // ============================================

    /**
     * @title LockInfo
     * @notice User lock commitment information
     */
    struct LockInfo {
        uint256 amount;
        uint256 startTime;
        uint256 endTime;
        uint256 duration;
        uint256 bonusFactor;
        bool isLocked;
    }

    // ============================================
    // State Variables
    // ============================================
    mapping(address => LockInfo) public locks;

    // ============================================
    // Events
    // ============================================

    /// @notice Emitted when a user locks their sCUR
    event Locked(address indexed user, uint256 duration, uint256 bonusFactor, uint256 endTime);
    /// @notice Emitted when a user unlocks after lock expires
    event Unlocked(address indexed user, uint256 amount);
    /// @notice Emitted when a user unlocks early with penalty
    event EarlyUnlocked(address indexed user, uint256 amount, uint256 penalty);
    /// @notice Emitted when IncentiveGauge address is updated
    event IncentiveGaugeUpdated(address indexed oldAddress, address indexed newAddress);
    /// @notice Emitted when the CURStaking contract address is updated
    event CurStakingUpdated(address indexed oldAddress, address indexed newAddress);
    /// @notice Emitted when a user's lock is forcibly broken during emergency withdrawal
    event EmergencyUnlocked(address indexed user, uint256 amount);

    // ============================================
    // Errors
    // ============================================

    /// @notice Thrown when user has no sCUR in gauge
    error ZeroSCUR();
    /// @notice Thrown when zero address is provided
    error ZeroAddress();
    /// @notice Thrown when lock duration is invalid
    error InvalidDuration();
    /// @notice Thrown when user already has an active lock
    error AlreadyLocked();
    /// @notice Thrown when user has no active lock
    error NotLocked();
    /// @notice Thrown when lock has already expired
    error AlreadyExpired();
    /// @notice Thrown when lock has not expired yet
    error NotExpired();
    /// @notice Thrown when lock duration exceeds NFT permission
    error DurationExceedsPermission();
    /// @notice Thrown when user does not own the NFT
    error NotNFTOwner();
    /// @notice Thrown when user has no bound NFT
    error NotBound();
    /// @notice Thrown when NFT is already bound by another user
    error AlreadyBound();
    /// @notice Thrown when the caller is not authorized to execute the function
    error Unauthorized();
    /// @notice Thrown when an address parameter is invalid
    error InvalidAddress();
    /// @notice Thrown when the new address is identical to the existing one
    error SameAddress();

    // ============================================
    // Modifiers
    // ============================================

    /**
     * @notice Restricts function access to the CURStaking contract only
     * @dev Reverts with Unauthorized if the caller is not the configured curStaking address
     */
    modifier onlyCurStaking() {
        if (msg.sender != address(curStaking)) revert Unauthorized();
        _;
    }

    // ============================================
    // Constructor
    // ============================================

    /**
     * @notice Initializes the veCURLock contract
     * @param _sCURToken Address of the sCUR token
     * @param _nftChecker Address of the NFTChecker contract
     * @param _incentiveGauge Address of the IncentiveGauge contract
     */
    constructor(address _sCURToken, address _nftChecker, address _incentiveGauge) Ownable(msg.sender) {
        if (_sCURToken == address(0)) revert ZeroAddress();
        if (_nftChecker == address(0)) revert ZeroAddress();

        sCURToken = IsCUR(_sCURToken);
        nftChecker = INFTChecker(_nftChecker);

        if (_incentiveGauge != address(0)) incentiveGauge = IIncentiveGauge(_incentiveGauge);

        totalLocked = 0;
    }

    // ============================================
    // Duration & Bonus Helpers
    // ============================================

    /**
     * @notice Checks if a lock duration is valid
     * @param duration Lock duration in seconds
     * @return True if duration is one of the predefined options
     */
    function isValidDuration(uint256 duration) public pure returns (bool) {
        return duration == DURATION_30 || duration == DURATION_90 || duration == DURATION_180
            || duration == DURATION_365 || duration == DURATION_730;
    }

    /**
     * @notice Gets bonus multiplier for a given duration
     * @param duration Lock duration in seconds
     * @return Bonus multiplier (1e18 = 1.0x)
     */
    function getBonusByDuration(uint256 duration) public pure returns (uint256) {
        if (duration == DURATION_30) return BONUS_30;
        if (duration == DURATION_90) return BONUS_90;
        if (duration == DURATION_180) return BONUS_180;
        if (duration == DURATION_365) return BONUS_365;
        if (duration == DURATION_730) return BONUS_730;
        revert InvalidDuration();
    }

    /**
     * @notice Gets maximum allowed lock duration for a user (based on NFT)
     * @param user User address
     * @return maxLockDuration Maximum lock duration in seconds
     */
    function getMaxLockDuration(address user) public view returns (uint256 maxLockDuration) {
        if (!nftChecker.isUserBound(user)) {
            return DURATION_180;
        }

        uint8 tier = nftChecker.getUserTier(user);

        if (tier == nftChecker.TIER_MID()) {
            return DURATION_365;
        }

        if (tier == nftChecker.TIER_HIGH()) {
            return DURATION_730;
        }

        return DURATION_180;
    }

    // ============================================
    // Core Functions
    // ============================================

    /**
     * @notice Locks sCUR tokens for a specified duration
     * @dev Locks the user's gauged sCUR amount
     * @param duration Lock duration (must be one of the predefined options)
     */

    function lock(uint256 duration) public nonReentrant whenNotPaused {
        //检查duration否在
        if (!isValidDuration(duration)) revert InvalidDuration();
        //查看权限
        if (duration > getMaxLockDuration(msg.sender)) revert DurationExceedsPermission();
        //查看用户是否锁仓
        if (locks[msg.sender].isLocked) revert AlreadyLocked();
        //获得用户在矿池中质押的scur数量
        uint256 depositedGauge = incentiveGauge.getUserAmount(msg.sender);
        if (depositedGauge == 0) revert ZeroSCUR();
        //获得bonus系数
        uint256 bonus = getBonusByDuration(duration);
        //更新锁仓变量
        locks[msg.sender] = LockInfo({
            amount: depositedGauge,
            startTime: block.timestamp,
            endTime: block.timestamp + duration,
            duration: duration,
            bonusFactor: bonus,
            isLocked: true
        });

        totalLocked += depositedGauge;

        //通知incentiveGauge更改权重
        incentiveGauge.executeLock(msg.sender);
        //发送事件
        emit Locked(msg.sender, duration, bonus, block.timestamp + duration);
    }

    /**
     * @notice Unlocks sCUR after lock period expires
     * @dev No penalty, called when lock has expired
     */
    function unlock() public nonReentrant {
        LockInfo storage lockInfo = locks[msg.sender];
        //检查用户是否锁仓
        if (!lockInfo.isLocked) revert NotLocked();
        //检查锁仓是否到期
        if (block.timestamp < lockInfo.endTime) revert NotExpired();
        uint256 amount = lockInfo.amount;
        //更新合约状态
        lockInfo.isLocked = false;
        totalLocked -= amount;

        //通知incentiveGauge更改权重
        incentiveGauge.executeUnlock(msg.sender);
        //发送事件
        emit Unlocked(msg.sender, amount);
    }

    /**
     * @notice Early unlock with penalty
     * @dev Calculates penalty and notifies IncentiveGauge
     */
    function earlyUnlock() public nonReentrant {
        //获得用户锁仓信息
        LockInfo storage lockInfo = locks[msg.sender];
        ///查看用户是否锁仓
        if (!lockInfo.isLocked) revert NotLocked();
        //检查锁仓是否到期
        if (block.timestamp >= lockInfo.endTime) revert AlreadyExpired();
        //计算罚金
        uint256 penaltyAmount = calculatePenalty(msg.sender);
        //更新锁仓变量
        lockInfo.isLocked = false;
        //更新totalLocked
        totalLocked -= lockInfo.amount;
        // 解除 NFT 绑定
        if (nftChecker.isUserBound(msg.sender)) {
            nftChecker.unbindNFTFor(msg.sender);
        }

        //通知incentiveGauge更改权重
        incentiveGauge.executeEarlyUnlock(msg.sender, penaltyAmount);
        //发送事件
        emit EarlyUnlocked(msg.sender, lockInfo.amount, penaltyAmount);
    }

    /**
     * @notice Calculates penalty for a user's lock
     * @param user User address
     * @return penalty Penalty amount
     */
    function calculatePenalty(address user) public view returns (uint256 penalty) {
        LockInfo memory lockInfo = locks[user];
        if (!lockInfo.isLocked) return 0;
        if (block.timestamp >= lockInfo.endTime) return 0;

        uint256 remaining = lockInfo.endTime - block.timestamp;
        uint256 totalTime = lockInfo.endTime - lockInfo.startTime;

        penalty = (lockInfo.amount * PENALTY_RATE * remaining) / totalTime / 10_000;

        return penalty;
    }

    /**
     * @notice Forcibly breaks a user's lock during emergency withdrawal
     * @dev Only callable by CURStaking. Clears all lock state to prevent ghost data.
     *      If the lock has not expired, the corresponding early unlock penalty is calculated and returned.
     *      The penalty amount is NOT deducted here; it is returned for the caller (CURStaking) to handle.
     * @param user The address of the user whose lock should be broken
     * @return penalty The sCUR penalty amount to be deducted (0 if not locked or already expired)
     */
    function emergencyBreakLock(address user) public onlyCurStaking returns (uint256 penalty) {
        LockInfo storage lockInfo = locks[user];
        if (!lockInfo.isLocked) return 0;

        uint256 amount = lockInfo.amount;

        penalty = calculatePenalty(user);

        lockInfo.isLocked = false;
        totalLocked -= amount;

        emit EmergencyUnlocked(user, amount);
        return penalty;
    }

    // ============================================
    // View Functions
    // ============================================
    /**
     * @notice Gets remaining lock time for a user
     * @param user User address
     * @return Remaining time in seconds
     */
    function getRemainingTime(address user) public view returns (uint256) {
        LockInfo memory lockInfo = locks[user];
        //检查用户是否lock
        if (!lockInfo.isLocked) return 0;
        if (block.timestamp > lockInfo.endTime) return 0;

        return lockInfo.endTime - block.timestamp;
    }

    /**
     * @notice Gets user's current bonus multiplier
     * @param user User address
     * @return Bonus multiplier (1e18 = 1.0x)
     */
    function getBonus(address user) public view returns (uint256) {
        LockInfo memory lockInfo = locks[user];
        if (!lockInfo.isLocked) return PRECISION;
        if (block.timestamp >= lockInfo.endTime) return PRECISION;
        return lockInfo.bonusFactor;
    }

    /**
     * @notice Checks if a user has an active lock
     * @param user User address
     * @return True if user has an active lock
     */
    function isLocked(address user) public view returns (bool) {
        LockInfo memory lockInfo = locks[user];
        return lockInfo.isLocked && (block.timestamp < lockInfo.endTime);
    }

    // ============================================
    // Admin Functions
    // ============================================

    /**
     * @notice Updates IncentiveGauge contract address
     * @param _incentiveGauge New IncentiveGauge address
     */
    function setIncentiveGauge(address _incentiveGauge) external onlyOwner {
        if (_incentiveGauge == address(0)) revert ZeroAddress();
        if (_incentiveGauge == address(this)) revert InvalidAddress();
        if (_incentiveGauge == address(incentiveGauge)) revert SameAddress();

        address oldGauge = address(incentiveGauge);
        incentiveGauge = IIncentiveGauge(_incentiveGauge);

        emit IncentiveGaugeUpdated(oldGauge, _incentiveGauge);
    }

    /**
     * @notice Updates CURStaking contract address
     * @param _curStaking New CURStaking address
     */
    function setCurStaking(address _curStaking) external onlyOwner {
        if (_curStaking == address(0)) revert ZeroAddress();
        if (_curStaking == address(this)) revert InvalidAddress();
        if (_curStaking == address(curStaking)) revert SameAddress();

        address oldStaking = address(curStaking);
        curStaking = ICURStaking(_curStaking);

        emit CurStakingUpdated(oldStaking, _curStaking);
    }

    // ============================================
    // Pause Functions
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
