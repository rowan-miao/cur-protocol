// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/core/sCUR.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/core/CURStaking.sol";
import "../src/modules/IncentiveGauge.sol";

// Mock CUR token for testing
contract MockCUR is ERC20 {
    constructor() ERC20("Mock CUR", "CUR") {
        _mint(msg.sender, 100_000_000 * 1e18);
    }
}


contract MockIncentiveGauge {

}

contract MockveCURLock {

}

contract MockRevenueRebatePool {

}

contract sCURTest is Test {
sCUR public sCur;
MockCUR public mCur;
CURStaking public staking;
MockIncentiveGauge public mockGauge;
MockveCURLock public mockVeLock;
MockRevenueRebatePool public revenuePool;

address public owner = makeAddr("owner");
address public minter = makeAddr("minter"); 
address public newGauge = makeAddr("newGauge");
address public alice = makeAddr("alice");
address public bob = makeAddr("bob");
address public charlie = makeAddr("charlie");

uint256 constant INITIAL_EXCHANGE_RATE = 1e18;
uint256 constant PRECISION = 1e18;
uint256 public constant INITIAL_SUPPLY = 0;

// Events
event Mint(address indexed to, uint256 CURAmount, uint256 sCURAmount);
event Redeem(address indexed from, uint256 CURAmount, uint256 sCURAmount);
event UpdateExchangeRate(uint256 oldRate, uint256 newRate);
event MinterAdded(address indexed minter);
event MinterRemoved(address indexed minter);
event IncentiveGaugeUpdated(address indexed oldGauge, address indexed newGauge);
 
// ============================================
// Setup
// ============================================
function setUp() public {
    vm.startPrank(owner);

    mCur = new MockCUR();

    sCur = new sCUR(address(mCur));

    mockGauge = new MockIncentiveGauge();
    mockVeLock = new MockveCURLock();
    revenuePool = new MockRevenueRebatePool();

    staking = new CURStaking(address(mCur), address(sCur), address(mockGauge), address(mockVeLock), address(revenuePool));

    sCur.setIncentiveGauge(address(mockGauge));

    sCur.addMinter(minter);
    sCur.addMinter(address(staking));

    vm.stopPrank();

}

// ============================================
// Constructor Tests
// ============================================
function test_Constructor() public view {
    assertEq(sCur.name(), "Staked CUR");
    assertEq(sCur.symbol(), "sCUR");
    assertEq(sCur.decimals(), 18);
    assertEq(sCur.currentExchangeRate(), INITIAL_EXCHANGE_RATE);
    assertEq(sCur.totalUnderlying(), 0);
    assertEq(sCur.totalSupply(), INITIAL_SUPPLY);
    assertEq(address(sCur.CURToken()), address(mCur));
    assertEq(sCur.owner(), owner);
}

function test_Constructor_ZeroAddress() public {
    vm.prank(owner);
    vm.expectRevert(sCUR.ZeroAddress.selector);
    new sCUR(address(0));
}

// ============================================
// Minter Management Tests
// ============================================

function test_AddMinter() public {
    address newMinter = makeAddr("newMinter");
    
    vm.prank(owner);
    vm.expectEmit(true, false, false, true);
    emit MinterAdded(newMinter);
    sCur.addMinter(newMinter);
    
    assertTrue(sCur.minters(newMinter));
}

function test_AddMinter_ZeroAddress() public {
    vm.prank(owner);
    vm.expectRevert(sCUR.ZeroAddress.selector);
    sCur.addMinter(address(0));
}

function test_AddMinter_NotOwner() public {
    vm.prank(alice);
    vm.expectRevert();
    sCur.addMinter(bob);
}

function test_RemoveMinter() public {
    vm.prank(owner);
    sCur.removeMinter(minter);
    
    assertFalse(sCur.minters(minter));
}

function test_RemoveMinter_Unauthorized() public {
    address notMinter = makeAddr("notMinter");
    
    vm.prank(owner);
    vm.expectRevert(sCUR.Unauthorized.selector);
    sCur.removeMinter(notMinter);
}

// ============================================
// Mint Tests
// ============================================
function test_Mint_success() public {
    uint256 curAmount = 1000 * 1e18;
    
    vm.prank(minter);
    uint256 sCURAmount = sCur.mint(alice, curAmount);
    
    uint256 expectedSCUR = (curAmount * PRECISION) / INITIAL_EXCHANGE_RATE;
    assertEq(sCURAmount, expectedSCUR);
    assertEq(sCur.balanceOf(alice), expectedSCUR);
    assertEq(sCur.totalUnderlying(), curAmount);
    assertEq(sCur.totalSupply(), expectedSCUR);
}

function test_Mint_ZeroAddress() public {
    vm.prank(minter);
    vm.expectRevert(sCUR.ZeroAddress.selector);
    sCur.mint(address(0), 1000 * 1e18);
}

function test_Mint_ZeroAmount() public {
    vm.prank(minter);
    vm.expectRevert(sCUR.ZeroAmount.selector);
    sCur.mint(alice, 0);
}

function test_Mint_NotMinter() public {
    vm.prank(alice);
    vm.expectRevert(sCUR.Unauthorized.selector);
    sCur.mint(bob, 1000 * 1e18);
}

function test_Mint_Event() public {
    uint256 curAmount = 1000 * 1e18;
    
    vm.prank(minter);
    vm.expectEmit(true, false, false, true);
    emit Mint(alice, curAmount, (curAmount * PRECISION) / INITIAL_EXCHANGE_RATE);
    sCur.mint(alice, curAmount);
}

// ============================================
// Redeem Tests
// ============================================
function test_Redeem_Success() public {
    uint256 curAmount = 1000 * 1e18;

    vm.prank(minter);
    uint256 sCURAmount = sCur.mint(alice, curAmount);

    vm.prank(owner);
    mCur.transfer(address(sCur), curAmount);

    vm.prank(minter);
    uint256 returnedCUR = sCur.redeem(alice, sCURAmount);

    assertEq(returnedCUR, curAmount);
    assertEq(sCur.balanceOf(alice), 0);
    assertEq(sCur.totalUnderlying(), 0);

}


function test_Redeem_ZeroAddress() public {
    uint256 amount = 1000 * 1e18;

    vm.prank(minter);
    sCur.mint(alice, amount);

    vm.prank(minter);
    vm.expectRevert(sCUR.ZeroAddress.selector);
    sCur.redeem(address(0), amount);
}

function test_Redeem_ZeroAmount() public {
    uint256 amount = 1000 * 1e18;

    vm.prank(minter);
    sCur.mint(alice, amount);

    vm.prank(minter);
    vm.expectRevert(sCUR.ZeroAmount.selector);
    sCur.redeem(alice, 0);
}

function test_Redeem_InsufficientSCURBalance() public {
    vm.prank(minter);
    sCur.mint(alice, 100 * 1e18);
    
    vm.prank(minter);
    vm.expectRevert(sCUR.InsufficientSCURBalance.selector);
    sCur.redeem(alice, 200 * 1e18);
}

function test_Redeem_Unauthorized() public {
    vm.prank(minter);
    sCur.mint(alice, 1000 * 1e18);
    
    vm.prank(alice);
    vm.expectRevert(sCUR.Unauthorized.selector);
    sCur.redeem(alice, 100 * 1e18);
}

function test_Redeem_Event() public {
    uint256 sCURAmount = 1000 * 1e18;
    
    vm.prank(minter);
    sCur.mint(alice, sCURAmount);

    uint256 exchangeRate = sCur.getExchangeRate();
    uint256 expectedCUR = (sCURAmount * exchangeRate) / 1e18;

    vm.expectEmit(true, true, false, true);
    emit Redeem(alice, expectedCUR, sCURAmount);
    vm.prank(minter);
    sCur.redeem(alice, sCURAmount);
}

// ============================================
// burnGauge Tests
// ============================================

function test_burnGauge_Success() public {
    uint256 mintAmount = 1000 * 1e18;
    uint256 burnAmount = 500 * 1e18;

    vm.prank(minter);
    sCur.mint(address(mockGauge), mintAmount);
    
    uint256 beforeSCURBalance = sCur.balanceOf(address(mockGauge));
    uint256 beforeTotalSupply = sCur.totalSupply();
    uint256 beforeTotalUnderlying = sCur.totalUnderlying();

    uint256 expectedCUR = burnAmount * sCur.getExchangeRate() / PRECISION;
    
    vm.prank(address(mockGauge));
    uint256 curAmount = sCur.burnGauge(burnAmount);

  
    assertEq(curAmount, expectedCUR);
    assertEq(sCur.balanceOf(address(mockGauge)), beforeSCURBalance - burnAmount);
    assertEq(sCur.totalSupply(), beforeTotalSupply - burnAmount);
    assertEq(sCur.totalUnderlying(), beforeTotalUnderlying - expectedCUR);
}

function test_burnGauge_ZeroAmount() public {
    vm.prank(address(mockGauge));
    vm.expectRevert(sCUR.ZeroAmount.selector);
    sCur.burnGauge(0);
}

function test_burnGauge_Unauthorized() public {
    vm.prank(alice);
    vm.expectRevert(sCUR.Unauthorized.selector);
    sCur.burnGauge(100 * 1e18);
}

function test_burnGauge_InsufficientBalance() public {
    uint256 sCURAmount = 2000 * 1e18; 
    
    vm.prank(address(mockGauge));
    vm.expectRevert(); 
    sCur.burnGauge(sCURAmount);
}

function test_burnGauge_UpdatesTotalUnderlyingCorrectly() public {
    uint256 mintAmount = 1000 * 1e18;
    uint256 sCURAmount = 300 * 1e18;

    vm.prank(minter);
    sCur.mint(address(mockGauge), mintAmount);
    uint256 exchangeRate = sCur.getExchangeRate();
    uint256 expectedCUR = (sCURAmount * exchangeRate) / PRECISION;
    
    uint256 beforeTotalUnderlying = sCur.totalUnderlying();
    
    vm.prank(address(mockGauge));
    uint256 curAmount = sCur.burnGauge(sCURAmount);
    
    assertEq(curAmount, expectedCUR);
    assertEq(sCur.totalUnderlying(), beforeTotalUnderlying - expectedCUR);
}


// ============================================
// Update Exchange Rate Tests
// ============================================
function test_UpdateExchangeRate() public {
    vm.prank(minter);
    sCur.mint(alice, 1000 * 1e18);

    uint256 additionalCUR = 100 * 1e18;
    
    vm.prank(minter);
    uint256 newRate = sCur.updateExchangeRate(additionalCUR);
    
    uint256 expectedRate = ((1000 * 1e18 + additionalCUR) * PRECISION) / (1000 * 1e18);
    assertEq(newRate, expectedRate);
    assertEq(sCur.currentExchangeRate(), expectedRate);
    assertEq(sCur.totalUnderlying(), 1000 * 1e18 + additionalCUR);
}

function test_UpdateExchangeRate_ZeroAmount() public {
    vm.prank(minter);
    vm.expectRevert(sCUR.ZeroAmount.selector);
    sCur.updateExchangeRate(0);
}

function test_UpdateExchangeRate_NoSupply() public {
    uint256 oldRate = sCur.currentExchangeRate();
    
    vm.prank(minter);
    uint256 newRate = sCur.updateExchangeRate(100 * 1e18);
    
    assertEq(newRate, oldRate);
    assertEq(sCur.totalUnderlying(), 100 * 1e18);
}

function test_UpdateExchangeRate_NotMinter() public {
    vm.prank(alice);
    vm.expectRevert(sCUR.Unauthorized.selector);
    sCur.updateExchangeRate(100 * 1e18);
}

function test_UpdateExchangeRate_Event() public {
    vm.prank(minter);
    sCur.mint(alice, 1000 * 1e18);
    
    vm.prank(minter);
    vm.expectEmit(true, true, false, true);
    emit UpdateExchangeRate(INITIAL_EXCHANGE_RATE, (1100 * 1e18 * PRECISION) / (1000 * 1e18));
    sCur.updateExchangeRate(100 * 1e18);
}

// ============================================
// Emergency Burn Tests
// ============================================

function test_emergencyRedeem_Success() public {
    uint256 amount = 1000 * 1e18;
    
    vm.prank(minter);
    sCur.mint(alice, amount);
    
    vm.prank(owner);
    sCur.pause();

    vm.prank(minter);
    uint256 redeemed = sCur.emergencyRedeem(alice, amount);
    
    assertEq(sCur.balanceOf(alice), 0);
    assertEq(sCur.totalSupply(), 0);
    assertEq(sCur.totalUnderlying(), 0);
    assertEq(redeemed, amount);

   
}


function test_emergencyRedeem_OnlyMinter() public {
    uint256 amount = 1000 * 1e18;
    
    vm.prank(minter);
    sCur.mint(alice, amount);

    vm.prank(owner);
    sCur.pause();

    vm.expectRevert();

    vm.prank(alice);
    sCur.emergencyRedeem(alice, amount);
}


function test_emergencyRedeem_ZeroAmount() public {
    vm.prank(owner);
    sCur.pause();

    vm.expectRevert(sCUR.ZeroAmount.selector);

    vm.prank(minter);
    sCur.emergencyRedeem(alice, 0);

}


function test_emergencyRedeem_ZeroAddress() public {
    vm.prank(minter);
    sCur.mint(alice, 1000 * 1e18);
    
    vm.prank(owner);
    sCur.pause();

    vm.expectRevert(sCUR.ZeroAddress.selector);

    vm.prank(minter);
    sCur.emergencyRedeem(address(0), 1000 * 1e18);
}

function test_emergencyRedeem_InsufficientSCURBalance() public {
    vm.prank(owner);
    sCur.pause();

    vm.expectRevert(sCUR.InsufficientSCURBalance.selector);
    
    vm.prank(minter);
    sCur.emergencyRedeem(alice, 100 * 1e18);
}

// ============================================
// View Function Tests
// ============================================
function test_GetExchangeRate() public view {
    assertEq(sCur.getExchangeRate(), INITIAL_EXCHANGE_RATE);
}


// ============================================
// setIncentiveGauge Tests
// ============================================

function test_setIncentiveGauge_Success() public {
    vm.prank(owner);
    sCur.setIncentiveGauge(newGauge);
    
    assertEq(address(sCur.incentiveGauge()), newGauge);
}

function test_setIncentiveGauge_EmitsEvent() public {
    address oldGauge = address(sCur.incentiveGauge());

    vm.expectEmit(true, true, false, true);
    emit IncentiveGaugeUpdated(oldGauge, newGauge);

    vm.prank(owner);
    sCur.setIncentiveGauge(newGauge);
}

function test_setIncentiveGauge_RevertsWhenZeroAddress() public {
    vm.prank(owner);
    vm.expectRevert(sCUR.ZeroAddress.selector);
    sCur.setIncentiveGauge(address(0));
}

function test_setIncentiveGauge_RevertsWhenNotOwner() public {
    vm.prank(alice);
    vm.expectRevert();
    sCur.setIncentiveGauge(newGauge);
}

function test_setIncentiveGauge_OnlyOwnerCanUpdate() public {
    vm.prank(owner);
    sCur.setIncentiveGauge(newGauge);
    assertEq(address(sCur.incentiveGauge()), newGauge);
    
    address anotherGauge = makeAddr("anotherGauge");
    vm.prank(alice);
    vm.expectRevert();
    sCur.setIncentiveGauge(anotherGauge);

    assertEq(address(sCur.incentiveGauge()), newGauge);
}

function test_setIncentiveGauge_CanUpdateMultipleTimes() public {
    address gauge1 = makeAddr("gauge1");
    address gauge2 = makeAddr("gauge2");
    
    vm.prank(owner);
    sCur.setIncentiveGauge(gauge1);
    assertEq(address(sCur.incentiveGauge()), gauge1);
    
    vm.prank(owner);
    sCur.setIncentiveGauge(gauge2);
    assertEq(address(sCur.incentiveGauge()), gauge2);
}


// ============================================
// Pause Tests
// ============================================
function test_Pause_Success() public {
    vm.prank(owner);
    sCur.pause();
    
    assertTrue(sCur.paused());
}

function test_Unpause_Success() public {
    vm.prank(owner);
    sCur.pause();
    
    vm.prank(owner);
    sCur.unpause();
    
    assertFalse(sCur.paused());
}

function test_Pause_NotOwner() public {
    vm.prank(alice);
    vm.expectRevert();
    sCur.pause();
}

function test_Mint_WhenPaused() public {
    vm.prank(owner);
    sCur.pause();
    
    vm.prank(minter);
    vm.expectRevert();
    sCur.mint(alice, 1000 * 1e18);
}


// ============================================
// Edge Cases Tests
// ============================================

function test_EdgeCase_MintAndRedeemMultiple() public {
    for(uint256 i = 0; i < 5; i++) {
        uint256 amount = 100 * 1e18;
             
        vm.prank(minter);
        uint256 sCURAmount = sCur.mint(alice, amount);
        
        vm.prank(owner);
        mCur.transfer(address(sCur), amount);
        
        vm.prank(minter);
        sCur.redeem(alice, sCURAmount);
    }
    
    assertEq(sCur.balanceOf(alice), 0);
    assertEq(sCur.totalUnderlying(), 0);
}


// ============================================
// Fuzz Tests
// ============================================
function test_Fuzz_Mint(uint256 curAmount) public {
    curAmount = bound(curAmount, 1, 1_000_000 * 1e18);
    
    vm.prank(minter);
    uint256 sCURAmount = sCur.mint(alice, curAmount);
    
    uint256 expectedSCUR = (curAmount * PRECISION) / INITIAL_EXCHANGE_RATE;
    assertEq(sCURAmount, expectedSCUR);
    assertEq(sCur.balanceOf(alice), expectedSCUR);
    assertEq(sCur.totalUnderlying(), curAmount);
}

function test_Fuzz_Redeem(uint256 curAmount, uint256 redeemAmount) public {
    curAmount = bound(curAmount, 1e18, 1_000_00 * 1e18);
    redeemAmount = bound(redeemAmount, 1e18, curAmount);

    vm.prank(minter);
    uint256 sCURAmount = sCur.mint(alice, curAmount);

    uint256 redeemSCUR = (sCURAmount * redeemAmount) / curAmount;

    vm.prank(minter);
    uint256 returnedCUR = sCur.redeem(alice, redeemSCUR);

    uint256 expectedCUR = (redeemSCUR * PRECISION) / INITIAL_EXCHANGE_RATE;
    assertApproxEqAbs(returnedCUR, expectedCUR, 10);
}

function test_Fuzz_UpdateExchangeRate(uint256 additionalCUR, uint256 mintAmount) public {
    mintAmount = bound(mintAmount, 1, 1_000_000 * 1e18);
    additionalCUR = bound(additionalCUR, 1, 1_000_000 * 1e18);
    
    vm.prank(minter);
    sCur.mint(alice, mintAmount);
    
    uint256 oldRate = sCur.currentExchangeRate();
    
    vm.prank(minter);
    uint256 newRate = sCur.updateExchangeRate(additionalCUR);
    
    assertGe(newRate, oldRate);
    assertEq(sCur.totalUnderlying(), mintAmount + additionalCUR);
}

function test_Fuzz_EmergencyBurn(uint256 mintAmount, uint256 burnAmount) public {
    mintAmount = bound(mintAmount, 1, 1_000_000 * 1e18);
    burnAmount = bound(burnAmount, 1, mintAmount);
    
    vm.prank(minter);
    sCur.mint(alice, mintAmount);
    
    vm.prank(owner);
    sCur.pause();

    uint256 beforeBalance = sCur.balanceOf(alice);
    
    vm.prank(minter);
    sCur.emergencyRedeem(alice, burnAmount);
    
    assertEq(sCur.balanceOf(alice), beforeBalance - burnAmount);
    assertEq(sCur.totalSupply(), beforeBalance - burnAmount);
}

}

