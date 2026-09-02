// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
* @title CURToken
* @notice Governance and reward token for the CUR Staking Protocol
* @dev Implements ERC20 with burnable, pausable, and ownable extensions
* @dev Total supply is fixed at 100,000,000 CUR with 18 decimals
*/ 
contract CURToken is ERC20, ERC20Burnable, Pausable, Ownable {
    // ============================================
    // Constants
    // ============================================
    
    /// @notice Total supply of CUR tokens
    uint256 public constant TOTAL_SUPPLY = 100_000_000 * 1e18;

    // ============================================
    // Errors
    // ============================================
   
    /// @notice Thrown when zero address is provided
    error ZeroAddress();
    /// @notice Thrown when invalid amount (zero) is provided
    error InvalidAmount();
    /// @notice Thrown when minting would exceed total supply
    error ExceedsTotalSupply();

    // ============================================
    // Constructor
    // ============================================
    
    /**
    * @notice Initializes the CURToken contract
     * @dev Sets token name to "CURToken" and symbol to "CUR"
     * @dev Mints the total supply to the contract deployer
     * @dev The deployer becomes the owner (can mint additional tokens and pause the contract)
     */
    constructor() ERC20("CURToken", "CUR") Ownable(msg.sender){
        _mint(msg.sender, TOTAL_SUPPLY);
    }

    // ============================================
    // Admin Functions
    // ============================================

    /**
     * @notice Pauses all token transfers
     * @dev Only callable by the contract owner
     * @dev When paused:
     *      - User-to-user transfers are blocked
     *      - Minting and burning are still allowed
     *      - Authorizations (approve) are not affected
     * @custom:modifier onlyOwner
     */
    function pause() public onlyOwner {
        _pause();
    }

     /**
     * @notice Unpauses token transfers, restoring normal functionality
     * @dev Only callable by the contract owner
     * @dev After unpausing, all token transfers work normally
     */
    function unpause() public onlyOwner {
        _unpause();
    }

    // ============================================
    // Core Functions
    // ============================================
 
    /**
     * @notice Mints new CUR tokens to a specified address
     * @dev Only callable by the contract owner
     * @dev Increases the total supply by the minted amount
     * @dev Used for initial distribution and emergency inflation (subject to governance)
     * @param to The address that will receive the minted tokens
     * @param amount The amount of tokens to mint (in wei)
     */
    function mint(address to, uint256 amount) public onlyOwner {
        if(to == address(0)) revert ZeroAddress();
        if(amount == 0) revert InvalidAmount();
       
        if (totalSupply() + amount > TOTAL_SUPPLY) revert ExceedsTotalSupply();

        _mint(to, amount);
    }

    // ============================================
    // Internal Functions
    // ============================================

    /**
     * @notice Hook executed before token transfers, minting, or burning
     * @dev Overrides ERC20's `_update` to add pause functionality
     * @dev ALL token movements are blocked when paused, including:
     *      - Transfers between users (from != address(0) && to != address(0))
     *      - Minting (from == address(0))
     *      - Burning (to == address(0))
     * @param from Source address (address(0) for minting)
     * @param to Destination address (address(0) for burning)
     * @param amount Amount of tokens being transferred, minted, or burned
     */
    function _update(address from, address to, uint256 amount)
        internal
        override
        whenNotPaused
    {
        super._update(from, to, amount);
    }

 
}
