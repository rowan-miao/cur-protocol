// test/veCURLock.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/core/CURToken.sol";
import "../src/core/sCUR.sol";
import "../src/core/CURStaking.sol";
import "../src/modules/veCURLock.sol";
import "../src/modules/NFTChecker.sol";

// Mock IncentiveGauge for testing
contract MockIncentiveGauge {
    address public veLock;

    address public lastCaller;
    address public lastUser;
    uint256 public lastPenalty;

    error Unauthorized();

    modifier onlyVeLock(){
        if(msg.sender != veLock) revert Unauthorized();
        _;
    }

    function setVeLock(address _veLock) external {
        veLock = _veLock;
    }

    function executeLock(address user) external onlyVeLock{
        lastCaller = msg.sender;
        lastUser = user;
    
    }
    
    function executeUnlock(address user) external onlyVeLock{
        lastCaller = msg.sender;
        lastUser = user;
      
    }
    
    function executeEarlyUnlock(address user, uint256 penalty) external onlyVeLock{
        lastCaller = msg.sender;
        lastUser = user;
        lastPenalty = penalty;
    }

}

// Mock NFTChecker for testing
contract MockNFTChecker {
    struct UserBinding{
        address nftContract;
        uint256 tokenId;
        uint8 tier;
        uint256 bindTime;
        bool isBound;
    }

    mapping(address => UserBinding) public userBindings;
    mapping(address => uint8) public contractTiers;


    function setUserBinding(address user, uint8 tier) external{
        address nft = address(1);

        userBindings[user] = UserBinding({
            nftContract : nft,
            tokenId : 1,
            tier : tier,
            bindTime : block.timestamp,
            isBound : true
        });
        contractTiers[nft] = tier;

    }
    
    function verifyOwnership(address user, address nftContract, uint256 tokenId) external view returns (bool) {
        return userBindings[user].isBound;
    }
    
    function getNFTTier(address nftContract) external view returns(uint8) {
        return contractTiers[nftContract];

    }

    function unbindNFT(address user) external{
        delete userBindings[user];
    }
}

// Mock CURStaking for testing
contract MockCURStaking {
    mapping(address => uint256) public depositedGauge;
    
    function setUserGaugeBalance(address user, uint256 amount) external {
        depositedGauge[user] += amount;
    }
    
    function getUserInfo(address user) external view returns (uint256, uint256) {
        return (0, depositedGauge[user]);
    }
    
}

