// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/core/CURToken.sol";
import "../src/modules/Airdrop.sol";

contract AirdropTest is Test {
    CURToken public curToken;
    Airdrop public airdrop;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    uint256 public constant AIRDROP_AMOUNT = 1000 * 1e18;
    uint256 public constant TOTAL_AIRDROP = 10000000 * 1e18;

    event Claimed(address indexed user, uint256 amount);
    event AddWhitelist(address[] indexed users);
    event AddToWhitelist(address indexed user);
    event RemoveFromWhitelist(address indexed user);
    event Deposited(uint256 amount);

    function setUp() public {
        vm.startPrank(owner);

        curToken = new CURToken();
        airdrop = new Airdrop(address(curToken));
        curToken.transfer(address(airdrop), TOTAL_AIRDROP);

        vm.stopPrank();
    }

    function test_Constructor() public view {
        assertEq(address(airdrop.curToken()), address(curToken));
        assertEq(airdrop.AIRDROP_AMOUNT(), AIRDROP_AMOUNT);
        assertEq(airdrop.getRemainingTokens(), TOTAL_AIRDROP);
        assertEq(airdrop.totalClaimed(), 0);
        assertEq(airdrop.totalRecipients(), 0);
        assertEq(airdrop.owner(), owner);
    }

    function test_Constructor_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(Airdrop.ZeroAddress.selector);
        new Airdrop(address(0));
    }

    // ============================================
    // AddToWhitelist Tests
    // ============================================
    function test_AddToWhitelist_Success() public {
        vm.prank(owner);
        airdrop.addToWhitelist(alice);
        assertTrue(airdrop.isWhitelisted(alice));
    }

    function test_AddToWhitelist_Event() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit AddToWhitelist(alice);
        airdrop.addToWhitelist(alice);
    }

    function test_AddToWhitelist_NotOwner() public {
        vm.prank(bob);
        vm.expectRevert();
        airdrop.addToWhitelist(alice);
    }

    function test_AddToWhitelist_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(Airdrop.ZeroAddress.selector);
        airdrop.addToWhitelist(address(0));
    }

    function test_AddToWhitelist_AlreadyWhitelisted() public {
        vm.prank(owner);
        airdrop.addToWhitelist(alice);

        vm.prank(owner);
        vm.expectRevert(Airdrop.AlreadyWhitelisted.selector);
        airdrop.addToWhitelist(alice);
    }

    // ============================================
    // AddWhitelist Tests
    // ============================================
    function test_AddWhitelist_Success() public {
        address[] memory users = new address[](3);
        users[0] = alice;
        users[1] = bob;
        users[2] = charlie;

        vm.prank(owner);
        airdrop.addWhitelist(users);

        assertTrue(airdrop.isWhitelisted(alice));
        assertTrue(airdrop.isWhitelisted(bob));
        assertTrue(airdrop.isWhitelisted(charlie));
    }

    function test_AddWhitelist_Event() public {
        address[] memory users = new address[](2);
        users[0] = alice;
        users[1] = bob;

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit AddWhitelist(users);

        airdrop.addWhitelist(users);
    }

    function test_AddWhitelist_NotOwner() public {
        address[] memory users = new address[](2);
        users[0] = alice;
        users[1] = bob;

        vm.prank(charlie);
        vm.expectRevert();
        airdrop.addWhitelist(users);
    }

    function test_AddWhitelist_SkipsZeroAddress() public {
        address[] memory users = new address[](2);
        users[0] = alice;
        users[1] = address(0);

        vm.prank(owner);
        airdrop.addWhitelist(users);

        assertTrue(airdrop.isWhitelisted(alice));
        assertFalse(airdrop.isWhitelisted(address(0)));
    }

    function test_AddWhitelist_EmptyArray() public {
        address[] memory users = new address[](0);

        vm.prank(owner);
        vm.expectRevert(Airdrop.EmptyArray.selector);
        airdrop.addWhitelist(users);
    }

    // ============================================
    // RemoveFromWhitelist Tests
    // ============================================
    function test_RemoveFromWhitelist_Success() public {
        vm.prank(owner);
        airdrop.addToWhitelist(alice);

        vm.prank(owner);
        airdrop.removeFromWhitelist(alice);

        assertFalse(airdrop.isWhitelisted(alice));
    }

    function test_RemoveFromWhitelist_Event() public {
        vm.prank(owner);
        airdrop.addToWhitelist(alice);

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit RemoveFromWhitelist(alice);
        airdrop.removeFromWhitelist(alice);
    }

    function test_RemoveFromWhitelist_NotOwner() public {
        vm.prank(owner);
        airdrop.addToWhitelist(alice);

        vm.prank(alice);
        vm.expectRevert();
        airdrop.removeFromWhitelist(bob);
    }

    function test_RemoveFromWhitelist_NotWhitelisted() public {
        vm.prank(owner);
        vm.expectRevert(Airdrop.NotWhitelisted.selector);
        airdrop.removeFromWhitelist(bob);
    }

    function test_RemoveFromWhitelist_Batch_Success() public {
        address[] memory users = new address[](3);
        users[0] = alice;
        users[1] = bob;
        users[2] = charlie;

        vm.prank(owner);
        airdrop.addWhitelist(users);

        vm.prank(owner);
        airdrop.removeFromWhitelist(alice);

        vm.prank(owner);
        airdrop.removeFromWhitelist(bob);

        vm.prank(owner);
        airdrop.removeFromWhitelist(charlie);

        assertFalse(airdrop.isWhitelisted(alice));
        assertFalse(airdrop.isWhitelisted(bob));
        assertFalse(airdrop.isWhitelisted(charlie));
    }

    // ============================================
    // Claim Tests
    // ============================================

    function test_Claim_Success() public {
        vm.prank(owner);
        airdrop.addToWhitelist(alice);

        vm.prank(alice);
        airdrop.claim();

        assertTrue(airdrop.hasClaimed(alice));
        assertEq(curToken.balanceOf(alice), AIRDROP_AMOUNT);
        assertEq(airdrop.totalRecipients(), 1);
        assertEq(airdrop.totalClaimed(), AIRDROP_AMOUNT);
        assertEq(airdrop.getRemainingTokens(), TOTAL_AIRDROP - AIRDROP_AMOUNT);
    }

    function test_Claim_Event() public {
        vm.prank(owner);
        airdrop.addToWhitelist(alice);

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit Claimed(alice, AIRDROP_AMOUNT);
        airdrop.claim();
    }

    function test_claim_NotWhitelisted() public {
        vm.prank(alice);
        vm.expectRevert(Airdrop.NotWhitelisted.selector);
        airdrop.claim();
    }

    function test_claim_AlreadyClaimed() public {
        vm.prank(owner);
        airdrop.addToWhitelist(alice);

        vm.prank(alice);
        airdrop.claim();

        vm.prank(alice);
        vm.expectRevert(Airdrop.AlreadyClaimed.selector);
        airdrop.claim();
    }

    function test_claim_InsufficientBalance() public {
        Airdrop smallAirdrop;
        CURToken smallCURToken;

        vm.startPrank(owner);

        smallCURToken = new CURToken();
        smallAirdrop = new Airdrop(address(smallCURToken));
        smallCURToken.transfer(address(smallAirdrop), 1500 * 1e18);

        smallAirdrop.addToWhitelist(alice);
        smallAirdrop.addToWhitelist(bob);

        vm.stopPrank();

        vm.prank(alice);
        smallAirdrop.claim();

        vm.prank(bob);
        vm.expectRevert(Airdrop.InsufficientBalance.selector);
        smallAirdrop.claim();
    }

    // ============================================
    // Deposit Tests
    // ============================================

    function test_Deposit_Success() public {
        uint256 deposit = 5000 * 1e18;
        vm.prank(owner);
        curToken.approve(address(airdrop), deposit);

        uint256 beforeBalance = curToken.balanceOf(address(airdrop));

        vm.prank(owner);
        airdrop.deposit(deposit);
        assertEq(curToken.balanceOf(address(airdrop)), beforeBalance + deposit);
    }

    function test_Deposit_Event() public {
        uint256 depositAmount = 5000 * 1e18;

        vm.prank(owner);
        curToken.approve(address(airdrop), depositAmount);

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit Deposited(depositAmount);
        airdrop.deposit(depositAmount);
    }

    function test_Deposit_ZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert(Airdrop.ZeroAmount.selector);
        airdrop.deposit(0);
    }

    function test_Deposit_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        airdrop.deposit(1000 * 1e18);
    }

    // ============================================
    // View Function Tests
    // ============================================

    function test_GetRemainingTokens_ReturnsCorrectBalance() public view {
        assertEq(airdrop.getRemainingTokens(), TOTAL_AIRDROP);
    }

    function test_GetRemainingTokens_UpdatesAfterClaim() public {
        vm.prank(owner);
        airdrop.addToWhitelist(alice);

        vm.prank(alice);
        airdrop.claim();

        assertEq(airdrop.getRemainingTokens(), TOTAL_AIRDROP - AIRDROP_AMOUNT);
    }

    function test_GetTotalClaimed_ReturnsCorrectAmount() public {
        vm.prank(owner);
        airdrop.addToWhitelist(alice);
        vm.prank(owner);
        airdrop.addToWhitelist(bob);

        vm.prank(alice);
        airdrop.claim();

        assertEq(airdrop.totalClaimed(), AIRDROP_AMOUNT);

        vm.prank(bob);
        airdrop.claim();

        assertEq(airdrop.totalClaimed(), AIRDROP_AMOUNT * 2);
    }

    // ============================================
    // Pause Tests
    // ============================================

    function test_Pause_Success() public {
        vm.prank(owner);
        airdrop.pause();

        assertTrue(airdrop.paused());
    }

    function test_Unpause_Success() public {
        vm.prank(owner);
        airdrop.pause();

        vm.prank(owner);
        airdrop.unpause();

        assertFalse(airdrop.paused());
    }

    function test_Pause_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        airdrop.pause();
    }

    function test_Unpause_NotOwner() public {
        vm.prank(owner);
        airdrop.pause();

        vm.prank(alice);
        vm.expectRevert();
        airdrop.unpause();
    }

    function test_Claim_WhenPaused() public {
        vm.prank(owner);
        airdrop.addToWhitelist(alice);

        vm.prank(owner);
        airdrop.pause();

        vm.prank(alice);
        vm.expectRevert();
        airdrop.claim();
    }

    // ============================================
    // Edge Case Tests
    // ============================================
    function test_Claim_ExactlyAllTokens() public {
        uint256 smallTotal = 5000 * 1e18;
        uint256 exactUsers = smallTotal / AIRDROP_AMOUNT;

        vm.prank(owner);
        Airdrop smallAirdrop = new Airdrop(address(curToken));
        vm.prank(owner);
        curToken.transfer(address(smallAirdrop), smallTotal);

        address[] memory users = new address[](exactUsers);
        for (uint256 i = 0; i < exactUsers; i++) {
            users[i] = makeAddr(string(abi.encodePacked("user", vm.toString(i))));
        }

        vm.prank(owner);
        smallAirdrop.addWhitelist(users);

        for (uint256 i = 0; i < exactUsers; i++) {
            vm.prank(users[i]);
            smallAirdrop.claim();
        }

        assertEq(smallAirdrop.totalClaimed(), smallTotal);
        assertEq(smallAirdrop.getRemainingTokens(), 0);
    }

    function test_Claim_CannotClaimAfterAllTokensDistributed() public {
        uint256 smallTotal = 2000 * 1e18;

        vm.prank(owner);
        Airdrop smallAirdrop = new Airdrop(address(curToken));
        vm.prank(owner);
        curToken.transfer(address(smallAirdrop), smallTotal);

        address[] memory users = new address[](3);
        users[0] = alice;
        users[1] = bob;
        users[2] = charlie;

        vm.prank(owner);
        smallAirdrop.addWhitelist(users);

        vm.prank(alice);
        smallAirdrop.claim();

        vm.prank(bob);
        smallAirdrop.claim();

        assertEq(smallAirdrop.totalClaimed(), smallTotal);
        assertEq(smallAirdrop.getRemainingTokens(), 0);

        vm.prank(charlie);
        vm.expectRevert(Airdrop.InsufficientBalance.selector);
        smallAirdrop.claim();
    }

    function test_Claim_WhitelistedUserCanClaimOnlyOnce() public {
        vm.prank(owner);
        airdrop.addToWhitelist(alice);

        vm.prank(alice);
        airdrop.claim();

        assertEq(airdrop.totalClaimed(), AIRDROP_AMOUNT);
        assertEq(airdrop.totalRecipients(), 1);

        vm.prank(alice);
        vm.expectRevert(Airdrop.AlreadyClaimed.selector);
        airdrop.claim();

        assertEq(airdrop.totalClaimed(), AIRDROP_AMOUNT);
        assertEq(airdrop.totalRecipients(), 1);
    }

    // ============================================
    // Fuzz Tests
    // ============================================
    function testFuzz_AddToWhitelist_AnyAddress(address user) public {
        vm.assume(user != address(0));
        vm.assume(user != owner);

        vm.prank(owner);
        airdrop.addToWhitelist(user);
        assertTrue(airdrop.isWhitelisted(user));
    }

    function testFuzz_AddWhitelist_Batch(uint8 count) public {
        vm.assume(count > 0);
        vm.assume(count <= 100);

        address[] memory users = new address[](count);
        for (uint8 i = 0; i < count; i++) {
            users[i] = makeAddr(string(abi.encodePacked("user", vm.toString(i))));
        }

        vm.prank(owner);
        airdrop.addWhitelist(users);

        for (uint8 i = 0; i < count; i++) {
            assertTrue(airdrop.isWhitelisted(users[i]));
        }
    }

    function testFuzz_Claim_SingleUser(uint8 userIndex) public {
        vm.assume(userIndex < 100);

        address user = makeAddr(string(abi.encodePacked("user", vm.toString(userIndex))));

        vm.prank(owner);
        airdrop.addToWhitelist(user);

        vm.prank(user);
        airdrop.claim();

        assertEq(airdrop.totalClaimed(), AIRDROP_AMOUNT);
        assertEq(airdrop.totalRecipients(), 1);
        assertTrue(airdrop.hasClaimed(user));
    }

    function testFuzz_Claim_MultipleUsers(uint8 userCount) public {
        vm.assume(userCount > 0);
        vm.assume(userCount <= 50);
        vm.assume(userCount * AIRDROP_AMOUNT <= TOTAL_AIRDROP);

        address[] memory users = new address[](userCount);
        for (uint8 i = 0; i < userCount; i++) {
            users[i] = makeAddr(string(abi.encodePacked("user", vm.toString(i))));
        }

        vm.prank(owner);
        airdrop.addWhitelist(users);

        for (uint8 i = 0; i < userCount; i++) {
            vm.prank(users[i]);
            airdrop.claim();
        }

        assertEq(airdrop.totalClaimed(), AIRDROP_AMOUNT * userCount);
        assertEq(airdrop.totalRecipients(), userCount);
    }

    function testFuzz_Deposit(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= 1_000_000 * 1e18);

        vm.prank(owner);
        curToken.approve(address(airdrop), amount);

        uint256 beforeBalance = curToken.balanceOf(address(airdrop));

        vm.prank(owner);
        airdrop.deposit(amount);

        assertEq(curToken.balanceOf(address(airdrop)), beforeBalance + amount);
    }
}
