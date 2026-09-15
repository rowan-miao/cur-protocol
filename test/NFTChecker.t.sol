// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/modules/NFTChecker.sol";

contract MockERC721 {
    mapping(uint256 => address) public owners;
    mapping(address => uint256) public balances;
    uint256 public totalSupply;

    string public name;
    string public symbol;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function mint(address to, uint256 tokenId) public {
        owners[tokenId] = to;
        balances[to]++;
        totalSupply++;
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        require(owners[tokenId] != address(0), "Token does not exist");
        return owners[tokenId];
    }

    function balanceOf(address owner) public view returns (uint256) {
        return balances[owner];
    }
}

contract NFTCheckerTest is Test {
    NFTChecker public nftChecker;
    MockERC721 public midNFT;
    MockERC721 public highNFT;
    MockERC721 public otherNFT;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    uint8 public constant TIER_NONE = 0;
    uint8 public constant TIER_MID = 1;
    uint8 public constant TIER_HIGH = 2;

    event ContractWhiteListed(address indexed nftContract, uint8 tier);
    event ContractRemove(address indexed nftContract);
    event NFTBound(address indexed user, address indexed nftContract, uint256 tokenId, uint8 tier);
    event NFTUnbound(address indexed user);

    // ============================================
    // Setup
    // ============================================
    function setUp() public {
        vm.startPrank(owner);
        nftChecker = new NFTChecker();

        midNFT = new MockERC721("Intermediate NFT", "IMID");
        highNFT = new MockERC721("Advanced NFT", "ADV");
        otherNFT = new MockERC721("Other NFT", "OTHER");

        nftChecker.addWhiteListedContract(address(midNFT), TIER_MID);
        nftChecker.addWhiteListedContract(address(highNFT), TIER_HIGH);

        midNFT.mint(alice, 1);
        midNFT.mint(alice, 2);
        highNFT.mint(alice, 100);
        highNFT.mint(alice, 101);
        otherNFT.mint(alice, 999);

        vm.stopPrank();
    }

    // ============================================
    // Constructor Tests
    // ============================================

    function test_Constructor_SetsOwner() public view {
        assertEq(nftChecker.owner(), owner);
    }

    function test_Constructor_InitialState() public view {
        assertTrue(nftChecker.isWhitelisted(address(midNFT)));
        assertTrue(nftChecker.isWhitelisted(address(highNFT)));
        assertEq(nftChecker.getNFTTier(address(midNFT)), TIER_MID);
        assertEq(nftChecker.getNFTTier(address(highNFT)), TIER_HIGH);
    }

    // ============================================
    // AddWhiteListedContract Tests
    // ============================================

    function test_addWhiteListedContract_Success() public {
        address newNFT = address(new MockERC721("New", "NEW"));

        vm.prank(owner);
        nftChecker.addWhiteListedContract(newNFT, TIER_MID);

        assertTrue(nftChecker.isWhitelisted(address(newNFT)));
        assertEq(nftChecker.getNFTTier(newNFT), TIER_MID);
    }

    function test_addWhiteListedContract_Event() public {
        address newNFT = address(new MockERC721("New", "NEW"));

        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit ContractWhiteListed(newNFT, TIER_HIGH);
        nftChecker.addWhiteListedContract(newNFT, TIER_HIGH);
    }

    function test_addWhiteListedContract_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        nftChecker.addWhiteListedContract(address(otherNFT), TIER_MID);
    }

    function test_addWhiteListedContract_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(NFTChecker.ZeroAddress.selector);
        nftChecker.addWhiteListedContract(address(0), TIER_MID);
    }

    function test_addWhiteListedContract_InvalidTier() public {
        vm.prank(owner);
        vm.expectRevert(NFTChecker.InvalidTier.selector);
        nftChecker.addWhiteListedContract(address(otherNFT), 99);
    }

    // ============================================
    // RemoveWhiteListedContract Tests
    // ============================================

    function test_removeWhiteListedContract_success() public {
        address newNFT = address(new MockERC721("New", "NEW"));

        vm.prank(owner);
        nftChecker.addWhiteListedContract(address(newNFT), TIER_MID);

        vm.prank(owner);
        nftChecker.removeWhiteListedContract(address(newNFT));

        assertFalse(nftChecker.isWhitelisted(address(newNFT)));
        assertEq(nftChecker.getNFTTier(newNFT), TIER_NONE);
    }

    function test_removeWhiteListedContract_Event() public {
        address newNFT = address(new MockERC721("New", "NEW"));

        vm.prank(owner);
        nftChecker.addWhiteListedContract(address(newNFT), TIER_MID);

        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit ContractRemove(address(newNFT));
        nftChecker.removeWhiteListedContract(address(newNFT));
    }

    function test_removeWhiteListedContract_NotOwner() public {
        vm.prank(owner);
        nftChecker.addWhiteListedContract(address(otherNFT), TIER_MID);

        vm.prank(alice);
        vm.expectRevert();
        nftChecker.removeWhiteListedContract(address(otherNFT));
    }

    function test_removeWhiteListedContract_NotWhitelisted() public {
        vm.prank(owner);
        vm.expectRevert(NFTChecker.NotWhitelisted.selector);
        nftChecker.removeWhiteListedContract(address(otherNFT));
    }

    // ============================================
    // VerifyOwnership Tests
    // ============================================
    function test_verifyOwnership_ReturnsTrueWhenOwner() public view {
        assertTrue(nftChecker.verifyOwnership(alice, address(midNFT), 1));
        assertTrue(nftChecker.verifyOwnership(alice, address(highNFT), 100));
    }

    function test_verifyOwnership_ReturnsFalseWhenNotOwner() public view {
        assertFalse(nftChecker.verifyOwnership(bob, address(midNFT), 1));
        assertFalse(nftChecker.verifyOwnership(bob, address(midNFT), 2));
    }

    function test_verifyOwnership_ReturnsFalseWhenNotWhitelisted() public view {
        assertFalse(nftChecker.verifyOwnership(alice, address(otherNFT), 999));
    }

    // ============================================
    // BindNFT Tests
    // ============================================

    function test_bindNFT_Success() public {
        vm.prank(alice);
        nftChecker.bindNFT(address(highNFT), 101);

        (address nftContract, uint256 tokenId, uint8 tier, uint256 bindTime, bool isBound) =
            nftChecker.userBindings(alice);

        assertEq(nftContract, address(highNFT));
        assertEq(tokenId, 101);
        assertEq(tier, TIER_HIGH);
        assertEq(bindTime, block.timestamp);
        assertTrue(isBound);
        assertTrue(nftChecker.nftBound(address(highNFT), 101));
    }

    function test_bindNFT_Event() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit NFTBound(alice, address(highNFT), 101, TIER_HIGH);
        nftChecker.bindNFT(address(highNFT), 101);
    }

    function test_bindNFT_NotWhitelisted() public {
        vm.prank(alice);
        vm.expectRevert(NFTChecker.NotWhitelisted.selector);
        nftChecker.bindNFT(address(otherNFT), 999);
    }

    function test_bindNFT_UserAlreadyBound() public {
        vm.prank(alice);
        nftChecker.bindNFT(address(highNFT), 101);

        vm.prank(alice);
        vm.expectRevert(NFTChecker.UserAlreadyBound.selector);
        nftChecker.bindNFT(address(midNFT), 1);
    }

    function test_bindNFT_NFTAlreadyBound() public {
        vm.prank(alice);
        nftChecker.bindNFT(address(highNFT), 101);

        vm.prank(bob);
        vm.expectRevert(NFTChecker.NFTAlreadyBound.selector);
        nftChecker.bindNFT(address(highNFT), 101);
    }

    function test_bindNFT_NotOwner() public {
        vm.prank(bob);
        vm.expectRevert(NFTChecker.NotOwner.selector);
        nftChecker.bindNFT(address(highNFT), 101);
    }

    // ============================================
    // UnbindNFT Tests
    // ============================================

    function test_unbindNFT_Success() public {
        vm.prank(alice);
        nftChecker.bindNFT(address(highNFT), 101);

        vm.prank(alice);
        nftChecker.unbindNFT();

        (,,,, bool isBound) = nftChecker.userBindings(alice);

        assertFalse(isBound);
        assertFalse(nftChecker.nftBound(address(highNFT), 2));
    }

    function test_unbindNFT_Event() public {
        vm.prank(alice);
        nftChecker.bindNFT(address(highNFT), 101);

        vm.prank(alice);
        vm.expectEmit(true, false, false, false);
        emit NFTUnbound(alice);
        nftChecker.unbindNFT();
    }

    function test_unbindNFT_NoBinding() public {
        vm.prank(alice);
        vm.expectRevert(NFTChecker.NoBinding.selector);
        nftChecker.unbindNFT();
    }

    // ============================================
    // GetNFTTier Tests
    // ============================================
    function test_GetNFTTier_ReturnsTierForWhitelisted() public view {
        assertEq(nftChecker.getNFTTier(address(midNFT)), TIER_MID);
        assertEq(nftChecker.getNFTTier(address(highNFT)), TIER_HIGH);
    }

    function test_GetNFTTier_ReturnsNoneForNonWhitelisted() public view {
        assertEq(nftChecker.getNFTTier(address(otherNFT)), TIER_NONE);
    }

    // ============================================
    // IsWhitelisted Tests
    // ============================================

    function test_IsWhitelisted_ReturnsTrueForWhitelisted() public view {
        assertTrue(nftChecker.isWhitelisted(address(midNFT)));
        assertTrue(nftChecker.isWhitelisted(address(highNFT)));
    }

    function test_IsWhitelisted_ReturnsFalseForNonWhitelisted() public view {
        assertFalse(nftChecker.isWhitelisted(address(otherNFT)));
    }

    // ============================================
    // GetWhitelistedContractsList Tests
    // ============================================

    function test_GetWhitelistedContractsList_ReturnsAllContracts() public view {
        address[] memory list = nftChecker.getWhitelistedContractsList();
        assertEq(list.length, 2);
        assertEq(list[0], address(midNFT));
        assertEq(list[1], address(highNFT));
    }

    // ============================================
    // Pause Tests
    // ============================================

    function test_Pause_Success() public {
        vm.prank(owner);
        nftChecker.pause();

        assertTrue(nftChecker.paused());
    }

    function test_Unpause_Success() public {
        vm.prank(owner);
        nftChecker.pause();

        vm.prank(owner);
        nftChecker.unpause();

        assertFalse(nftChecker.paused());
    }

    function test_Pause_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        nftChecker.pause();
    }

    function test_BindNFT_Paused() public {
        vm.prank(owner);
        nftChecker.pause();

        vm.prank(alice);
        vm.expectRevert();
        nftChecker.bindNFT(address(midNFT), 1);
    }

    function test_UnbindNFT_Paused() public {
        vm.prank(alice);
        nftChecker.bindNFT(address(midNFT), 1);

        vm.prank(owner);
        nftChecker.pause();

        vm.prank(alice);
        vm.expectRevert();
        nftChecker.unbindNFT();
    }

    // ============================================
    // Edge Case Tests
    // ============================================

    function test_BindAndUnbindMultipleTimes() public {
        vm.prank(alice);
        nftChecker.bindNFT(address(midNFT), 1);

        vm.prank(alice);
        nftChecker.unbindNFT();

        vm.prank(alice);
        nftChecker.bindNFT(address(midNFT), 2);

        (,, uint8 tier,, bool isBound) = nftChecker.userBindings(alice);
        assertTrue(isBound);
        assertEq(tier, TIER_MID);
    }

    function test_DifferentUsersBindDifferentNFTs() public {
        vm.prank(alice);
        nftChecker.bindNFT(address(midNFT), 1);

        vm.prank(owner);
        highNFT.mint(bob, 200);

        vm.prank(bob);
        nftChecker.bindNFT(address(highNFT), 200);

        (,,,, bool isBoundAlice) = nftChecker.userBindings(alice);
        (,,,, bool isBoundBob) = nftChecker.userBindings(bob);

        assertTrue(isBoundAlice);
        assertTrue(isBoundBob);
        assertTrue(nftChecker.nftBound(address(midNFT), 1));
        assertTrue(nftChecker.nftBound(address(highNFT), 200));
    }

    function test_UserCanBindDifferentNFTAfterUnbind() public {
        vm.prank(alice);
        nftChecker.bindNFT(address(midNFT), 1);

        vm.prank(alice);
        nftChecker.unbindNFT();

        vm.prank(alice);
        nftChecker.bindNFT(address(highNFT), 100);

        (address nftContract, uint256 tokenId,,,) = nftChecker.userBindings(alice);
        assertEq(nftContract, address(highNFT));
        assertEq(tokenId, 100);
    }

    // ============================================
    // Fuzz Tests
    // ============================================

    function testFuzz_AddWhitelistedContract_AnyTier(uint8 tier) public {
        vm.assume(tier == TIER_MID || tier == TIER_HIGH);

        address newNFT = address(new MockERC721("Fuzz", "FUZZ"));

        vm.prank(owner);
        nftChecker.addWhiteListedContract(newNFT, tier);

        assertTrue(nftChecker.isWhitelisted(newNFT));
        assertEq(nftChecker.getNFTTier(newNFT), tier);
    }

    function testFuzz_BindNFT_ValidTokenId(uint256 tokenId) public {
        vm.assume(tokenId > 0);
        vm.assume(tokenId < 10000);

        // Mint a new NFT to alice
        vm.prank(owner);
        midNFT.mint(alice, tokenId);

        vm.prank(alice);
        nftChecker.bindNFT(address(midNFT), tokenId);

        (, uint256 storedTokenId,,, bool isBound) = nftChecker.userBindings(alice);
        assertTrue(isBound);
        assertEq(storedTokenId, tokenId);
    }

    function testFuzz_BindNFT_FailsForNonExistentToken(uint256 tokenId) public {
        vm.assume(tokenId > 1000);
        vm.assume(tokenId != 1 && tokenId != 2 && tokenId != 100 && tokenId != 101);

        vm.prank(alice);
        vm.expectRevert();
        nftChecker.bindNFT(address(midNFT), tokenId);
    }

    function testFuzz_MultipleNFTsBindAndUnbind(uint8 iterations) public {
        vm.assume(iterations > 0);
        vm.assume(iterations <= 10);

        for (uint8 i = 0; i < iterations; i++) {
            vm.prank(alice);
            nftChecker.bindNFT(address(midNFT), 1);

            vm.prank(alice);
            nftChecker.unbindNFT();
        }

        (,,,, bool isBound) = nftChecker.userBindings(alice);
        assertFalse(isBound);
    }
}
