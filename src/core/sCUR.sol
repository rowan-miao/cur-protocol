// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IIncentiveGauge.sol";

/**
 * @title sCUR - Staked CUR Token
 * @notice Share token representing a user's staked position in the CUR protocol
 * @dev This is an accounting-only token that does NOT hold or custody CUR assets
 * @dev Actual CUR assets are held in the CURStaking contract
 * @dev sCUR value increases over time as protocol revenue is injected into the system.
 * @dev 1 sCUR = exchangeRate / 1e18 CUR (exchangeRate only increases)
 * @dev Only authorized addresses (CURStaking, RevenueRebatePool) can call restricted functions
 * @dev CURStaking can call: mint() and redeem()
 * @dev RevenueRebatePool can call: updateExchangeRate()
 */
contract sCUR is ERC20, Pausable, Ownable, ReentrancyGuard {
    // ============================================
    // Immutable State
    // ============================================
    IERC20 public immutable CURToken;
    address public CUR_STAKING;
    IIncentiveGauge public incentiveGauge;

    // ============================================
    // Constants
    // ============================================
    uint256 public constant INITIAL_EXCHANGE_RATE = 1e18;
    uint256 public constant PRECISION = 1e18;

    // ============================================
    // State Variables
    // ============================================
    uint256 public currentExchangeRate;
    uint256 public totalUnderlying;

    mapping(address => bool) public minters;

    // ============================================
    // Events
    // ============================================

    /// @notice Emitted when sCUR is minted
    event Mint(address indexed to, uint256 CURAmount, uint256 sCURAmount);

    /// @notice Emitted when sCUR is redeemed
    event Redeem(address indexed from, uint256 CURAmount, uint256 sCURAmount);

    /// @notice Emitted when exchange rate is updated
    event UpdateExchangeRate(uint256 oldRate, uint256 newRate);

    /// @notice Emitted when a minter is added
    event MinterAdded(address indexed minter);

    /// @notice Emitted when a minter is removed
    event MinterRemoved(address indexed minter);

    /// @notice Emitted when IncentiveGauge address is updated
    event IncentiveGaugeUpdated(address indexed oldGauge, address indexed newGauge);
    
    /// @notice Emitted when CURStaking address is updated
    event CurStakingUpdated(address indexed newStaking);

    /// @notice Emitted when sCUR is burned from the gauge as an early-unlock penalty
    event PenaltyBurned(address indexed gauge, uint256 sCURBurned, uint256 curAmount);


    // ============================================
    // Errors
    // ============================================

    /// @notice Thrown when a zero address is provided
    error ZeroAddress();

    /// @notice Thrown when the provided amount is zero
    error ZeroAmount();

    /// @notice Thrown when user has insufficient sCUR balance
    error InsufficientSCURBalance();

    /// @notice Thrown when caller is not authorized
    error Unauthorized();

    /// @notice Thrown when exchange rate would decrease
    error ExchangeRateCannotDecrease();

    /// @notice Thrown when trying to remove CURStaking after set
    error CannotRemoveStaking();

    /// @notice Thrown when redeem amount exceeds totalUnderlying
    error InsufficientUnderlying();

    /// @notice Thrown when totalSupply is zero during exchange rate update
    error NoSupply();

    /// @notice Thrown when adding an address that is already a minter
    error AlreadyMinter();

    /// @notice Thrown when trying to set CURStaking after it has been set
    error StakingAlreadySet();

    // ============================================
    // Modifiers
    // ============================================

    /**
     * @notice Restricts function execution to authorized minters
     * @dev Only addresses added via addMinter() can call functions with this modifier
     */
    modifier onlyMinter() {
        if (!minters[msg.sender]) revert Unauthorized();
        _;
    }

    /**
     * @notice Restricts function access to the IncentiveGauge contract only
     * @dev Reverts with Unauthorized if caller is not IncentiveGauge
     */
    modifier onlyGauge() {
        if (msg.sender != address(incentiveGauge)) revert Unauthorized();
       _;
    }

    // ============================================
    // Constructor
    // ============================================

    /**
     * @notice Deploys the sCUR contract
     * @dev Sets token name to "Staked CUR", symbol to "sCUR"
     * @dev Initial exchange rate is 1:1 (1 sCUR = 1 CUR)
     * @param _curToken Address of the underlying CUR token
     */
    constructor(address _curToken, address _curStaking) ERC20("Staked CUR", "sCUR") Ownable(msg.sender) {
        if (_curToken == address(0)) revert ZeroAddress();
    
        CURToken = IERC20(_curToken);
        
        if (_curStaking != address(0)){
            CUR_STAKING = _curStaking;
            minters[_curStaking] = true;
            emit MinterAdded(_curStaking);
        }

        currentExchangeRate = INITIAL_EXCHANGE_RATE;
    }

   

    // ============================================
    // Minter Management
    // ============================================

    /**
     * @notice Adds a new authorized minter
     * @dev Only callable by contract owner
     * @param minter Address to add as minter
     */
    function addMinter(address minter) external onlyOwner {
        if (minter == address(0)) revert ZeroAddress();
        if (minters[minter]) revert AlreadyMinter();
        minters[minter] = true;
        emit MinterAdded(minter);
    }

    /**
     * @notice Removes an authorized minter
     * @dev Only callable by contract owner
     * @param minter Address to remove from minters
     */
    function removeMinter(address minter) external onlyOwner {
        if (minter == CUR_STAKING) revert CannotRemoveStaking();
        if (!minters[minter]) revert Unauthorized();

        delete minters[minter];
        emit MinterRemoved(minter);
    }

    // ============================================
    // Core Functions
    // ============================================

    /**
     * @notice Mint sCUR tokens when user stakes CUR
     * @dev Only callable by authorized minters (CURStaking)
     * @dev dev sCUR amount = CURAmount × PRECISION / currentExchangeRate
     * @param to Address receiving the newly minted sCUR
     * @param CURAmount Amount of CUR deposited and represented by the newly minted sCUR
     * @return sCURAmount Amount of sCUR minted
     */
    function mint(address to, uint256 CURAmount)
        public
        onlyMinter
        whenNotPaused
        nonReentrant
        returns (uint256 sCURAmount)
    {
        ///判断to是否是空地址
        ///判断 CURAmount 是否为零
        ///计算当前汇率 变更sCURAmount的数值
        ///铸造
        ///发送事件
        if (to == address(0)) revert ZeroAddress();
        if (CURAmount == 0) revert ZeroAmount();

        sCURAmount = (CURAmount * PRECISION) / currentExchangeRate;
        if (sCURAmount == 0) revert ZeroAmount();
        totalUnderlying += CURAmount;

        _mint(to, sCURAmount);

        emit Mint(to, CURAmount, sCURAmount);
        return sCURAmount;
    }
     

    /**
     * @notice Redeems sCUR tokens for CUR
     * @dev Burns sCUR from user and returns equivalent CUR
     * @dev Only callable by authorized minters (CURStaking)
     * @param from Address whose sCUR will be burned
     * @param sCURAmount Amount of sCUR to redeem
     * @return CURAmount Amount of CUR returned
     */
    function redeem(address from, uint256 sCURAmount) public onlyMinter whenNotPaused nonReentrant returns (uint256) {
        return _redeem(from, sCURAmount);
    }

    /**
     * @notice Internal logic for redeeming sCUR
     * @dev Burns sCUR and returns equivalent CUR
     * @param from Address whose sCUR will be burned
     * @param sCURAmount Amount of sCUR to redeem
     * @return CURAmount Amount of CUR returned
     */
    function _redeem(address from, uint256 sCURAmount) internal returns (uint256 CURAmount) {
        ///判断to是否为空地址
        ///判断sCURAmount是否为零
        ///判断用户是否有足够的 sCUR 余额
        ///计算当前汇率
        ///销毁
        ///发送赎回事件
        if (from == address(0)) revert ZeroAddress();
        if (sCURAmount == 0) revert ZeroAmount();

        uint256 balance = balanceOf(from);
        if (balance < sCURAmount) revert InsufficientSCURBalance();

        CURAmount = sCURAmount * currentExchangeRate / PRECISION;

        if (CURAmount > totalUnderlying) revert InsufficientUnderlying();
        
        totalUnderlying -= CURAmount;

        _burn(from, sCURAmount);

        emit Redeem(from, CURAmount, sCURAmount);
        return CURAmount;
    }

    /**
     * @notice Burns sCUR from gauge for penalty fees
     * @dev Only callable by IncentiveGauge
     * @dev Burns sCUR held in gauge and returns CUR amount
     * @param penalty Amount of sCUR to burn 
     * @return curAmount Equivalent CUR amount represented by the burned sCUR
     */
    function burnGaugePenalty(uint256 penalty) external onlyGauge whenNotPaused returns (uint256 curAmount) {
        if (penalty == 0) revert ZeroAmount();

        curAmount = (penalty * currentExchangeRate) / PRECISION;
        
        if (curAmount > totalUnderlying) revert InsufficientUnderlying();
        totalUnderlying -= curAmount;

        _burn(msg.sender, penalty);

        emit PenaltyBurned(msg.sender, penalty, curAmount);
        return curAmount;
    }

    /**
     * @notice Update exchange rate when protocol revenue is injected
     * @dev Only callable by authorized minters (RevenueRebatePool)
     * @dev newRate = (totalUnderlying + additionalCUR) × PRECISION / totalSupply()
     * @param additionalCUR Amount of CUR added to the pool
     * @return newRate The updated exchange rate
     */
    function updateExchangeRate(uint256 additionalCUR) public onlyMinter returns (uint256 newRate) {
        if (additionalCUR == 0) revert ZeroAmount();
        
        uint256 currentTotalSupply = totalSupply();
        if (currentTotalSupply == 0) revert NoSupply();

        uint256 oldRate = currentExchangeRate;
        totalUnderlying += additionalCUR;

        newRate = totalUnderlying * PRECISION / currentTotalSupply;
        if (newRate < oldRate) revert ExchangeRateCannotDecrease();

        currentExchangeRate = newRate;

        emit UpdateExchangeRate(oldRate, newRate);
        return newRate;
    }

    /**
     * @notice Emergency redeem when contract is paused
     * @dev Only callable by authorized minters (CURStaking for emergency withdrawal)
     * @param from Address whose sCUR will be burned
     * @param sCURAmount Amount of sCUR to redeem
     * @return CURAmount Amount of CUR returned
     */
    function emergencyRedeem(address from, uint256 sCURAmount) public onlyMinter nonReentrant returns (uint256) {
        return _redeem(from, sCURAmount);
    }
   
    // ============================================
    // View Functions
    // ============================================

    /**
     * @notice Get the current exchange rate
     * @return Current exchange rate (1 sCUR = rate / 1e18 CUR)
     */
    function getExchangeRate() public view returns (uint256) {
        return currentExchangeRate;
    }

    /**
     * @notice Updates the IncentiveGauge contract address
     * @dev Only callable by contract owner
     * @param _incentiveGauge New IncentiveGauge contract address
     */
    function setIncentiveGauge(address _incentiveGauge) public onlyOwner {
        if (_incentiveGauge == address(0)) revert ZeroAddress();
        address oldGauge = address(incentiveGauge);
        incentiveGauge = IIncentiveGauge(_incentiveGauge);
        emit IncentiveGaugeUpdated(oldGauge, _incentiveGauge);
    }

    function setCurStaking(address _curStaking) public onlyOwner{
        if(_curStaking == address(0)) revert ZeroAddress();
        if(CUR_STAKING != address(0)) revert StakingAlreadySet();

        CUR_STAKING = _curStaking;
        minters[_curStaking] = true;

        emit CurStakingUpdated(_curStaking);
     
    }

    // ============================================
    // Pause Functions
    // ============================================

    /**
     * @notice Pause the contract (emergency stop)
     * @dev Only callable by contract owner
     * @dev When paused, mint/redeem/transfers are blocked
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the contract (resume operations)
     * @dev Only callable by contract owner
     */
    function unpause() public onlyOwner {
        _unpause();
    }
}
