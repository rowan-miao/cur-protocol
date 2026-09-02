// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/core/CURToken.sol";

contract CURTokenTest is Test {
    CURToken public token;
    
    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    uint256 constant TOTAL_SUPPLY = 100_000_000 * 10 ** 18;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Paused(address account);
    event Unpaused(address account);

    // ============================================
    // Setup
    // ============================================
    function setUp() public {
        vm.prank(owner);
        token = new CURToken();

        assertEq(token.name(), "CURToken");
        assertEq(token.symbol(), "CUR");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), TOTAL_SUPPLY);
        assertEq(token.balanceOf(owner), TOTAL_SUPPLY);
        assertEq(token.owner(), owner);
    }
    

    // ============================================
    // Constructor Tests
    // ============================================
    
    function test_Constructor() public view{
        assertEq(token.name(), "CURToken");
        assertEq(token.symbol(), "CUR");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), TOTAL_SUPPLY);
        assertEq(token.balanceOf(owner), TOTAL_SUPPLY);
        assertEq(token.owner(), owner);
    }

    // ============================================
    // Transfer Tests
    // ============================================
    function test_Transfer() public  {
        uint256 amount = 1000 * 10 ** 18;

        vm.prank(owner);
        token.transfer(alice, amount);

        assertEq(token.balanceOf(owner), TOTAL_SUPPLY - amount);
        assertEq(token.balanceOf(alice), amount);
    }
  
    function test_Transfer_InsufficientBalance() public  {
        uint256 amount = TOTAL_SUPPLY + 1;

        vm.prank(owner);
        vm.expectRevert();
        token.transfer(alice, amount);

    }

    function test_Transfer_ZeroAddress() public  {
        uint256 amount = 6000 * 10 ** 18;

        vm.prank(owner);
        vm.expectRevert();
        token.transfer(address(0), amount);

    }

    function test_Transfer_ZeroAmount() public {
        vm.prank(owner);
        token.transfer(alice, 0);
    
        assertEq(token.balanceOf(owner), TOTAL_SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }


    function test_Transfer_Event() public  {
        uint256 amount = 1000 * 10 ** 18;

        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit Transfer(owner, alice, amount);
        token.transfer(alice, amount);
        
    }


    // ============================================
    // Approve Tests
    // ============================================
    function test_Approve() public {
        uint256 amount = 5000 * 10 ** 18;

        vm.prank(alice);
        token.approve(bob, amount);

        assertEq(token.allowance(alice, bob), amount);
    }

    function test_Approve_Event() public {
        uint256 amount = 5000 * 10 ** 18;

       
        vm.expectEmit(true, true, false, true);
        emit Approval(alice, bob, amount);
        
        vm.prank(alice);
        token.approve(bob, amount);
       
    }

    function test_Approve_ZeroAmount() public {
        vm.prank(alice);
        token.approve(bob, 0);

        assertEq(token.allowance(alice, bob), 0);
    }

    // ============================================
    // TransferFrom Tests
    // ============================================

    function test_TransferFrom() public {
        uint256 amount = 1000 * 10 ** 18;

        vm.prank(owner);
        token.transfer(alice, 4000 * 10 ** 18);

        vm.prank(alice);
        token.approve(bob, amount);
       
        vm.prank(bob);
        token.transferFrom(alice, charlie, amount);

        assertEq(token.balanceOf(alice), 3000 * 10 ** 18);
        assertEq(token.balanceOf(charlie), amount);
        assertEq(token.allowance(alice, bob), 0);

    }

    function test_TransferFrom_InsufficientAllowance() public {
        uint256 amount = 1000 * 10 ** 18;
        vm.prank(owner);
        token.transfer(alice, 4000 * 10 ** 18);

       
        vm.prank(bob);
        vm.expectRevert();
        token.transferFrom(alice, charlie, amount);

    }

    function test_TransferFrom_InsufficientBalance() public {
        uint256 amount = 5000 * 10 ** 18;
        vm.prank(owner);
        token.transfer(alice, 2000 * 10 ** 18);

        vm.prank(alice);
        token.approve(bob, amount);

        vm.prank(bob);
        vm.expectRevert();
        token.transferFrom(alice, charlie, amount);
    }

    function test_TransferFrom_ZeroAddress() public {
        uint256 amount = 5000 * 10 ** 18;
        vm.prank(owner);
        token.transfer(alice, amount);

        vm.prank(alice);
        token.approve(bob, amount);

        vm.prank(bob);
        vm.expectRevert();
        token.transferFrom(alice, address(0), amount);
    }

    // ============================================
    // Burn Tests
    // ============================================
    function test_Burn_success() public {
        uint256 amount = 1000 * 10 ** 18;

        vm.prank(owner);
        token.burn(amount);
        
        assertEq(token.balanceOf(owner), TOTAL_SUPPLY - amount);
        assertEq(token.totalSupply(), TOTAL_SUPPLY - amount);

    }

    function test_Burn_InsufficientBalance() public {
        uint256 amount = TOTAL_SUPPLY + 1;

        vm.prank(owner);
        vm.expectRevert();
        token.burn(amount);

    }

    function test_BurnFrom() public {
        uint256 amount = 1000 * 10 ** 18;

        vm.prank(owner);
        token.transfer(alice, 5000 * 10 ** 18);

        vm.prank(alice);
        token.approve(bob, amount);

        vm.prank(bob);
        token.burnFrom(alice, amount);

        assertEq(token.balanceOf(alice), 4000 * 10 ** 18);
        assertEq(token.totalSupply(), TOTAL_SUPPLY - amount);
    }

    function test_BurnFrom_InsufficientBalance() public {
        uint256 amount = 6000 * 10 ** 18;

        vm.prank(owner);
        token.transfer(alice, 5000 * 10 ** 18);

        vm.prank(alice);
        token.approve(bob, amount);

        vm.prank(bob);
        vm.expectRevert();
        token.burnFrom(alice, amount);
    }

    function test_BurnFrom_InsufficientAllowance() public {
        uint256 amount = 1000 * 10 ** 18;

        vm.prank(owner);
        token.transfer(alice, 5000 * 10 ** 18);

        vm.prank(bob);
        vm.expectRevert();
        token.burnFrom(alice, amount);
    }


    // ============================================
    // Mint Tests
    // ============================================
    function test_Mint_NotOwner() public {
        uint256 amount = 1000 * 10 ** 18;
        vm.prank(alice);

        vm.expectRevert();
        token.mint(bob, amount);
        
    }

    function test_Mint_ZeroAddress() public {
        uint256 amount = 1000 * 10 ** 18;
        vm.prank(owner);
        vm.expectRevert(CURToken.ZeroAddress.selector);
        token.mint(address(0), amount);

    }

    function test_Mint_ZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert(CURToken.InvalidAmount.selector);
        token.mint(alice, 0);

    }

     function test_Mint_ExceedsTotalSupply() public {
        uint256 remaining = TOTAL_SUPPLY - token.totalSupply();
        uint256 mintAmount = remaining + 1;

        vm.prank(owner);
        vm.expectRevert(CURToken.ExceedsTotalSupply.selector);
        token.mint(alice, mintAmount);
    }

    // ============================================
    // Pause Tests
    // ============================================
    function test_Pause() public {
        vm.prank(owner);
        token.pause();

        assertTrue(token.paused());

    } 

    function test_Unpause() public {
        vm.prank(owner);
        token.pause();

        vm.prank(owner);
        token.unpause();

        assertFalse(token.paused());
 
    }

    function test_Transfer_WhenPaused() public {
        vm.prank(owner);
        token.pause();

        vm.prank(owner);
        vm.expectRevert();
        token.transfer(alice, 1000 * 10 ** 18);

    }

    function test_Mint_WhenPaused() public {
        vm.prank(owner);
        token.pause();

        vm.prank(owner);
        vm.expectRevert();
        token.mint(alice, 1000 * 10 ** 18);

    }

    function test_Burn_WhenPaused() public {
        vm.prank(owner);
        token.pause();

        vm.prank(owner);
        vm.expectRevert();
        token.burn(1000 * 10 ** 18);

    }

    function test_Pause_Event() public {
        vm.expectEmit(true, false, false, true);
        emit Paused(owner);

        vm.prank(owner);
        token.pause();
        
    }

     function test_Unpause_Event() public {
        vm.prank(owner);
        token.pause();
        
        vm.expectEmit(true, false, false, true);
        emit Unpaused(owner);

        vm.prank(owner);
        token.unpause();
        
    }

    function test_Pause_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        token.pause();
    }

    function test_Unpause_NotOwner() public {
        vm.prank(owner);
        token.pause();
    
        vm.prank(alice);
        vm.expectRevert();
        token.unpause();
    }

    // ============================================
    // Ownership Tests
    // ============================================
    function test_TransferOwnership() public {
        vm.prank(owner);
        token.transferOwnership(alice);
    
        assertEq(token.owner(), alice);
    }

    function test_TransferOwnership_NotOwner() public {
        vm.prank(alice);
        
        vm.expectRevert();
        token.transferOwnership(bob);
    }

    function test_TransferOwnership_ZeroAddress() public {
        vm.prank(owner);

        vm.expectRevert(); 
        token.transferOwnership(address(0));

    }

    
    // ============================================
    // Edge Cases Tests
    // ============================================

    function test_EdgeCase_TransferMaxAmount() public {
        uint256 maxAmount = token.balanceOf(owner);

        vm.prank(owner);
        token.transfer(alice, maxAmount);

        assertEq(token.balanceOf(owner), 0);
        assertEq(token.balanceOf(alice), maxAmount);
    }

    function test_EdgeCase_ApproveMaxAmount() public {
        uint256 maxAmount = type(uint256).max;

        vm.prank(alice);
        token.approve(bob, maxAmount);

        assertEq(token.allowance(alice, bob), maxAmount);
    }


    // ============================================
    // Fuzz Tests
    // ============================================

    function test_Fuzz_Burn(uint256 amount) public {
        amount = bound(amount, 1, TOTAL_SUPPLY);

        vm.prank(owner);
        token.burn(amount);
        
        assertEq(token.balanceOf(owner), TOTAL_SUPPLY - amount);
        assertEq(token.totalSupply(), TOTAL_SUPPLY - amount);

    }
   

    function test_Fuzz_Transfer(uint256 amount) public {
        amount = bound(amount, 1, TOTAL_SUPPLY);
        vm.prank(owner);
        token.transfer(alice, amount);

        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(owner), TOTAL_SUPPLY - amount);

    }

    function test_Fuzz_Approve(uint256 amount) public{
        amount = bound(amount, 1, TOTAL_SUPPLY);

        vm.prank(alice);
        token.approve(bob, amount);

        assertEq(token.allowance(alice, bob), amount);

    }

    function test_Fuzz_transferFrom(uint256 amount, uint256 aliceBalance) public{
        aliceBalance = bound(aliceBalance, 1, TOTAL_SUPPLY);
        amount = bound(amount, 1, aliceBalance);

        vm.prank(owner);
        token.transfer(alice, aliceBalance);

        vm.prank(alice);
        token.approve(bob, amount);

        vm.prank(bob);
        token.transferFrom(alice, charlie, amount);

        assertEq(token.balanceOf(charlie), amount);
        assertEq(token.balanceOf(owner), TOTAL_SUPPLY - aliceBalance);
        assertEq(token.balanceOf(alice), aliceBalance - amount);
        assertEq(token.allowance(alice, bob), 0);
    }

}

   
