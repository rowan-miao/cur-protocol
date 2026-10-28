// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
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
    using SafeERC20 for IERC20;
    IERC20 public immutable curToken;
    IsCUR public immutable sCURToken;
    IIncentiveGauge public gauge;
    IveCURLock public veLock;
    IRevenueRebatePool public revenueRebatePool;

    uint256 public constant PRECISION = 1e18;

    uint256 public constant MIN_STAKE_CUR = 1e12;

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
    event EmergencyWithdrawn(address indexed user, uint256 totalSCUR, uint256 actualSCURRedeemed);

    /// @notice Emitted when a penalty is executed on early unlock
    event PenaltyExecuted(address indexed user, uint256 CURAmount);

    /// @notice Emitted when IncentiveGauge address is updated
    event GaugeUpdated(address indexed oldAddress, address indexed newAddress);

    /// @notice Emitted when veCURLock address is updated
    event VeLockUpdated(address indexed oldAddress, address indexed newAddress);

    /// @notice Emitted when RevenueRebatePool address is updated
    event RevenueRebatePoolUpdated(address indexed oldAddress, address indexed newAddress);

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

    /// @notice Thrown when the contract has insufficient balance
    error InsufficientBalance();

    /// @notice Thrown when the user has no assets to withdraw
    error NoAssets();

    /// @notice Thrown when the caller is not authorized
    error Unauthorized();

    /// @notice Thrown when user has an active lock and cannot perform operation
    error PositionLocked();

    /// @notice Thrown when stake amount is below minimum
    error BelowMinimumStake(uint256 minimumStake);

    /// @notice Thrown when stake amount results in zero sCUR minted
    error ZeroSCURMinted();

    /// @notice Thrown when unstake amount results in zero CUR redeemed
    error ZeroCURRedeemed();

    /// @notice Thrown when an invalid address is provided
    error InvalidAddress(); 

    /// @notice Thrown when the new address is identical to the current one
    error SameAddress();

    /// @notice Thrown when veLock address has not been configured yet
    error VeLockNotConfigured();

    /// @notice Thrown when gauge address has not been configured yet
    error GaugeNotConfigured();

    /// @notice Thrown when the system is not in a paused (emergency) state
    error SystemNotPaused();

    /// @notice Thrown when a required dependency address has not been configured
    error DependencyNotConfigured();

    // ============================================
    // modifiers
    // ============================================

    /**
     * @notice Restricts function access to the IncentiveGauge contract only
     * @dev Reverts with Unauthorized if caller is not the gauge address
     */
    modifier onlyGauge() {
        if (msg.sender != address(gauge)) revert Unauthorized();
        _;
    }
    
    /**
     * @notice Ensures the veLock contract address is configured before execution
     * @dev Reverts with VeLockNotConfigured if veLock has not been set (address(0))
     */
    modifier onlyVeLockConfigured() {
        if (address(veLock) == address(0)) revert VeLockNotConfigured();
        _;
    }

    /**
     * @notice Ensures the gauge contract address is configured before execution
     * @dev Reverts with GaugeNotConfigured if gauge has not been set (address(0))
     */
    modifier onlyGaugeConfigured() {
        if (address(gauge) == address(0)) revert GaugeNotConfigured();
        _;
    }

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
    constructor(address _curToken, address _sCURToken, address _gauge, address _veLock, address _revenueRebatePool)
        Ownable(msg.sender)
    {
        if (_curToken == address(0)) revert ZeroAddress();
        if (_sCURToken == address(0)) revert ZeroAddress();

        curToken = IERC20(_curToken);
        sCURToken = IsCUR(_sCURToken);

        if (_gauge != address(0)) gauge = IIncentiveGauge(_gauge);

        if (_veLock != address(0)) veLock = IveCURLock(_veLock);

        if (_revenueRebatePool != address(0)) revenueRebatePool = IRevenueRebatePool(_revenueRebatePool);
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
        if (CURAmount == 0) revert ZeroAmount();

        uint256 minimumStake = getMinimumStakeAmount();
        if (CURAmount < minimumStake) revert BelowMinimumStake(minimumStake);

        curToken.safeTransferFrom(msg.sender, address(this), CURAmount);
    
        uint256 sCURAmount = sCURToken.mint(msg.sender, CURAmount);
        if (sCURAmount == 0) revert ZeroSCURMinted();
 
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
    function unstake(uint256 sCURAmount) public nonReentrant onlyVeLockConfigured {
        if (sCURAmount == 0) revert ZeroAmount();

        if (veLock.isLocked(msg.sender)) revert PositionLocked();

        uint256 userBalance = sCURToken.balanceOf(msg.sender);
        if (userBalance < sCURAmount) revert InsufficientFreeSCUR();
       
        uint256 CURAmount = sCURToken.redeem(msg.sender, sCURAmount);
        if (CURAmount == 0) revert ZeroCURRedeemed();

        curToken.safeTransfer(msg.sender, CURAmount);
    
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
    function enterGauge(uint256 sCURAmount) public nonReentrant whenNotPaused onlyVeLockConfigured onlyGaugeConfigured {
        if (sCURAmount == 0) revert ZeroAmount();

        if (veLock.isLocked(msg.sender)) revert PositionLocked();

        uint256 userBalance = sCURToken.balanceOf(msg.sender);
        if (userBalance < sCURAmount) revert InsufficientAmount();

        IERC20(address(sCURToken)).safeTransferFrom(msg.sender, address(gauge), sCURAmount);

        gauge.deposit(msg.sender, sCURAmount);

        emit EnterGauge(msg.sender, sCURAmount);
    }

    /**
     * @notice Exits the gauge and withdraws sCUR tokens
     * @param sCURAmount Amount of sCUR to withdraw from gauge
     */
    function exitGauge(uint256 sCURAmount) public nonReentrant onlyVeLockConfigured onlyGaugeConfigured {
        if (sCURAmount == 0) revert ZeroAmount();

        if (veLock.isLocked(msg.sender)) revert PositionLocked();

        gauge.withdraw(msg.sender, sCURAmount);

        emit ExitGauge(msg.sender, sCURAmount);
    }

    /**
     * @notice Transfers the penalty CUR amount to the RevenueRebatePool after early unlock
     * @dev Called by IncentiveGauge after sCUR has already been burned via burnGaugePenalty.
     *      This function only handles the CUR transfer; sCUR burn and accounting are done in sCUR.
     * @param user User address (for event tracking)
     * @param curAmount Amount of CUR to transfer as penalty (calculated by burnGaugePenalty)
     */
    function executePenalty(address user, uint256 curAmount) external onlyGauge nonReentrant whenNotPaused {
        if (curAmount == 0) revert ZeroAmount();
        curToken.safeTransfer(address(revenueRebatePool), curAmount);

        emit PenaltyExecuted(user, curAmount);
    }

    /**
     * @notice Emergency withdrawal when any core component is paused
     * @dev Users forfeit all pending rewards. Only available when at least one core contract is paused.
     */
    function emergencyWithdraw() public nonReentrant {
        bool emergencyMode = paused();

        if (address(gauge) != address(0) && gauge.paused()) {
            emergencyMode = true;
        }

        if (address(veLock) != address(0) && veLock.paused()) {
            emergencyMode = true;
        }

        if (address(sCURToken) != address(0) && sCURToken.paused()) {
            emergencyMode = true;
        }

        if (!emergencyMode) revert SystemNotPaused();
          
        uint256 penalty = 0;
        if (address(sCURToken) == address(0)) {
            revert DependencyNotConfigured();
        }

        if(address(veLock) != address(0)){
            penalty = veLock.emergencyBreakLock(msg.sender);
        }
        
        if(address(gauge) != address(0)){
            uint256 gaugeAmount = gauge.getUserAmount(msg.sender);
            if (gaugeAmount > 0) {
                gauge.gaugeEmergencyWithdraw(msg.sender);
            }
        }
        
        uint256 totalSCUR = sCURToken.balanceOf(msg.sender);
        if (totalSCUR == 0) revert NoAssets();
        
        uint256 actualSCURToRedeem = totalSCUR;
        if(penalty > 0){
            if(penalty > totalSCUR) penalty = totalSCUR;
            actualSCURToRedeem = totalSCUR - penalty;
            uint256 penaltyCUR = sCURToken.emergencyRedeem(msg.sender, penalty);
            if(penaltyCUR > 0){
                curToken.safeTransfer(address(revenueRebatePool), penaltyCUR);
            }
        }
  
        if(actualSCURToRedeem > 0){
            uint256 CURAmount = sCURToken.emergencyRedeem(msg.sender, actualSCURToRedeem);
            if(CURAmount == 0) revert NoAssets();
            curToken.safeTransfer(msg.sender, CURAmount);
        }
       
        emit EmergencyWithdrawn(msg.sender, totalSCUR, actualSCURToRedeem);
    }

    // ============================================
    // View Functions
    // ============================================

    /**
     * @notice Returns the total amount of sCUR representing active staking positions.
     * @dev This value equals the total sCUR supply and represents staking principal,
     *      not the current underlying CUR value after exchange rate appreciation.
     * @return Total amount of sCUR representing staking principal.
     */
    function getTotalStaked() public view returns (uint256) {
        return sCURToken.totalSupply();
    }

    /**
     * @notice Calculates the minimum stake amount
     * @dev Returns max(fixed minimum, rounding minimum)
     *      - Fixed minimum: MIN_STAKE_CUR (economic floor)
     *      - Rounding minimum: ceil(exchangeRate / PRECISION)
     *        (ensures sCURAmount > 0)
     * @return Minimum stake amount in CUR
     */
    function getMinimumStakeAmount() public view returns (uint256) {
        uint256 rate = sCURToken.getExchangeRate();
        uint256 roundingMinimum = (rate + PRECISION - 1) / PRECISION;
        return roundingMinimum > MIN_STAKE_CUR ? roundingMinimum : MIN_STAKE_CUR;
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
     * @dev Only callable by the owner to update the protocol dependency
     * @param _gauge New IncentiveGauge contract address
     */
    function setGauge(address _gauge) external onlyOwner {
        if (_gauge == address(0)) revert ZeroAddress();
        if(_gauge == address(this)) revert InvalidAddress();
        if(_gauge == address(gauge)) revert SameAddress();

        address oldGauge = address(gauge);
        gauge = IIncentiveGauge(_gauge);

        emit GaugeUpdated(oldGauge, _gauge);
    }

    /**
     * @notice Updates the veCURLock contract address
     * @dev Only callable by the owner to update the protocol dependency
     * @param _veLock New veCURLock contract address
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
     * @dev Only callable by the owner to update the protocol dependency
     * @param _revenueRebatePool New RevenueRebatePool contract address
     */
    function setRevenueRebatePool(address _revenueRebatePool) external onlyOwner {
        if (_revenueRebatePool == address(0)) revert ZeroAddress();
        if(_revenueRebatePool == address(this)) revert InvalidAddress();
        if(_revenueRebatePool == address(revenueRebatePool)) revert SameAddress();

        address oldPool = address(revenueRebatePool);
        revenueRebatePool = IRevenueRebatePool(_revenueRebatePool);

        emit RevenueRebatePoolUpdated(oldPool, _revenueRebatePool);
    }
}
