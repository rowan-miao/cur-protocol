// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title Airdrop
 * @author CUR Protocol Team
 * @notice Community airdrop contract for early supporters
 * @dev Manages whitelist and distributes CUR tokens to eligible users
 * 
 * Features:
 * - Whitelist management (add/remove users)
 * - Batch whitelist addition
 * - Claim functionality for whitelisted users
 * - Each user can claim only once
 * - Pausable for emergency situations
 */
contract Airdrop is Ownable, Pausable {
    IERC20 public immutable curToken;

    uint256 public constant AIRDROP_AMOUNT = 1000 * 1e18;

    uint256 public totalClaimed;
    uint256 public totalRecipients;

    mapping(address => bool) public hasClaimed;
    mapping(address => bool) public isWhitelisted; 

    // ============================================
    // Events
    // ============================================
    
    /// @notice Emitted when a user successfully claims their airdrop
    event Claimed(address indexed user, uint256 amount);
    /// @notice Emitted when multiple users are added to whitelist
    event AddWhitelist(address[] indexed users);
    /// @notice Emitted when a single user is added to whitelist
    event AddToWhitelist(address indexed user);
    /// @notice Emitted when a user is removed from whitelist
    event RemoveFromWhitelist(address indexed user);
    /// @notice Emitted when CUR tokens are deposited into the contract
    event Deposited(uint256 amount);

    // ============================================
    // Errors
    // ============================================
    
    /// @notice Thrown when zero address is provided
    error ZeroAddress();
    /// @notice Thrown when caller is not whitelisted
    error NotWhitelisted();
    /// @notice Thrown when user has already claimed
    error AlreadyClaimed();
    /// @notice Thrown when contract has insufficient CUR balance
    error InsufficientBalance();
    /// @notice Thrown when trying to add an empty array to whitelist
    error EmptyArray();
    /// @notice Thrown when user is already whitelisted
    error AlreadyWhitelisted();
    /// @notice Thrown when zero amount is provided
    error ZeroAmount();

    // ============================================
    // Constructor
    // ============================================
    
    /**
     * @notice Initializes the Airdrop contract
     * @dev Sets the CUR token address
     * @param _curtoken Address of the CUR token
     */
    constructor(address _curtoken) Ownable(msg.sender) {
        if (_curtoken == address(0)) revert ZeroAddress();
        curToken = IERC20(_curtoken);
    }

    // ============================================
    // Whitelist Management
    // ============================================
    
    /**
     * @notice Adds a single user to the whitelist
     * @dev Only callable by contract owner
     * @param user Address to add to whitelist
     */
    function addToWhitelist(address user) public onlyOwner{
        if(user == address(0)) revert ZeroAddress();
        if(isWhitelisted[user]) revert AlreadyWhitelisted();
        isWhitelisted[user] = true;

        emit AddToWhitelist(user); 
    }
    
    /**
     * @notice Adds multiple users to the whitelist
     * @dev Only callable by contract owner. Gas efficient for large batches.
     * @param users Array of addresses to add to whitelist
     */
    function addWhitelist(address[] calldata users) public onlyOwner{
        if(users.length == 0) revert EmptyArray();
        for(uint256 i = 0; i < users.length; i++){
            if(users[i] != address(0)){
                isWhitelisted[users[i]] = true;
            }
            
        }

        emit AddWhitelist(users);
    }

    /**
     * @notice Removes a user from the whitelist
     * @dev Only callable by contract owner
     * @param user Address to remove from whitelist
     */
    function removeFromWhitelist(address user) public onlyOwner{
        if(!isWhitelisted[user]) revert NotWhitelisted();
        isWhitelisted[user] = false;

        emit RemoveFromWhitelist(user);


    }

    // ============================================
    // Claim Functions
    // ============================================
    
    /**
     * @notice Claims the airdrop for the caller
     * @dev User must be whitelisted and not have claimed before
     */
    function claim() public whenNotPaused {
        if(!isWhitelisted[msg.sender]) revert NotWhitelisted();
        if(hasClaimed[msg.sender]) revert AlreadyClaimed();

        uint256 balance = curToken.balanceOf(address(this));
        if(balance < AIRDROP_AMOUNT) revert InsufficientBalance();

        hasClaimed[msg.sender] = true;
        totalClaimed += AIRDROP_AMOUNT;
        totalRecipients++;

        curToken.transfer(msg.sender, AIRDROP_AMOUNT);

        emit Claimed(msg.sender, AIRDROP_AMOUNT);


    }
    
    // ============================================
    // Deposit Functions
    // ============================================
    
    /**
     * @notice Deposits CUR tokens into the contract for distribution
     * @dev Only callable by contract owner
     * @param amount Amount of CUR to deposit
     */
    function deposit(uint256 amount) public onlyOwner{
        if(amount == 0) revert ZeroAmount();
        curToken.transferFrom(msg.sender, address(this), amount);
        emit Deposited(amount);
    }

    // ============================================
    // View Functions
    // ============================================
    
    /**
     * @notice Gets the remaining CUR balance in the contract
     * @return Remaining CUR amount
     */
    function getRemainingTokens() public view returns(uint256){
        return curToken.balanceOf(address(this));
        
    }

    /**
     * @notice Gets the total amount of CUR claimed so far
     * @return Total claimed amount
     */
    function getTotalClaimed() public view returns(uint256){
        return totalClaimed;
    }
    
    
    // ============================================
    // Pause Functions
    // ============================================
    
    /**
     * @notice Pauses the claim functionality
     * @dev Only callable by contract owner
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the claim functionality
     * @dev Only callable by contract owner
     */
    function unpause() public onlyOwner {
        _unpause();
    }


}