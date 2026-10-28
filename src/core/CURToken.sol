// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title CURToken
 * @notice Governance and reward token for the CUR Staking Protocol
 * @dev Implements ERC20 with burnable, pausable, and ownable extensions
 * @dev Total supply is fixed at 100,000,000 CUR with 18 decimals
 */
contract CURToken is ERC20, Pausable, Ownable {
    // ============================================
    // Constants
    // ============================================

    /// @notice Total supply of CUR tokens
    uint256 public constant TOTAL_SUPPLY = 100_000_000 * 1e18;


    // ============================================
    // Constructor
    // ============================================

    /**
     * @notice Initializes the CURToken contract
     * @dev Sets token name to "CURToken" and symbol to "CUR"
     * @dev Mints the total supply to the contract deployer
     * @dev The deployer becomes the owner (can mint additional tokens and pause the contract)
     */
    constructor() ERC20("CURToken", "CUR") Ownable(msg.sender) {
        _mint(msg.sender, TOTAL_SUPPLY);
    }

    // ============================================
    // Admin Functions
    // ============================================

    /**
     * @notice Pauses all token transfers
     * @dev Only callable by the contract owner
     * @dev When paused:
     *      - All token movements are blocked (transfer, mint, burn)
     *      - This includes gauge reward distribution and airdrop claims
     *      - Use with caution: pausing will halt the entire protocol
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

   
}
