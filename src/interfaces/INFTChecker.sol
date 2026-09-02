// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
 
/**
 * @title INFTChecker
 * @dev Interface for NFTChecker;
 */
interface INFTChecker {
    function verifyOwnership(address user, address nftContract, uint256 tokenId) external view returns(bool);
    function getNFTTier(address nftContract) external view returns(uint8);
    function isWhitelisted(address nftContract) external view returns(bool);

    function addWhiteListedContract(address nftContract, uint8 tier) external;
    function removeWhiteListedContract(address nftContract) external;

    function bindNFT(address nftContract, uint256 tokenId) external;
    function unbindNFT() external;   
    function getWhitelistedContractsList() external view returns (address[] memory);  

    event ContractWhiteListed(address indexed nftContract, uint8 tier);
    event ContractRemove(address indexed nftContract);
    event NFTBound(address indexed user, address indexed nftContract, uint256 tokenId, uint8 tier);
    event NFTUnbound(address indexed user);
   

} 

