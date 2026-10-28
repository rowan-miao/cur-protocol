// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../interfaces/IveCURLock.sol";

/**
 * @title NFTChecker
 * @author CUR Protocol Team
 * @notice NFT permission validator for lock duration tiers
 * @dev Manages NFT whitelist and validates user NFT holdings for lock permissions
 *
 * Key Features:
 * - Whitelist management for NFT contracts (owner only)
 * - NFT binding/unbinding with anti-abuse mechanism:
 *   - One NFT per account (user can only bind one NFT)
 *   - One account per NFT (NFT can only be bound by one account)
 * - Permission tier validation:
 *   - TIER_NONE (0): No NFT, max lock 180 days
 *   - TIER_MID (1): Mid-tier NFT, max lock 365 days
 *   - TIER_HIGH (2): High-tier NFT, max lock 730 days
 * - Lock-aware unbinding: cannot unbind while locked in veCURLock
 */
contract NFTChecker is Pausable, Ownable {
    IveCURLock public veLock;
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
    struct UserBinding {
        address nftContract;
        uint256 tokenId;
        uint256 bindTime;
        bool isBound;
    }

    // ============================================
    // State Variables
    // ============================================

   
    mapping(address => UserBinding) public userBindings;
    mapping(address => mapping(uint256 => bool)) public nftBound;
    mapping(address => uint8) public contractTiers;

    address[] public whitelistedContractsList;
    mapping(address => uint256) private _whitelistIndex;

    // ============================================
    // Events
    // ============================================

    /// @notice Emitted when an NFT contract is added to whitelist
    event ContractWhiteListed(address indexed nftContract, uint8 tier);
    /// @notice Emitted when an NFT contract is removed from whitelist
    event ContractRemoved(address indexed nftContract);
    /// @notice Emitted when a user binds an NFT to their account
    event NFTBound(address indexed user, address indexed nftContract, uint256 tokenId, uint8 tier);
    /// @notice Emitted when a user unbinds an NFT
    event NFTUnbound(address indexed user, address indexed nftContract, uint256 tokenId, uint8 tier);
    /// @notice Emitted when veCURLock contract address is updated
    event VeLockUpdated(address indexed oldAddress, address indexed newAddress);

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
    error NotBound();
    /// @notice Thrown when user is locked in veCURLock and cannot unbind
    error PositionLocked();
    /// @notice Thrown when the caller is not authorized
    error Unauthorized();
   /// @notice Thrown when an address parameter is invalid
    error InvalidAddress();
    /// @notice Thrown when attempting to set an address to its current value 
    error SameAddress();


    // ============================================
    // modifier
    // ============================================

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
     * @notice Initializes the NFTChecker contract
     * @param _veLock Address of the veCURLock contract
     */
    constructor(address _veLock) Ownable(msg.sender) {
        if (_veLock != address(0)) veLock = IveCURLock(_veLock);
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
        if (nftContract == address(0)) revert ZeroAddress();
        if (tier != TIER_MID && tier != TIER_HIGH) revert InvalidTier();

        if (contractTiers[nftContract] == TIER_NONE) {
            whitelistedContractsList.push(nftContract);
            _whitelistIndex[nftContract] = whitelistedContractsList.length;
        }

        contractTiers[nftContract] = tier;

        emit ContractWhiteListed(nftContract, tier);
    }

    /**
     * @notice Removes an NFT contract from the whitelist
     * @dev Only callable by contract owner
     * @param nftContract NFT contract address
     */
    function removeWhiteListedContract(address nftContract) public onlyOwner {
        if (contractTiers[nftContract] == TIER_NONE) revert NotWhitelisted();
        uint256 indexPlusOne = _whitelistIndex[nftContract];

        if (indexPlusOne == 0) revert NotWhitelisted();

        uint256 index = indexPlusOne - 1;
        uint256 lastIndex = whitelistedContractsList.length - 1;

        if (index != lastIndex) {
            address lastContract = whitelistedContractsList[lastIndex];
            whitelistedContractsList[index] = lastContract;
 
            _whitelistIndex[lastContract] = index + 1;
        }


        whitelistedContractsList.pop();

        delete _whitelistIndex[nftContract];
        delete contractTiers[nftContract];
   
        emit ContractRemoved(nftContract);
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
        if (contractTiers[nftContract] == TIER_NONE) revert NotWhitelisted();
        ///检查用户是否已绑定
        if (userBindings[msg.sender].isBound) revert UserAlreadyBound();
        //NFT是否绑定
        if (nftBound[nftContract][tokenId]) revert NFTAlreadyBound();
        ///检查是否持有NFT
        address owner = IERC721(nftContract).ownerOf(tokenId);
        if (msg.sender != owner) revert NotOwner();
        
        //更新UserBinding
        nftBound[nftContract][tokenId] = true;
        userBindings[msg.sender] = UserBinding({
            nftContract: nftContract, tokenId: tokenId, bindTime: block.timestamp, isBound: true
        });

        //发送事件
        emit NFTBound(msg.sender, nftContract, tokenId, contractTiers[nftContract]);
    }

    /**
     * @notice Allows a user to unbind their own NFT
     * @dev Caller is msg.sender; subject to lock check
     */
    function unbindNFT() public {
        _unbind(msg.sender);
    }

    /**
     * @notice Internal unbind logic (shared by user self-unbind and veCURLock proxy-unbind)
     * @param user Address of the user to unbind NFT for
     */
    function _unbind(address user) internal {
        if (address(veLock) != address(0) && veLock.isLocked(user)) revert PositionLocked();
        UserBinding memory binding = userBindings[user];
        //检查用户是否绑定Nft
        if (!binding.isBound) revert NotBound();

        address nftContract = binding.nftContract;
        uint256 tokenId = binding.tokenId;
        //删除nftBound
        nftBound[nftContract][tokenId] = false;
        //删除用户绑定信息
        delete userBindings[user];
        //发送事件
        emit NFTUnbound(user, nftContract, tokenId, contractTiers[nftContract]);
    }

    /**
     * @notice Proxy unbind called by veCURLock
     * @param user Address of the user to unbind NFT for
     */
    function unbindNFTFor(address user) external onlyVeLock {
        _unbind(user);
    }

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
    function verifyOwnership(address user, address nftContract, uint256 tokenId) public view returns (bool) {
        if (contractTiers[nftContract] == TIER_NONE) return false;

        address owner = IERC721(nftContract).ownerOf(tokenId);
        return owner == user;
    }


    /**
     * @notice Checks if an NFT contract is whitelisted
     * @param nftContract NFT contract address
     * @return True if contract is in whitelist
     */
    function isWhitelisted(address nftContract) public view returns (bool) {
        return contractTiers[nftContract] != TIER_NONE;
    }

    /**
     * @notice Gets the complete list of whitelisted NFT contracts
     * @return Array of whitelisted contract addresses
     */
    function getWhitelistedContractsList() public view returns (address[] memory) {
        return whitelistedContractsList;
    }

    /**
     * @notice Gets the user's bound NFT tier
     * @param user User address
     * @return tier NFT tier (0 if not bound)
     */
    function getUserTier(address user) public view returns (uint8) {
        UserBinding memory binding = userBindings[user];
        if(!binding.isBound) return TIER_NONE;
        return contractTiers[binding.nftContract];
        
    }

    /**
     * @notice Checks if a user has a bound NFT
     * @param user User address to check
     * @return True if user has a bound NFT, false otherwise
     */
    function isUserBound(address user) public view returns (bool) {
        return userBindings[user].isBound;
    }

    /**
     * @notice Updates the veCURLock contract address
     * @dev Only callable by the owner to update the protocol dependency
     * @param _veLock New veCURLock contract address
     */
    function setVeLock(address _veLock) external onlyOwner {
        if (_veLock == address(0)) revert ZeroAddress();
        if(_veLock == address(this)) revert InvalidAddress();
        if(_veLock == address(veLock)) revert SameAddress();

        address oldVeLock = address(veLock);
        veLock = IveCURLock(_veLock);

        emit VeLockUpdated(oldVeLock, _veLock);
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