contract veCURLockTest is Test {
    veCURLock public veLock;
    CURToken public curToken;
    sCUR public sCURToken;
    MockCURStaking public curStake;
    MockNFTChecker public nftChecker;
    MockIncentiveGauge public incentiveGauge;
    
    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    
    uint256 public constant PRECISION = 1e18;
    uint256 public constant PENALTY_RATE = 5000;
    
    // Lock durations
    uint256 public constant DURATION_30 = 30 days;
    uint256 public constant DURATION_90 = 90 days;
    uint256 public constant DURATION_180 = 180 days;
    uint256 public constant DURATION_365 = 365 days;
    uint256 public constant DURATION_730 = 730 days;
    
    // Bonus factors (1e18 = 1.0x)
    uint256 public constant BONUS_30 = 1.15e18;
    uint256 public constant BONUS_90 = 1.35e18;
    uint256 public constant BONUS_180 = 1.65e18;
    uint256 public constant BONUS_365 = 2.00e18;
    uint256 public constant BONUS_730 = 2.50e18;
    
    // Events
    event Locked(address indexed user, uint256 duration, uint256 bonusFactor, uint256 endTime);
    event Unlocked(address indexed user, uint256 amount);
    event EarlyUnlocked(address indexed user, uint256 amount, uint256 penalty);
    event NFTBound(address indexed user, address indexed nftContract, uint256 tokenId, uint8 tier);
    event NFTUnbound(address indexed user, address indexed nftContract, uint256 tokenId, uint8 tier);
    event NFTCheckerUpdated(address indexed newChecker);
    event IncentiveGaugeUpdated(address indexed newGauge);

    // ============================================
    // Setup
    // ============================================
    function setUp() public {
        vm.startPrank(owner);
        
        curToken = new CURToken();
        sCURToken = new sCUR(address(curToken));
        curStake = new MockCURStaking();
        nftChecker = new MockNFTChecker();
        incentiveGauge = new MockIncentiveGauge();
        
        veLock = new veCURLock(
            address(sCURToken),
            address(curStake),
            address(nftChecker),
            address(incentiveGauge)
        );

        incentiveGauge.setVeLock(address(veLock));

        curToken.transfer(alice, 10000 * 1e18);

        sCURToken.addMinter(address(this));

        vm.stopPrank();

        sCURToken.mint(alice, 5000 * 1e18);

        vm.prank(alice);
        sCURToken.approve(address(veLock), type(uint256).max);
    }
    
    // ============================================
    // Constructor Tests
    // ============================================
    
    function test_Constructor_SetsCorrectState() public view {
        assertEq(address(veLock.sCURToken()), address(sCURToken));
        assertEq(address(veLock.curStake()), address(curStake));
        assertEq(address(veLock.nftChecker()), address(nftChecker));
        assertEq(address(veLock.incentiveGauge()), address(incentiveGauge));
        assertEq(veLock.owner(), owner);
        assertEq(veLock.totalLocked(), 0);
    }
    
    function test_Constructor_SCURTokenZero() public {
        vm.prank(owner);
        vm.expectRevert(veCURLock.ZeroAddress.selector);
        new veCURLock(address(0), address(curStake), address(nftChecker), address(incentiveGauge));
    }
    
    function test_Constructor_CurStakeZero() public {
        vm.prank(owner);
        vm.expectRevert(veCURLock.ZeroAddress.selector);
        new veCURLock(address(sCURToken), address(0), address(nftChecker), address(incentiveGauge));
    }
    
    function test_Constructor_NFTCheckerZero() public {
        vm.prank(owner);
        vm.expectRevert(veCURLock.ZeroAddress.selector);
        new veCURLock(address(sCURToken), address(curStake), address(0), address(incentiveGauge));
    }
    
    function test_Constructor_IncentiveGaugeZero() public {
        vm.prank(owner);
        vm.expectRevert(veCURLock.ZeroAddress.selector);
        new veCURLock(address(sCURToken), address(curStake), address(nftChecker), address(0));
    }
    
    // ============================================
    // Duration Validation Tests
    // ============================================
    
    function test_IsValidDuration_ReturnsTrueForValidDurations() public view {
        assertTrue(veLock.isValidDuration(DURATION_30));
        assertTrue(veLock.isValidDuration(DURATION_90));
        assertTrue(veLock.isValidDuration(DURATION_180));
        assertTrue(veLock.isValidDuration(DURATION_365));
        assertTrue(veLock.isValidDuration(DURATION_730));
    }
    
    function test_IsValidDuration_ReturnsFalseForInvalidDurations() public view {
        assertFalse(veLock.isValidDuration(1 days));
        assertFalse(veLock.isValidDuration(60 days));
        assertFalse(veLock.isValidDuration(3650 days));
    }
    
    // ============================================
    // Bonus Calculation Tests
    // ============================================
    
    function test_GetBonusByDuration_ReturnsCorrectBonus() public view{
        assertEq(veLock.getBonusByDuration(DURATION_30), BONUS_30);
        assertEq(veLock.getBonusByDuration(DURATION_90), BONUS_90);
        assertEq(veLock.getBonusByDuration(DURATION_180), BONUS_180);
        assertEq(veLock.getBonusByDuration(DURATION_365), BONUS_365);
        assertEq(veLock.getBonusByDuration(DURATION_730), BONUS_730);
    }
    
    function test_GetBonusByDuration_InvalidDuration() public {
        vm.expectRevert(veCURLock.InvalidDuration.selector);
        veLock.getBonusByDuration(1 days);
    }
    
    // ============================================
    // Lock Tests
    // ============================================
    
    function test_Lock_30Days_Success() public {
        uint256 gaugeBalance = 1000 * 1e18;
        curStake.setUserGaugeBalance(alice, gaugeBalance);
        
        vm.prank(alice);
        veLock.lock(DURATION_30);
        
        (uint256 amount, uint256 startTime, uint256 endTime, uint256 duration, uint256 bonusFactor, bool isLocked) = veLock.locks(alice);
        
        assertEq(amount, gaugeBalance);
        assertEq(duration, DURATION_30);
        assertEq(bonusFactor, BONUS_30);
        assertTrue(isLocked);
        assertEq(endTime, startTime + DURATION_30);
        assertEq(veLock.totalLocked(), gaugeBalance);
        assertEq(incentiveGauge.lastUser(), alice);
    }
    
    function test_Lock_90Days_Success() public {
        uint256 gaugeBalance = 1000 * 1e18;
        curStake.setUserGaugeBalance(alice, gaugeBalance);
        
        vm.prank(alice);
        veLock.lock(DURATION_90);
        
        (,,, uint256 duration, uint256 bonusFactor,) = veLock.locks(alice);
        assertEq(duration, DURATION_90);
        assertEq(bonusFactor, BONUS_90);
    }
    
    function test_Lock_180Days_Success() public {
        uint256 gaugeBalance = 1000 * 1e18;
        curStake.setUserGaugeBalance(alice, gaugeBalance);
        
        vm.prank(alice);
        veLock.lock(DURATION_180);
        
        (,,, uint256 duration, uint256 bonusFactor,) = veLock.locks(alice);
        assertEq(duration, DURATION_180);
        assertEq(bonusFactor, BONUS_180);
    }
    
    function test_Lock_365Days_WithNFTSuccess() public {
        // Give alice NFT permission for 365 days
        nftChecker.setUserBinding(alice, 1);

        address nftContract = address(1);
        uint256 tokenId = 1;
        vm.prank(alice);
        veLock.bindNFT(nftContract, tokenId);
        
        uint256 gaugeBalance = 1000 * 1e18;
        curStake.setUserGaugeBalance(alice, gaugeBalance);
        
        vm.prank(alice);
        veLock.lock(DURATION_365);
        
        (,,, uint256 duration, uint256 bonusFactor,) = veLock.locks(alice);
        assertEq(duration, DURATION_365);
        assertEq(bonusFactor, BONUS_365);
    }
    
    function test_Lock_730Days_WithNFTSuccess() public {
        nftChecker.setUserBinding(alice, 2);

        address nftContract = address(1);
        uint256 tokenId = 1;
        vm.prank(alice);
        veLock.bindNFT(nftContract, tokenId);
        
        uint256 gaugeBalance = 1000 * 1e18;
        curStake.setUserGaugeBalance(alice, gaugeBalance);
        
        vm.prank(alice);
        veLock.lock(DURATION_730);
        
        (,,, uint256 duration, uint256 bonusFactor,) = veLock.locks(alice);
        assertEq(duration, DURATION_730);
        assertEq(bonusFactor, BONUS_730);
    }
    
    function test_Lock_InvalidDuration() public {
        vm.prank(alice);
        vm.expectRevert(veCURLock.InvalidDuration.selector);
        veLock.lock(1 days);
    }
    
    function test_Lock_DurationExceedsPermission() public {
        // alice has no NFT, max is 180 days
        uint256 gaugeBalance = 1000 * 1e18;
        curStake.setUserGaugeBalance(alice, gaugeBalance);
        
        vm.prank(alice);
        vm.expectRevert(veCURLock.DurationExceedsPermission.selector);
        veLock.lock(DURATION_365);
    }
    
    function test_Lock_AlreadyLocked() public {
        uint256 gaugeBalance = 1000 * 1e18;
        curStake.setUserGaugeBalance(alice, gaugeBalance);
        
        vm.prank(alice);
        veLock.lock(DURATION_30);
        
        vm.prank(alice);
        vm.expectRevert(veCURLock.AlreadyLocked.selector);
        veLock.lock(DURATION_90);
    }
    
    function test_Lock_ZeroGaugeBalance() public {
        curStake.setUserGaugeBalance(alice, 0);
        
        vm.prank(alice);
        vm.expectRevert(veCURLock.ZeroSCUR.selector);
        veLock.lock(DURATION_30);
    }
    
    function test_Lock_Event() public {
        uint256 gaugeBalance = 1000 * 1e18;
        curStake.setUserGaugeBalance(alice, gaugeBalance);
        
        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit Locked(alice, DURATION_30, BONUS_30, block.timestamp + DURATION_30);
        veLock.lock(DURATION_30);
    }
    
    // ============================================
    // Unlock Tests
    // ============================================
    
    function test_Unlock_AfterExpiry_Success() public {
        uint256 gaugeBalance = 1000 * 1e18;
        curStake.setUserGaugeBalance(alice, gaugeBalance);
        
        vm.prank(alice);
        veLock.lock(DURATION_30);
        
        // Warp past expiry
        vm.warp(block.timestamp + DURATION_30 + 1);
        
        vm.prank(alice);
        veLock.unlock();
        
        (,,,,, bool isLocked) = veLock.locks(alice);
        assertFalse(isLocked);
        assertEq(veLock.totalLocked(), 0);
    }
    
    function test_Unlock_NotLocked() public {
        vm.prank(alice);
        vm.expectRevert(veCURLock.NotLocked.selector);
        veLock.unlock();
    }
    
    function test_Unlock_NotExpired() public {
        uint256 gaugeBalance = 1000 * 1e18;
        curStake.setUserGaugeBalance(alice, gaugeBalance);
        
        vm.prank(alice);
        veLock.lock(DURATION_30);
        
        vm.prank(alice);
        vm.expectRevert(veCURLock.NotExpired.selector);
        veLock.unlock();
    }

    function test_Unlock_Event() public {
        uint256 gaugeBalance = 1000 * 1e18;
        curStake.setUserGaugeBalance(alice, gaugeBalance);
        
        vm.prank(alice);
        veLock.lock(DURATION_30);

        vm.warp(block.timestamp + DURATION_30);

        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit Unlocked(alice, gaugeBalance);
        veLock.unlock();
    }
    
    // ============================================
    // Penalty Calculation Tests
    // ============================================
    
    function test_CalculatePenalty_ReturnsZeroWhenExpired() public {
        uint256 gaugeBalance = 1000 * 1e18;
        curStake.setUserGaugeBalance(alice, gaugeBalance);
        
        vm.prank(alice);
        veLock.lock(DURATION_30);

        vm.warp(block.timestamp + DURATION_30 + 1);
        
        uint256 penalty = veLock.calculatePenalty(alice);

        assertEq(penalty, 0);

    }
    
    function test_CalculatePenalty_Formula() public pure{
        uint256 amount = 1000 * 1e18;
        uint256 totalTime = 30 days;
        uint256 remaining = 15 days;  
        
        uint256 expectedPenalty = (amount * 5000 * remaining) / (10000 * totalTime);

        uint256 manualPenalty = 250 * 1e18;

        assertEq(expectedPenalty, manualPenalty);
        
    }
    
    // ============================================
    // EarlyUnlock Tests
    // ============================================
    
    function test_EarlyUnlock_Success() public {
        uint256 lockAmount = 1000 * 1e18; 

        curStake.setUserGaugeBalance(alice, lockAmount);

        vm.prank(alice);
        veLock.lock(DURATION_30);

        uint256 beforeLocked = veLock.totalLocked();
        
        vm.warp(block.timestamp + 15 days);
        
        vm.prank(alice);
        veLock.earlyUnlock();
        
        (,,,,, bool isLocked) = veLock.locks(alice);

        assertFalse(isLocked);
        assertEq(veLock.totalLocked(), beforeLocked - lockAmount);
    }
    
    function test_EarlyUnlock_NotLocked() public {
        vm.prank(alice);
        vm.expectRevert(veCURLock.NotLocked.selector);
        veLock.earlyUnlock();
    }
    
    function test_EarlyUnlock_AlreadyExpired() public {
        uint256 gaugeBalance = 1000 * 1e18;
        curStake.setUserGaugeBalance(alice, gaugeBalance);
        
        vm.prank(alice);
        veLock.lock(DURATION_30);
        
        vm.warp(block.timestamp + DURATION_30 + 1);
        
        vm.prank(alice);
        vm.expectRevert(veCURLock.AlreadyExpired.selector);
        veLock.earlyUnlock();
    }

    function test_EarlyUnlock_event() public {
        uint256 gaugeBalance = 1000 * 1e18;
        curStake.setUserGaugeBalance(alice, gaugeBalance);
        
        vm.prank(alice);
        veLock.lock(DURATION_30);
        
        vm.warp(block.timestamp + 15 days);

        uint256 penalty = veLock.calculatePenalty(alice);
        
        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit EarlyUnlocked(alice, gaugeBalance, penalty);
        veLock.earlyUnlock();
    }

    // ============================================
    // BindNFT Tests
    // ============================================
    function test_BindNFT_Success() public {
        address nftContract = address(1);
        uint256 tokenId = 1;
        uint8 tier = 2;

        nftChecker.setUserBinding(alice, tier);

        vm.prank(alice);
        veLock.bindNFT(nftContract, tokenId);

        (address boundNFT, uint256 boundTokenId, uint8 boundTier, bool isBound) = veLock.nftBindings(alice);

        assertEq(boundNFT, nftContract);
        assertEq(boundTokenId, tokenId);
        assertEq(boundTier, uint8(tier));
        assertTrue(isBound);

        assertTrue(veLock.isNFTBound(nftContract, tokenId));
    }

    function test_BindNFT_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert(veCURLock.NotNFTOwner.selector);
        veLock.bindNFT(address(1), 1);
    }

    function test_BindNFT_AlreadyBound() public {
        vm.prank(alice);

        nftChecker.setUserBinding(alice, 2);

        vm.prank(alice);
        veLock.bindNFT(address(1), 1);

        vm.prank(alice);
        vm.expectRevert(veCURLock.AlreadyBound.selector);
        veLock.bindNFT(address(1), 1);
    }

    function test_BindNFT_Event() public {
        address nftContract = address(1);
        uint256 tokenId = 1;
        uint8 tier = 2;

        nftChecker.setUserBinding(alice, tier);

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit NFTBound(alice, nftContract, tokenId, tier);
        veLock.bindNFT(nftContract, tokenId);
    }

    // ============================================
    // UnbindNFT Tests
    // ============================================
    function test_UnbindNFT_Success() public {
        uint8 tier = 2;

        vm.prank(alice);
        nftChecker.setUserBinding(alice, tier);

        vm.prank(alice);
        veLock.bindNFT(address(1), 1);

        vm.prank(alice);
        veLock.unbindNFT();

        (,,, bool isBound) = veLock.nftBindings(alice);

        assertFalse(isBound);

        assertFalse(veLock.isNFTBound(address(1), 1));
    }

    function test_UnbindNFT_NotBound() public {
        vm.prank(alice);
        vm.expectRevert(veCURLock.NotBound.selector);
        veLock.unbindNFT();
    }

    function test_UnbindNFT_Event() public {
        uint8 tier = 2;

        vm.prank(alice);
        nftChecker.setUserBinding(alice, tier);

        vm.prank(alice);
        veLock.bindNFT(address(1), 1);

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit NFTUnbound(alice, address(1), 1, tier);
        veLock.unbindNFT();
    }


    
    // ============================================
    // GetMaxLockDuration Tests
    // ============================================
    
    function test_GetMaxLockDuration_Returns180ForNoNFT() public view{
        assertEq(veLock.getMaxLockDuration(alice), DURATION_180);
    }
    
    function test_GetMaxLockDuration_Returns365ForIntermediateNFT() public {
        nftChecker.setUserBinding(alice, 1);

        address nftContract = address(1);
        uint256 tokenId = 1;
        vm.prank(alice);
        veLock.bindNFT(nftContract, tokenId);

        assertEq(veLock.getMaxLockDuration(alice), DURATION_365);
    }
    
    function test_GetMaxLockDuration_Returns730ForAdvancedNFT() public {
        nftChecker.setUserBinding(alice, 2);

        address nftContract = address(1);
        uint256 tokenId = 1;
        vm.prank(alice);
        veLock.bindNFT(nftContract, tokenId);

        assertEq(veLock.getMaxLockDuration(alice), DURATION_730);
    }
    
    // ============================================
    // GetBonus Tests
    // ============================================
    
    function test_GetBonus_ReturnsBonusWhenLocked() public {
        uint256 gaugeBalance = 1000 * 1e18;
        curStake.setUserGaugeBalance(alice, gaugeBalance);
        
        vm.prank(alice);
        veLock.lock(DURATION_30);
        
        assertEq(veLock.getBonus(alice), BONUS_30);
    }
    
    function test_GetBonus_ReturnsPrecisionWhenNotLocked() public view{
        assertEq(veLock.getBonus(alice), PRECISION);
    }
    
    function test_GetBonus_ReturnsPrecisionAfterExpiry() public {
        uint256 gaugeBalance = 1000 * 1e18;
        curStake.setUserGaugeBalance(alice, gaugeBalance);
        
        vm.prank(alice);
        veLock.lock(DURATION_30);
        
        vm.warp(block.timestamp + DURATION_30 + 1);
        
        assertEq(veLock.getBonus(alice), PRECISION);
    }
    
    // ============================================
    // GetRemainingTime Tests
    // ============================================
    
    function test_GetRemainingTime_ReturnsCorrectTime() public {
        uint256 gaugeBalance = 1000 * 1e18;
        curStake.setUserGaugeBalance(alice, gaugeBalance);
        
        vm.prank(alice);
        veLock.lock(DURATION_30);
        
        uint256 remaining = veLock.getRemainingTime(alice);
        assertEq(remaining, DURATION_30);
    }
    
    function test_GetRemainingTime_ReturnsZeroWhenNotLocked() public view{
        assertEq(veLock.getRemainingTime(alice), 0);
    }
    
    function test_GetRemainingTime_ReturnsZeroAfterExpiry() public {
        uint256 gaugeBalance = 1000 * 1e18;
        curStake.setUserGaugeBalance(alice, gaugeBalance);
        
        vm.prank(alice);
        veLock.lock(DURATION_30);
        
        vm.warp(block.timestamp + DURATION_30 + 1);
        
        assertEq(veLock.getRemainingTime(alice), 0);
    }

    // ============================================
    // SetNFTChecker Tests
    // ============================================
    function test_SetNFTChecker_Success() public {
        address newNFTChecker = address(0x123);

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit NFTCheckerUpdated(newNFTChecker);
        veLock.setNFTChecker(newNFTChecker);

        assertEq(address(veLock.nftChecker()), newNFTChecker);
    }

    function test_SetNFTChecker_RevertWhenZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(veCURLock.ZeroAddress.selector);
        veLock.setNFTChecker(address(0));
    }
    function test_SetNFTChecker_RevertWhenNotOwner() public {
        address newNFTChecker = address(0x123);
        vm.prank(alice);
        vm.expectRevert();
        veLock.setNFTChecker(newNFTChecker);
    }

    function test_SetNFTChecker_Event() public {
        address newNFTChecker = address(0x123);

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit NFTCheckerUpdated(newNFTChecker);
        veLock.setNFTChecker(newNFTChecker);

    }

    // ============================================
    // SetIncentiveGauge Tests
    // ============================================

    function test_SetIncentiveGauge_Success() public {
        address newGauge = address(0x456);

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit IncentiveGaugeUpdated(newGauge);
        veLock.setIncentiveGauge(newGauge);

        assertEq(address(veLock.incentiveGauge()), newGauge);
    }

    function test_SetIncentiveGauge_RevertWhenZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(veCURLock.ZeroAddress.selector);
        veLock.setIncentiveGauge(address(0));
    }

    function test_SetIncentiveGauge_RevertWhenNotOwner() public {
        address newGauge = address(0x456);
        vm.prank(alice);
        vm.expectRevert();
        veLock.setIncentiveGauge(newGauge);
    }

    function test_SetIncentiveGauge_Event() public {
        address newGauge = address(0x456);

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit IncentiveGaugeUpdated(newGauge);
        veLock.setIncentiveGauge(newGauge);

    }

    
    // ============================================
    // Pause Tests
    // ============================================
    
    function test_Pause_Success() public {
        vm.prank(owner);
        veLock.pause();
        
        assertTrue(veLock.paused());
    }
    
    function test_Unpause_Success() public {
        vm.prank(owner);
        veLock.pause();
        
        vm.prank(owner);
        veLock.unpause();
        
        assertFalse(veLock.paused());
    }
    
    function test_Pause_FailsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        veLock.pause();
    }
    
    function test_Lock_WhenPaused() public {
        vm.prank(owner);
        veLock.pause();
        
        uint256 gaugeBalance = 1000 * 1e18;
        curStake.setUserGaugeBalance(alice, gaugeBalance);
        
        vm.prank(alice);
        vm.expectRevert();
        veLock.lock(DURATION_30);
    }

    function test_Unlock_WhenPaused() public {
        uint256 amount = 1000 * 1e18;

        curStake.setUserGaugeBalance(alice, amount);

        vm.prank(alice);
        veLock.lock(DURATION_30);

        vm.prank(owner);
        veLock.pause();

        vm.prank(alice);
        vm.expectRevert();
        veLock.unlock();
    }

    function test_EarlyUnlock_WhenPaused() public {
        uint256 amount = 1000 * 1e18;

        curStake.setUserGaugeBalance(alice, amount);

        vm.prank(alice);
        veLock.lock(DURATION_30);

        vm.prank(owner);
        veLock.pause();

        vm.prank(alice);
        vm.expectRevert();
        veLock.earlyUnlock();

    }

    function test_BindNFT_WhenPaused() public {
        vm.prank(owner);
        veLock.pause();

        vm.prank(alice);
        vm.expectRevert();
        veLock.bindNFT(address(1), 1);
    }

    function test_UnbindNFT_WhenPaused() public {
        uint8 tier = 1;

        vm.prank(alice);
        nftChecker.setUserBinding(alice, tier);

        vm.prank(alice);
        veLock.bindNFT(address(1), 1);

        vm.prank(owner);
        veLock.pause();

        vm.prank(alice);
        vm.expectRevert();
        veLock.unbindNFT();
    }



    // ============================================
    // Edge Cases Tests
    // ============================================

    function test_EdgeCase_Unlock_ExactlyAtExpiry() public {
        uint256 gaugeBalance = 1000 * 1e18;
        curStake.setUserGaugeBalance(alice, gaugeBalance);
        
        vm.prank(alice);
        veLock.lock(DURATION_30);
        
        vm.warp(block.timestamp + DURATION_30);
        
        vm.prank(alice);
        veLock.unlock();
        
        (,,,,, bool isLocked) = veLock.locks(alice);
        assertFalse(isLocked);
        
    }

    
    function test_EdgeCase_EarlyUnlock_With1SecondRemaining() public {
        uint256 gaugeBalance = 1000 * 1e18; 
        curStake.setUserGaugeBalance(alice, gaugeBalance);

        vm.prank(alice);
        veLock.lock(DURATION_30);

        vm.warp(block.timestamp + DURATION_30 - 1);
        vm.prank(alice);
        veLock.earlyUnlock();

        (,,,,, bool isLocked) = veLock.locks(alice);
        assertFalse(isLocked);
    }

    function test_EdgeCase_EarlyUnlock_With0SecondsRemaining() public {
        uint256 gaugeBalance = 1000 * 1e18; 
        curStake.setUserGaugeBalance(alice, gaugeBalance);

        vm.prank(alice);
        veLock.lock(DURATION_30);

        vm.warp(block.timestamp + DURATION_30);

        vm.prank(alice);
        vm.expectRevert(veCURLock.AlreadyExpired.selector);
        veLock.earlyUnlock();

    } 

    function test_EdgeCase_Penalty_AtStartOfLock() public {
        uint256 gaugeBalance = 1000 * 1e18; 
        curStake.setUserGaugeBalance(alice, gaugeBalance);

        vm.prank(alice);
        veLock.lock(DURATION_30);

        uint256 penalty = veLock.calculatePenalty(alice);
    
    
        uint256 expectedPenalty = (gaugeBalance * 5000) / 10000;
        assertApproxEqAbs(penalty, expectedPenalty, 1);

    }

    function test_EdgeCase_Penalty_AtMidPoint() public {
        uint256 gaugeBalance = 1000 * 1e18; 
        curStake.setUserGaugeBalance(alice, gaugeBalance);

        vm.prank(alice);
        veLock.lock(DURATION_30);

        vm.warp(block.timestamp + 15 days);
        
        uint256 penalty = veLock.calculatePenalty(alice);
        uint256 expectedPenalty = (gaugeBalance * 5000 * 15 days) / (10000 * DURATION_30);
        assertApproxEqAbs(penalty, expectedPenalty, 1);
    
    }

    function test_EdgeCase_Penalty_AtEndOfLock() public {
        uint256 gaugeBalance = 1000 * 1e18; 
        curStake.setUserGaugeBalance(alice, gaugeBalance);

        vm.prank(alice);
        veLock.lock(DURATION_30);

        vm.warp(block.timestamp + DURATION_30 - 1);

        uint256 penalty = veLock.calculatePenalty(alice);

        assertLt(penalty, gaugeBalance / 1000);
    }

    function test_EdgeCase_Penalty_AfterExpiry() public {
        uint256 gaugeBalance = 1000 * 1e18;
        curStake.setUserGaugeBalance(alice, gaugeBalance);
    
        vm.prank(alice);
        veLock.lock(DURATION_30);
    
        vm.warp(block.timestamp + DURATION_30 + 1);
    
        uint256 penalty = veLock.calculatePenalty(alice);
        assertEq(penalty, 0);
    }

    function test_EdgeCase_Lock_WithMinimumAmount() public {
        uint256 minAmount = 1;
        curStake.setUserGaugeBalance(alice,minAmount);

        vm.prank(alice);
        veLock.lock(DURATION_30);

        (uint256 amount,,,,,) = veLock.locks(alice);
        assertEq(amount, minAmount);
        assertEq(veLock.totalLocked(), minAmount);
    }

    function test_EdgeCase_Lock_WithZeroAmount() public {
        curStake.setUserGaugeBalance(alice, 0);
    
        vm.prank(alice);
        vm.expectRevert(veCURLock.ZeroSCUR.selector);
        veLock.lock(DURATION_30);
    }

    function test_EdgeCase_Lock_WithLargeAmount() public {
        uint256 largeAmount = 100_000_000 * 1e18;  // 1亿 CUR
    
        curStake.setUserGaugeBalance(alice, largeAmount);
    
        vm.prank(alice);
        veLock.lock(DURATION_30);
    
        (uint256 amount, , , , , ) = veLock.locks(alice);
        assertEq(amount, largeAmount);
        assertEq(veLock.totalLocked(), largeAmount);
    }

    function test_EdgeCase_Lock_Exactly365Days_WithNFT() public {
        nftChecker.setUserBinding(alice, 1);

        address nftContract = address(1);
        uint256 tokenId = 1;
        vm.prank(alice);
        veLock.bindNFT(nftContract, tokenId);
    
        uint256 gaugeBalance = 1000 * 1e18;
        curStake.setUserGaugeBalance(alice, gaugeBalance);
    
        vm.prank(alice);
        veLock.lock(DURATION_365);
    
        (,,, uint256 duration, uint256 bonusFactor,) = veLock.locks(alice);
        assertEq(duration, DURATION_365);
        assertEq(bonusFactor, BONUS_365);


    }

    function test_EdgeCase_Lock_366Days_WithoutNFT() public {
        uint256 invalidDuration = 366 days;
    
        uint256 gaugeBalance = 1000 * 1e18;
        curStake.setUserGaugeBalance(alice, gaugeBalance);
    
        vm.prank(alice);
        vm.expectRevert(veCURLock.InvalidDuration.selector);
        veLock.lock(invalidDuration);
    }

    function test_EdgeCase_Lock_Exactly730Days_WithAdvancedNFT() public {
        nftChecker.setUserBinding(alice, 2);

        address nftContract = address(1);
        uint256 tokenId = 1;
        vm.prank(alice);
        veLock.bindNFT(nftContract, tokenId);
    
        uint256 gaugeBalance = 1000 * 1e18;
        curStake.setUserGaugeBalance(alice, gaugeBalance);
    
        vm.prank(alice);
        veLock.lock(DURATION_730);
    
        (,,, uint256 duration, uint256 bonusFactor,) = veLock.locks(alice);
        assertEq(duration, DURATION_730);
        assertEq(bonusFactor, BONUS_730);
    }

    function test_EdgeCase_LockUnlockLock_Successive() public {
        uint256 gaugeBalance = 1000 * 1e18;
        curStake.setUserGaugeBalance(alice, gaugeBalance);
    
        vm.prank(alice);
        veLock.lock(DURATION_30);

        vm.warp(block.timestamp + DURATION_30 + 1);

        vm.prank(alice);
        veLock.unlock();
    
        curStake.setUserGaugeBalance(alice, gaugeBalance);
        vm.prank(alice);
        veLock.lock(DURATION_90);
    
        (,,, uint256 duration, , bool isLocked) = veLock.locks(alice);
        assertEq(duration, DURATION_90);
        assertTrue(isLocked);
    }

    function test_EdgeCase_EarlyUnlockTwice_Reverts() public {
        uint256 gaugeBalance = 1000 * 1e18;
        curStake.setUserGaugeBalance(alice, gaugeBalance);

        vm.prank(alice);
        veLock.lock(DURATION_30);

        vm.warp(block.timestamp + 1 days);
    
        vm.prank(alice);
        veLock.earlyUnlock();
    
        vm.prank(alice);
        vm.expectRevert(veCURLock.NotLocked.selector);
        veLock.earlyUnlock();
    }

    function test_EdgeCase_RemainingTime_AfterVeryLongTime() public {
        uint256 gaugeBalance = 1000 * 1e18;
        curStake.setUserGaugeBalance(alice, gaugeBalance);
    
        vm.prank(alice);
        veLock.lock(DURATION_30);
    
        vm.warp(block.timestamp + 1000 days);
    
        uint256 remaining = veLock.getRemainingTime(alice);
        assertEq(remaining, 0);
    }

    function test_EdgeCase_GetBonus_AfterUnlock() public {
        uint256 gaugeBalance = 1000 * 1e18;
        curStake.setUserGaugeBalance(alice, gaugeBalance);
    
        vm.prank(alice);
        veLock.lock(DURATION_30);
    
        assertEq(veLock.getBonus(alice), BONUS_30);
    
        vm.prank(alice);
        veLock.earlyUnlock();

        assertEq(veLock.getBonus(alice), PRECISION);
    }

    function test_EdgeCase_GetBonus_AfterExpiry() public {
        uint256 gaugeBalance = 1000 * 1e18;
        curStake.setUserGaugeBalance(alice, gaugeBalance);
    
        vm.prank(alice);
        veLock.lock(DURATION_30);

        vm.warp(block.timestamp + DURATION_30 + 1);
    
        assertEq(veLock.getBonus(alice), PRECISION);
    }

    function test_EdgeCase_TotalLocked_AfterPartialEarlyUnlock() public {
        uint256 gaugeBalance1 = 1000 * 1e18;
        uint256 gaugeBalance2 = 2000 * 1e18;
    
        curStake.setUserGaugeBalance(alice, gaugeBalance1);
        curStake.setUserGaugeBalance(bob, gaugeBalance2);
    
        vm.prank(alice);
        veLock.lock(DURATION_30);
    
        vm.prank(bob);
        veLock.lock(DURATION_90);
    
        assertEq(veLock.totalLocked(), gaugeBalance1 + gaugeBalance2);
    
        vm.prank(alice);
        veLock.earlyUnlock();
    
        assertEq(veLock.totalLocked(), gaugeBalance2);
   
        vm.warp(block.timestamp + DURATION_90 + 1);
        vm.prank(bob);
        veLock.unlock();
    
        assertEq(veLock.totalLocked(), 0);
    }

    
    // ============================================
    // Fuzz Tests
    // ============================================
    
    function test_Fuzz_GetBonusByDuration(uint8 durationIndex) public view {
        vm.assume(durationIndex <= 4);
        
        uint256 duration;
        uint256 expectedBonus;
        
        if (durationIndex == 0) {
            duration = DURATION_30;
            expectedBonus = BONUS_30;
        } else if (durationIndex == 1) {
            duration = DURATION_90;
            expectedBonus = BONUS_90;
        } else if (durationIndex == 2) {
            duration = DURATION_180;
            expectedBonus = BONUS_180;
        } else if (durationIndex == 3) {
            duration = DURATION_365;
            expectedBonus = BONUS_365;
        } else {
            duration = DURATION_730;
            expectedBonus = BONUS_730;
        }
        
        assertEq(veLock.getBonusByDuration(duration), expectedBonus);
    }
    
    function test_Fuzz_LockAndUnlock(uint256 gaugeAmount) public {
        gaugeAmount = bound(gaugeAmount, 1, 10000000 * 1e18);
        
        curStake.setUserGaugeBalance(alice, gaugeAmount);
        
        vm.prank(alice);
        veLock.lock(DURATION_30);
        
        (uint256 amount, , , , , bool isLocked) = veLock.locks(alice);
        assertEq(amount, gaugeAmount);
        assertTrue(isLocked);
        
        vm.warp(block.timestamp + DURATION_30 + 1);
        
        vm.prank(alice);
        veLock.unlock();
        
        (,,,,, isLocked) = veLock.locks(alice);
        assertFalse(isLocked);
    }
}