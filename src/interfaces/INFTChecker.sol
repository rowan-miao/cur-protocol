// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title INFTChecker
 * @dev Interface for NFTChecker;
 */
interface INFTChecker {
    function addWhiteListedContract(address nftContract, uint8 tier) external;
    function removeWhiteListedContract(address nftContract) external;

    function bindNFT(address nftContract, uint256 tokenId) external;
    function unbindNFTFor(address user) external;
    function unbindNFT() external;

    function verifyOwnership(address user, address nftContract, uint256 tokenId) external view returns (bool);
    function isWhitelisted(address nftContract) external view returns (bool);
    function getWhitelistedContractsList() external view returns (address[] memory);
    function getUserTier(address user) external view returns (uint8);
    function isUserBound(address user) external view returns (bool);
    function TIER_NONE() external view returns (uint8);
    function TIER_MID() external view returns (uint8);
    function TIER_HIGH() external view returns (uint8);

    event ContractWhiteListed(address indexed nftContract, uint8 tier);
    event ContractRemoved(address indexed nftContract);
    event NFTBound(address indexed user, address indexed nftContract, uint256 tokenId, uint8 tier);
    event NFTUnbound(address indexed user, address indexed nftContract, uint256 tokenId, uint8 tier);
}
