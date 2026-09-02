// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title NFTChecker
 * @author CUR Protocol Team
 * @notice NFT permission validator for lock duration tiers
 * @dev Manages NFT whitelist and validates user NFT holdings for lock permissions
 * 
 * Features:
 * - Whitelist management for NFT contracts (owner only)
 * - NFT binding/unbinding to prevent reuse
 * - Permission tier validation (NONE, MID, HIGH)
 * - Anti-abuse mechanism: one NFT per account, one account per NFT
 */
contract NFTChecker is Pausable, Ownable {
    // ============================================
    // Constants
    // ============================================
    
    uint8 public constant TIER_NONE = 0;
    uint8 public constant TIER_MID = 1;
    uint8 public constant TIER_HIGH = 2;

    // ============================================
    // Structs
    // ============================================
    
    /**
     * @title UserBinding
     * @notice User NFT binding information
     */
    struct UserBinding{
        address nftContract;
        uint256 tokenId;
        uint8 tier;
        uint256 bindTime;
        bool isBound;
    }
    
    // ============================================
    // State Variables
    // ============================================

    mapping(address => bool) public whitelistedContracts;
    mapping(address => uint8) public contractTiers;
    mapping(address => UserBinding) public userBindings;
    mapping(address => mapping(uint256 => bool)) public nftBound;

    address[] public whitelistedContractsList;

    // ============================================
    // Events
    // ============================================
    
    /// @notice Emitted when an NFT contract is added to whitelist
    event ContractWhiteListed(address indexed nftContract, uint8 tier);
    /// @notice Emitted when an NFT contract is removed from whitelist
    event ContractRemove(address indexed nftContract);
    /// @notice Emitted when a user binds an NFT to their account
    event NFTBound(address indexed user, address indexed nftContract, uint256 tokenId, uint8 tier);
    /// @notice Emitted when a user unbinds an NFT
    event NFTUnbound(address indexed user);

    // ============================================
    // Errors
    // ============================================
    
    /// @notice Thrown when zero address is provided
    error ZeroAddress();
    /// @notice Thrown when tier value is invalid
    error InvalidTier();
    /// @notice Thrown when NFT contract is not whitelisted
    error NotWhitelisted();
    /// @notice Thrown when user already has a bound NFT
    error UserAlreadyBound();
    /// @notice Thrown when NFT is already bound by another user
    error NFTAlreadyBound();
    /// @notice Thrown when caller is not the NFT owner
    error NotOwner();
    /// @notice Thrown when user has no bound NFT to unbind
    error NoBinding();


    // ============================================
    // Constructor
    // ============================================
    
    /**
     * @notice Initializes the NFTChecker contract
     * @dev Sets the contract owner
     */
    constructor() Ownable(msg.sender) {}
  

    // ============================================
    // View Functions
    // ============================================
    
    /**
     * @notice Verifies if a user owns a specific NFT
     * @dev Returns false if NFT contract is not whitelisted
     * @param user User address to check
     * @param nftContract NFT contract address
     * @param tokenId NFT token ID
     * @return True if user owns the NFT and contract is whitelisted
     */
    function verifyOwnership(address user, address nftContract, uint256 tokenId) public view returns(bool){
        if(!whitelistedContracts[nftContract]) return false;
        
        address owner = IERC721(nftContract).ownerOf(tokenId);
        return owner == user;
    
    }

    /**
     * @notice Gets the tier level of an NFT contract
     * @param nftContract NFT contract address
     * @return Tier level (0 = NONE, 1 = MID, 2 = HIGH)
     */
    function getNFTTier(address nftContract) public view returns(uint8) {
        if(!whitelistedContracts[nftContract]) return TIER_NONE;
        return contractTiers[nftContract];

    }

    /**
     * @notice Checks if an NFT contract is whitelisted
     * @param nftContract NFT contract address
     * @return True if contract is in whitelist
     */
    function isWhitelisted(address nftContract) public view returns(bool){
        return whitelistedContracts[nftContract];

    } 

    /**
     * @notice Gets the complete list of whitelisted NFT contracts
     * @return Array of whitelisted contract addresses
     */
    function getWhitelistedContractsList() public view returns (address[] memory) {
        return whitelistedContractsList;
    }

    // ============================================
    // Admin Functions
    // ============================================
    
    /**
     * @notice Adds an NFT contract to the whitelist
     * @dev Only callable by contract owner
     * @param nftContract NFT contract address
     * @param tier Tier level (1 = MID, 2 = HIGH)
     */
    function addWhiteListedContract(address nftContract, uint8 tier) public onlyOwner {
        if(nftContract == address(0)) revert ZeroAddress();
        if(tier != TIER_MID && tier != TIER_HIGH) revert InvalidTier();

        if(!whitelistedContracts[nftContract]) {
            whitelistedContractsList.push(nftContract);
        }

        whitelistedContracts[nftContract] = true;
        contractTiers[nftContract] = tier;

        emit ContractWhiteListed(nftContract, tier);


    }

    /**
     * @notice Removes an NFT contract from the whitelist
     * @dev Only callable by contract owner
     * @param nftContract NFT contract address
     */
    function removeWhiteListedContract(address nftContract) public onlyOwner{
        ///检查地址是否在白名单中
        if(!whitelistedContracts[nftContract]) revert NotWhitelisted();
        ///从mapping中删除
        delete whitelistedContracts[nftContract];
        delete contractTiers[nftContract];
        ///发送事件
        emit ContractRemove(nftContract);

    }

    // ============================================
    // User Functions
    // ============================================
    
    /**
     * @notice Binds an NFT to the caller's account
     * @dev One user can only bind one NFT at a time
     * @param nftContract NFT contract address
     * @param tokenId NFT token ID to bind
     */
    function bindNFT(address nftContract, uint256 tokenId) public whenNotPaused {
        //检查用户是否在白名单中
        if(!whitelistedContracts[nftContract]) revert NotWhitelisted();
        ///检查用户是否已绑定
        if(userBindings[msg.sender].isBound) revert UserAlreadyBound();
        //NFT是否绑定
        if(nftBound[nftContract][tokenId]) revert NFTAlreadyBound();
        ///检查是否持有NFT
        address owner = IERC721(nftContract).ownerOf(tokenId);
        if(msg.sender != owner)  revert NotOwner();
        //获得tier等级
        uint8 tier = contractTiers[nftContract];
        //更新UserBinding
        nftBound[nftContract][tokenId] = true;
        userBindings[msg.sender] = UserBinding({
            nftContract : nftContract,
            tokenId : tokenId,
            tier : tier,
            bindTime : block.timestamp,
            isBound : true
        });

        //发送事件
        emit NFTBound(msg.sender, nftContract, tokenId, tier);
       
    }

    /**
     * @notice Unbinds the NFT from the caller's account
     * @dev Allows the NFT to be bound by another user
     */
    function unbindNFT() public whenNotPaused {
        //检查用户是否绑定Nft
        if(!userBindings[msg.sender].isBound) revert NoBinding();
        address nftContract = userBindings[msg.sender].nftContract;
        uint256 tokenId = userBindings[msg.sender].tokenId;
        //删除nftBound 
        delete nftBound[nftContract][tokenId];
        //删除用户绑定信息
        delete userBindings[msg.sender]; 
        //发送事件
        emit NFTUnbound(msg.sender);

    }

    // ============================================
    // Pause Functions 
    // ============================================
    
    /**
     * @notice Pauses NFT binding/unbinding operations
     * @dev Only callable by contract owner
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses NFT binding/unbinding operations
     * @dev Only callable by contract owner
     */
    function unpause() public onlyOwner {
        _unpause();
    }

    


}
