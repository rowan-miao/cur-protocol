// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IsCUR.sol";
import "../interfaces/ICURStaking.sol";
import "../interfaces/INFTChecker.sol";
import "../interfaces/IIncentiveGauge.sol";


/**
 * @title veCURLock - Lock Bonus Manager
 * @author CUR Protocol Team
 * @notice Manages lock commitments and provides bonus multipliers for stakers
 * @dev Non-custodial: only records lock commitments, does not hold sCUR assets
 * 
 * Features:
 * - Lock sCUR for 30-730 days to get bonus multipliers
 * - Different lock durations give different bonus factors
 * - Early unlock triggers penalty calculation
 * - NFT integration for unlocking higher lock tiers
 */
contract veCURLock is Pausable, Ownable, ReentrancyGuard {
    IsCUR public immutable sCURToken;
    ICURStaking public curStake;
    INFTChecker public nftChecker;
    IIncentiveGauge public incentiveGauge;

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
    uint256 public constant BONUS_365 = 2.00e18;
    uint256 public constant BONUS_730 = 2.50e18;

  
    uint256 public constant MIN_LOCK_DURATION = 30 days;
    uint256 public constant MAX_LOCK_DURATION = 730 days;
    uint256 public constant MIN_BONUS_FACTOR = 1e18;
    uint256 public constant MAX_BONUS_FACTOR = 250 * PRECISION; 
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

    /**
     * @title NFTBinding
     * @notice NFT binding information for lock permission
     */
    struct NFTBinding {
        address nftContract;
        uint256 tokenId;
        uint8 tier;
        bool isBound;
    }

    // ============================================
    // State Variables
    // ============================================
    mapping(address => LockInfo) public locks;
    mapping(address => NFTBinding) public nftBindings;
    mapping(address => mapping(uint256 => bool)) public isNFTBound;
    
    // ============================================
    // Events
    // ============================================
    
    /// @notice Emitted when a user locks their sCUR
    event Locked(address indexed user, uint256 duration, uint256 bonusFactor, uint256 endTime);
    /// @notice Emitted when a user unlocks after lock expires
    event Unlocked(address indexed user, uint256 amount);
    /// @notice Emitted when a user unlocks early with penalty
    event EarlyUnlocked(address indexed user, uint256 amount, uint256 penalty);
    /// @notice Emitted when NFT is bound to lock
    event NFTBound(address indexed user, address indexed nftContract, uint256 tokenId, uint8 tier);
    /// @notice Emitted when NFT is unbound
    event NFTUnbound(address indexed user, address indexed nftContract, uint256 tokenId, uint8 tier);
    /// @notice Emitted when NFTChecker address is updated
    event NFTCheckerUpdated(address indexed newChecker);
    /// @notice Emitted when IncentiveGauge address is updated
    event IncentiveGaugeUpdated(address indexed newGauge);

   
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


    // ============================================
    // Constructor
    // ============================================
    
    /**
     * @notice Initializes the veCURLock contract
     * @param _sCURToken Address of the sCUR token
     * @param _curStake Address of the CURStaking contract
     * @param _nftChecker Address of the NFTChecker contract
     * @param _incentiveGauge Address of the IncentiveGauge contract
     */
    constructor(address _sCURToken, address _curStake, address _nftChecker, address _incentiveGauge) Ownable(msg.sender) {
        if (_sCURToken == address(0)) revert ZeroAddress();
        if (_curStake == address(0)) revert ZeroAddress();
        if (_nftChecker == address(0)) revert ZeroAddress();
        if (_incentiveGauge == address(0)) revert ZeroAddress();

        sCURToken = IsCUR(_sCURToken);
        curStake = ICURStaking(_curStake);
        nftChecker = INFTChecker(_nftChecker);
        incentiveGauge = IIncentiveGauge(_incentiveGauge);

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
    function isValidDuration(uint256 duration) public pure returns(bool){
        return duration == DURATION_30 ||
               duration == DURATION_90 ||
               duration == DURATION_180 ||
               duration == DURATION_365 ||
               duration == DURATION_730;
    }

    /**
     * @notice Gets bonus multiplier for a given duration
     * @param duration Lock duration in seconds
     * @return Bonus multiplier (1e18 = 1.0x)
     */
    function getBonusByDuration(uint256 duration) public pure returns(uint256){
        if(duration == DURATION_30) return BONUS_30;
        if(duration == DURATION_90) return BONUS_90;
        if(duration == DURATION_180) return BONUS_180;
        if(duration == DURATION_365) return BONUS_365;
        if(duration == DURATION_730) return BONUS_730;
        revert InvalidDuration();
    }

    /**
     * @notice Gets maximum allowed lock duration for a user (based on NFT)
     * @param user User address
     * @return maxLockDuration Maximum lock duration in seconds
     */
    function getMaxLockDuration(address user) public view returns(uint256 maxLockDuration) {
        NFTBinding memory binding = nftBindings[user];
        if(!binding.isBound){
            return DURATION_180;
        }

        if(binding.tier == 2){
            return DURATION_730;
        }

        return DURATION_365;

    }

    // ============================================
    // Core Functions
    // ============================================
    
    /**
     * @notice Locks sCUR tokens for a specified duration
     * @dev Locks the user's gauged sCUR amount
     * @param duration Lock duration (must be one of the predefined options)
     */

    function lock(uint256 duration) public nonReentrant whenNotPaused{
        //检查duration否在
        if(!isValidDuration(duration)) revert InvalidDuration();
        //查看权限
        if(duration > getMaxLockDuration(msg.sender)) revert DurationExceedsPermission();
        //查看用户是否锁仓
        if(locks[msg.sender].isLocked) revert AlreadyLocked();
        //获得用户在矿池中质押的scur数量
        (, uint256 depositedGauge) = curStake.getUserInfo(msg.sender);
        if(depositedGauge == 0) revert ZeroSCUR();
        //获得bonus系数
        uint256 bonus = getBonusByDuration(duration);
        //更新锁仓变量
        locks[msg.sender] = LockInfo({
            amount : depositedGauge,
            startTime : block.timestamp,
            endTime : block.timestamp + duration,
            duration : duration,
            bonusFactor : bonus,
            isLocked : true
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
    function unlock() public nonReentrant whenNotPaused {
        LockInfo storage lockInfo = locks[msg.sender];
        //检查用户是否锁仓
        if(!lockInfo.isLocked) revert NotLocked();
        //检查锁仓是否到期
        if(block.timestamp < lockInfo.endTime) revert NotExpired();
        //更新合约状态
        locks[msg.sender].isLocked = false;
        totalLocked -= lockInfo.amount;

        _releaseNFTBinding(msg.sender);
        //通知incentiveGauge更改权重
        incentiveGauge.executeUnlock(msg.sender);
        //发送事件
        emit Unlocked(msg.sender, lockInfo.amount);

    }


    /**
     * @notice Early unlock with penalty
     * @dev Calculates penalty and notifies IncentiveGauge
     */
    function earlyUnlock() public nonReentrant whenNotPaused {
        //获得用户锁仓信息
        LockInfo storage lockInfo = locks[msg.sender];
        ///查看用户是否锁仓
        if(!lockInfo.isLocked) revert NotLocked();
        //检查锁仓是否到期
        if(block.timestamp >= lockInfo.endTime) revert AlreadyExpired();
        //计算罚金
        uint256 penaltyAmount = _calculatePenalty(lockInfo.amount, lockInfo.startTime, lockInfo.endTime);
        //更新锁仓变量
        locks[msg.sender].isLocked = false;
        //更新totalLocked
        totalLocked -= lockInfo.amount;

        //释放NFT
        _releaseNFTBinding(msg.sender);
        //通知incentiveGauge更改权重
        incentiveGauge.executeEarlyUnlock(msg.sender, penaltyAmount);
        //发送事件
        emit EarlyUnlocked(msg.sender, lockInfo.amount, penaltyAmount);
    }

    /**
     * @notice Calculates early unlock penalty
     * @dev Penalty = amount × 50% × (remaining time / total time)
     * @param amount Locked sCUR amount
     * @param startTime Lock start timestamp
     * @param endTime Lock end timestamp
     * @return penalty Amount to be penalized (burned)
     */
    function _calculatePenalty(uint256 amount, uint256 startTime, uint256 endTime) internal view returns(uint256 penalty){
        if(block.timestamp >= endTime) return 0;

        uint256 remaining = endTime - block.timestamp; 
        uint256 totalTime = endTime - startTime;

        uint256 penaltyBasis = (remaining * PENALTY_RATE) / totalTime;
        penalty = (amount * penaltyBasis) / 10000;

        return penalty;

    }

   
   

    // ============================================
    // NFT Binding Functions
    // ============================================
    
    /**
     * @notice Binds an NFT to the user's account for lock permission
     * @param nftContract NFT contract address
     * @param tokenId NFT token ID
     */
    function bindNFT(address nftContract, uint256 tokenId) public nonReentrant whenNotPaused{
        //检查用户是否持有Nft
        if(!nftChecker.verifyOwnership(msg.sender, nftContract, tokenId)) revert NotNFTOwner();
        //检查nft是否被绑定
        if(isNFTBound[nftContract][tokenId]) revert AlreadyBound();
        uint256 tier = nftChecker.getNFTTier(nftContract);
        //更新NFT变量
        nftBindings[msg.sender] = NFTBinding({
            nftContract : nftContract,
            tokenId : tokenId,
            tier : uint8(tier),
            isBound : true 
        });
        //绑定Nft
        isNFTBound[nftContract][tokenId] = true;

        emit NFTBound(msg.sender, nftContract, tokenId, uint8(tier));

    }

   /**
    * @notice Unbinds the NFT lock permission from the caller.
    * @dev Clears the NFT binding record without transferring NFT ownership.
    */
    function unbindNFT() public nonReentrant whenNotPaused{
        NFTBinding memory binding = nftBindings[msg.sender];

        //检查用户是否绑定NFT
        if(!binding.isBound) revert NotBound();

        //更新NFT变量
        isNFTBound[binding.nftContract][binding.tokenId] = false;
        delete nftBindings[msg.sender];

        emit NFTUnbound(msg.sender, binding.nftContract, binding.tokenId, binding.tier);


    } 

    /**
     * @notice Internal function to release NFT binding
     * @param user User address to release NFT for
     */
    function _releaseNFTBinding(address user) internal {
        NFTBinding memory binding = nftBindings[user];
        if(binding.isBound){
            isNFTBound[binding.nftContract][binding.tokenId] = false;
            delete nftBindings[user];
        }

    }

    // ============================================
    // View Functions
    // ============================================
    
    /**
     * @notice Calculates penalty for a user's lock
     * @param user User address
     * @return Penalty amount
     */
    function calculatePenalty(address user) public view returns(uint256){
        LockInfo memory lockInfo = locks[user];
        if(!lockInfo.isLocked) return 0;
        if(block.timestamp >= lockInfo.endTime) return 0;
        return  _calculatePenalty(lockInfo.amount, lockInfo.startTime, lockInfo.endTime);
    
    }

    /**
     * @notice Gets remaining lock time for a user
     * @param user User address
     * @return Remaining time in seconds
     */
    function getRemainingTime(address user) public view returns(uint256){
        LockInfo memory lockInfo = locks[user];
        //检查用户是否lock
        if(!lockInfo.isLocked) return 0;
        if(block.timestamp > lockInfo.endTime) return 0;

        return lockInfo.endTime - block.timestamp;
    }

    /**
     * @notice Gets user's current bonus multiplier
     * @param user User address
     * @return Bonus multiplier (1e18 = 1.0x)
     */
    function getBonus(address user) public view returns(uint256) {
        LockInfo memory lockInfo = locks[user];
        if(!lockInfo.isLocked) return PRECISION;
        if(block.timestamp >= lockInfo.endTime) return PRECISION;
        return lockInfo.bonusFactor;

    }

    // ============================================
    // Admin Functions
    // ============================================
    
    /**
     * @notice Updates NFTChecker contract address
     * @param _nftChecker New NFTChecker address
     */
    function setNFTChecker(address _nftChecker) public onlyOwner {
        if (_nftChecker == address(0)) revert ZeroAddress();
        nftChecker = INFTChecker(_nftChecker);
        emit NFTCheckerUpdated(_nftChecker);
    }

    /**
     * @notice Updates IncentiveGauge contract address
     * @param _incentiveGauge New IncentiveGauge address
     */
    function setIncentiveGauge(address _incentiveGauge) public onlyOwner {
        if (_incentiveGauge == address(0)) revert ZeroAddress();
        incentiveGauge = IIncentiveGauge(_incentiveGauge);
        emit IncentiveGaugeUpdated(_incentiveGauge);
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
