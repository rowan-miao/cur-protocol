// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/core/CURToken.sol";
import "../src/core/sCUR.sol";
import "../src/modules/veCURLock.sol";
import "../src/modules/NFTChecker.sol";

// Mock IncentiveGauge for testing
contract MockIncentiveGauge {
    address public veLock;

    address public lastCaller;
    address public lastUser;
    uint256 public lastPenalty;

    mapping(address => uint256) public userAmounts;

    error Unauthorized();

    modifier onlyVeLock() {
        if (msg.sender != veLock) revert Unauthorized();
        _;
    }

    function setVeLock(address _veLock) external {
        veLock = _veLock;
    }

    function setUserAmount(address user, uint256 amount) external {
        userAmounts[user] = amount;
    }

    function getUserAmount(address user) external view returns (uint256) {
        return userAmounts[user];
    }

    function executeLock(address user) external onlyVeLock {
        lastCaller = msg.sender;
        lastUser = user;
    }

    function executeUnlock(address user) external onlyVeLock {
        lastCaller = msg.sender;
        lastUser = user;
    }

    function executeEarlyUnlock(address user, uint256 penalty) external onlyVeLock {
        lastCaller = msg.sender;
        lastUser = user;
        lastPenalty = penalty;
    }
}

// Mock NFTChecker for testing
contract MockNFTChecker {
    uint8 public constant TIER_MID = 1;
    uint8 public constant TIER_HIGH = 2;

    struct UserBinding {
        address nftContract;
        uint256 tokenId;
        uint256 bindTime;
        bool isBound;
    }

    mapping(address => UserBinding) public userBindings;
    mapping(address => uint8) public contractTiers;

    function setUserBinding(address user, uint8 tier) external {
        address nft = address(1);

        userBindings[user] = UserBinding({nftContract: nft, tokenId: 1, bindTime: block.timestamp, isBound: true});
        contractTiers[nft] = tier;
    }

    function verifyOwnership(address user, address nftContract, uint256 tokenId) external view returns (bool) {
        return userBindings[user].isBound;
    }

    function getUserTier(address user) external view returns (uint8) {
        if (!userBindings[user].isBound) return 0;
        UserBinding memory binding = userBindings[user];
        return contractTiers[binding.nftContract];
    }

    function getNFTTier(address nftContract) external view returns (uint8) {
        return contractTiers[nftContract];
    }

    function unbindNFTFor(address user) external {
        delete userBindings[user];
    }

    function isUserBound(address user) external view returns (bool) {
        return userBindings[user].isBound;
    }

    function paused() external pure returns (bool) {
        return false; 
    }
}

contract veCURLockTest is Test {
    veCURLock public veLock;
    CURToken public curToken;
    sCUR public sCURToken;
    MockNFTChecker public nftChecker;
    MockIncentiveGauge public incentiveGauge;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public curStaking = makeAddr("curStaking");

    uint256 public constant PRECISION = 1e18;
    uint256 public constant PENALTY_RATE = 5000;

    uint256 public constant DURATION_30 = 30 days;
    uint256 public constant DURATION_90 = 90 days;
    uint256 public constant DURATION_180 = 180 days;
    uint256 public constant DURATION_365 = 365 days;
    uint256 public constant DURATION_730 = 730 days;

    // Bonus factors (1e18 = 1.0x)
    uint256 public constant BONUS_30 = 1.15e18;
    uint256 public constant BONUS_90 = 1.35e18;
    uint256 public constant BONUS_180 = 1.65e18;
    uint256 public constant BONUS_365 = 2.0e18;
    uint256 public constant BONUS_730 = 2.5e18;

    // Events
    event Locked(address indexed user, uint256 duration, uint256 bonusFactor, uint256 endTime);
    event Unlocked(address indexed user, uint256 amount);
    event EarlyUnlocked(address indexed user, uint256 amount, uint256 penalty);
    event IncentiveGaugeUpdated(address indexed oldAddress, address indexed newAddress);
    event CurStakingUpdated(address indexed oldAddress, address indexed newAddress);
    event EmergencyUnlocked(address indexed user, uint256 amount);

    // ============================================
    // Setup
    // ============================================
    function setUp() public {
        vm.startPrank(owner);

        curToken = new CURToken();
        sCURToken = new sCUR(address(curToken), address(0));
        nftChecker = new MockNFTChecker();
        incentiveGauge = new MockIncentiveGauge();

        veLock = new veCURLock(address(sCURToken), address(nftChecker), address(incentiveGauge));

        incentiveGauge.setVeLock(address(veLock));
        veLock.setCurStaking(curStaking);
     
        curToken.transfer(alice, 10_000 * 1e18);

        sCURToken.addMinter(address(this));

        vm.stopPrank();

        sCURToken.mint(alice, 5000 * 1e18);
    }

    // ============================================
    // Constructor Tests
    // ============================================

    function test_Constructor_SetsCorrectState() public view {
        assertEq(address(veLock.sCURToken()), address(sCURToken));
        assertEq(address(veLock.nftChecker()), address(nftChecker));
        assertEq(address(veLock.incentiveGauge()), address(incentiveGauge));
        assertEq(veLock.owner(), owner);
        assertEq(veLock.totalLocked(), 0);
    }

    function test_Constructor_SCURTokenZero() public {
        vm.prank(owner);
        vm.expectRevert(veCURLock.ZeroAddress.selector);
        new veCURLock(address(0), address(nftChecker), address(incentiveGauge));
    }

    function test_Constructor_NFTCheckerZero() public {
        vm.prank(owner);
        vm.expectRevert(veCURLock.ZeroAddress.selector);
        new veCURLock(address(sCURToken), address(0), address(incentiveGauge));
    }

    function test_Constructor_AllowsIncentiveGaugeZero() public {
        vm.prank(owner);

        veCURLock newVeLock = new veCURLock(address(sCURToken), address(nftChecker), address(0));

        assertEq(address(newVeLock.sCURToken()), address(sCURToken));
        assertEq(address(newVeLock.nftChecker()), address(nftChecker));
        assertEq(address(newVeLock.incentiveGauge()), address(0));
        assertEq(newVeLock.owner(), owner);
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

    function test_GetBonusByDuration_ReturnsCorrectBonus() public view {
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
        incentiveGauge.setUserAmount(alice, gaugeBalance);

        vm.prank(alice);
        veLock.lock(DURATION_30);

        (uint256 amount, uint256 startTime, uint256 endTime, uint256 duration, uint256 bonusFactor, bool isLocked) =
            veLock.locks(alice);

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
        incentiveGauge.setUserAmount(alice, gaugeBalance);

        vm.prank(alice);
        veLock.lock(DURATION_90);

        (,,, uint256 duration, uint256 bonusFactor,) = veLock.locks(alice);
        assertEq(duration, DURATION_90);
        assertEq(bonusFactor, BONUS_90);
    }

    function test_Lock_180Days_Success() public {
        uint256 gaugeBalance = 1000 * 1e18;
        incentiveGauge.setUserAmount(alice, gaugeBalance);

        vm.prank(alice);
        veLock.lock(DURATION_180);

        (,,, uint256 duration, uint256 bonusFactor,) = veLock.locks(alice);
        assertEq(duration, DURATION_180);
        assertEq(bonusFactor, BONUS_180);
    }

    function test_Lock_365Days_WithNFTSuccess() public {
        nftChecker.setUserBinding(alice, 1);

        uint256 gaugeBalance = 1000 * 1e18;
        incentiveGauge.setUserAmount(alice, gaugeBalance);

        vm.prank(alice);
        veLock.lock(DURATION_365);

        (,,, uint256 duration, uint256 bonusFactor,) = veLock.locks(alice);
        assertEq(duration, DURATION_365);
        assertEq(bonusFactor, BONUS_365);
    }

    function test_Lock_730Days_WithNFTSuccess() public {
        nftChecker.setUserBinding(alice, 2);

        uint256 gaugeBalance = 1000 * 1e18;
        incentiveGauge.setUserAmount(alice, gaugeBalance);

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
        uint256 gaugeBalance = 1000 * 1e18;
        incentiveGauge.setUserAmount(alice, gaugeBalance);

        vm.prank(alice);
        vm.expectRevert(veCURLock.DurationExceedsPermission.selector);
        veLock.lock(DURATION_365);
    }

    function test_Lock_AlreadyLocked() public {
        uint256 gaugeBalance = 1000 * 1e18;
        incentiveGauge.setUserAmount(alice, gaugeBalance);

        vm.prank(alice);
        veLock.lock(DURATION_30);

        vm.prank(alice);
        vm.expectRevert(veCURLock.AlreadyLocked.selector);
        veLock.lock(DURATION_90);
    }

    function test_Lock_ZeroGaugeBalance() public {
        incentiveGauge.setUserAmount(alice, 0);

        vm.prank(alice);
        vm.expectRevert(veCURLock.ZeroSCUR.selector);
        veLock.lock(DURATION_30);
    }

    function test_Lock_Event() public {
        uint256 gaugeBalance = 1000 * 1e18;
        incentiveGauge.setUserAmount(alice, gaugeBalance);

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
        incentiveGauge.setUserAmount(alice, gaugeBalance);

        vm.prank(alice);
        veLock.lock(DURATION_30);

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
        incentiveGauge.setUserAmount(alice, gaugeBalance);

        vm.prank(alice);
        veLock.lock(DURATION_30);

        vm.prank(alice);
        vm.expectRevert(veCURLock.NotExpired.selector);
        veLock.unlock();
    }

    function test_Unlock_Event() public {
        uint256 gaugeBalance = 1000 * 1e18;
        incentiveGauge.setUserAmount(alice, gaugeBalance);

        vm.prank(alice);
        veLock.lock(DURATION_30);

        vm.warp(block.timestamp + DURATION_30);

        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit Unlocked(alice, gaugeBalance);
        veLock.unlock();
    }
   
    // ============================================
    // EarlyUnlock Tests
    // ============================================

    function test_EarlyUnlock_Success() public {
        uint256 lockAmount = 1000 * 1e18;

        incentiveGauge.setUserAmount(alice, lockAmount);

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
        incentiveGauge.setUserAmount(alice, gaugeBalance);

        vm.prank(alice);
        veLock.lock(DURATION_30);

        vm.warp(block.timestamp + DURATION_30 + 1);

        vm.prank(alice);
        vm.expectRevert(veCURLock.AlreadyExpired.selector);
        veLock.earlyUnlock();
    }

    function test_EarlyUnlock_Event() public {
        uint256 gaugeBalance = 1000 * 1e18;
        incentiveGauge.setUserAmount(alice, gaugeBalance);

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
    // calculatePenalty Tests
    // ============================================

    function test_CalculatePenalty_NotLocked() public view {
        uint256 penalty = veLock.calculatePenalty(alice);
        assertEq(penalty, 0);
    }

    function test_CalculatePenalty_AlreadyExpired() public {
        incentiveGauge.setUserAmount(alice, 1000 * 1e18);
        
        vm.prank(alice);
        veLock.lock(DURATION_30);

        vm.warp(block.timestamp + DURATION_30 + 1);

        uint256 penalty = veLock.calculatePenalty(alice);
        assertEq(penalty, 0);
    }

    function test_CalculatePenalty_JustLocked() public {
        uint256 amount = 1000 * 1e18;
        incentiveGauge.setUserAmount(alice, amount);
        
        vm.prank(alice);
        veLock.lock(DURATION_30);

        uint256 expectedPenalty = (amount * PENALTY_RATE) / 10000;
        uint256 penalty = veLock.calculatePenalty(alice);
        
        assertEq(penalty, expectedPenalty);
    }

    function test_CalculatePenalty_HalfWay() public {
        uint256 amount = 1000 * 1e18;
        incentiveGauge.setUserAmount(alice, amount);
        
        vm.prank(alice);
        veLock.lock(DURATION_30);

        vm.warp(block.timestamp + (DURATION_30 / 2));

        uint256 expectedPenalty = (amount * PENALTY_RATE * (DURATION_30 / 2)) / DURATION_30 / 10000;
        uint256 penalty = veLock.calculatePenalty(alice);
        
        assertEq(penalty, expectedPenalty);
    }
    // ============================================
    // emergencyBreakLock Tests
    // ============================================

    function test_EmergencyBreakLock_NotAuthorized() public {
        vm.prank(alice);
        vm.expectRevert(veCURLock.Unauthorized.selector);
        veLock.emergencyBreakLock(alice);
    }

    function test_EmergencyBreakLock_NotLocked() public {
        vm.prank(curStaking);
        uint256 penalty = veLock.emergencyBreakLock(alice);
        
        assertEq(penalty, 0);
        assertEq(veLock.totalLocked(), 0);
    }
    function test_EmergencyBreakLock_Success() public {
        uint256 amount = 1000 * 1e18;
        incentiveGauge.setUserAmount(alice, amount);
        
        vm.prank(alice);
        veLock.lock(DURATION_30);

        vm.warp(block.timestamp + (DURATION_30 / 2));

        uint256 expectedPenalty = (amount * PENALTY_RATE * (DURATION_30 / 2)) / DURATION_30 / 10000;

        vm.prank(curStaking);
        uint256 penalty = veLock.emergencyBreakLock(alice);

        assertEq(penalty, expectedPenalty);
  
        (,,,,, bool isLocked) = veLock.locks(alice);
        assertFalse(isLocked);
        assertEq(veLock.totalLocked(), 0);
    }

    function test_EmergencyBreakLock_Event() public {
        uint256 amount = 1000 * 1e18;
        incentiveGauge.setUserAmount(alice, amount);
        
        vm.prank(alice);
        veLock.lock(DURATION_30);

        vm.prank(curStaking);
        vm.expectEmit(true, false, false, true);
        emit EmergencyUnlocked(alice, amount);
        veLock.emergencyBreakLock(alice);
    }

    // ============================================
    // GetMaxLockDuration Tests
    // ============================================

    function test_GetMaxLockDuration_Returns180ForNoNFT() public view {
        assertEq(veLock.getMaxLockDuration(alice), DURATION_180);
    }

    function test_GetMaxLockDuration_Returns365ForIntermediateNFT() public {
        nftChecker.setUserBinding(alice, 1);
        assertEq(veLock.getMaxLockDuration(alice), DURATION_365);
    }

    function test_GetMaxLockDuration_Returns730ForAdvancedNFT() public {
        nftChecker.setUserBinding(alice, 2);
        assertEq(veLock.getMaxLockDuration(alice), DURATION_730);
    }

    // ============================================
    // GetBonus Tests
    // ============================================

    function test_GetBonus_ReturnsBonusWhenLocked() public {
        uint256 gaugeBalance = 1000 * 1e18;
        incentiveGauge.setUserAmount(alice, gaugeBalance);

        vm.prank(alice);
        veLock.lock(DURATION_30);

        assertEq(veLock.getBonus(alice), BONUS_30);
    }

    function test_GetBonus_ReturnsPrecisionWhenNotLocked() public view {
        assertEq(veLock.getBonus(alice), PRECISION);
    }

    function test_GetBonus_ReturnsPrecisionAfterExpiry() public {
        uint256 gaugeBalance = 1000 * 1e18;
        incentiveGauge.setUserAmount(alice, gaugeBalance);

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
        incentiveGauge.setUserAmount(alice, gaugeBalance);

        vm.prank(alice);
        veLock.lock(DURATION_30);

        uint256 remaining = veLock.getRemainingTime(alice);
        assertEq(remaining, DURATION_30);
    }

    function test_GetRemainingTime_ReturnsZeroWhenNotLocked() public view {
        assertEq(veLock.getRemainingTime(alice), 0);
    }

    function test_GetRemainingTime_ReturnsZeroAfterExpiry() public {
        uint256 gaugeBalance = 1000 * 1e18;
        incentiveGauge.setUserAmount(alice, gaugeBalance);

        vm.prank(alice);
        veLock.lock(DURATION_30);

        vm.warp(block.timestamp + DURATION_30 + 1);

        assertEq(veLock.getRemainingTime(alice), 0);
    }

    // ============================================
    // SetIncentiveGauge Tests
    // ============================================
    function test_setIncentiveGauge_Success() public {
        address newIncentiveGauge = address(makeAddr("newGauge"));

        vm.prank(owner);
        veLock.setIncentiveGauge(newIncentiveGauge);

        assertEq(address(veLock.incentiveGauge()), newIncentiveGauge);
    }

    function test_setIncentiveGauge_RevertWhenZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(veCURLock.ZeroAddress.selector);
        veLock.setIncentiveGauge(address(0));
    }

    function test_SetIncentiveGauge_RevertSelfAddress() public {
        vm.prank(owner);
        vm.expectRevert(veCURLock.InvalidAddress.selector);
        veLock.setIncentiveGauge(address(veLock));
    }

    function test_SetIncentiveGauge_RevertSameAddress() public {
        address currentGauge = address(veLock.incentiveGauge());
        
        vm.prank(owner);
        vm.expectRevert(veCURLock.SameAddress.selector);
        veLock.setIncentiveGauge(currentGauge);
    }

    function test_setIncentiveGauge_RevertWhenNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        veLock.setIncentiveGauge(makeAddr("newGauge"));
    }

    function test_setIncentiveGauge_Event() public {
        address newIncentiveGauge = address(makeAddr("newGauge"));
        address oldIncentiveGauge = address(incentiveGauge);

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit IncentiveGaugeUpdated(oldIncentiveGauge, newIncentiveGauge);
        veLock.setIncentiveGauge(newIncentiveGauge);
    }

      // ============================================
    // setCurStaking Tests
    // ============================================

    function test_SetCurStaking_Success() public {
        address newStaking = makeAddr("newStaking");

        vm.prank(owner);
        veLock.setCurStaking(newStaking);

        assertEq(address(veLock.curStaking()), newStaking);
    }

    function test_SetCurStaking_RevertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(veCURLock.ZeroAddress.selector);
        veLock.setCurStaking(address(0));
    }

    function test_SetCurStaking_RevertSelfAddress() public {
        vm.prank(owner);
        vm.expectRevert(veCURLock.InvalidAddress.selector);
        veLock.setCurStaking(address(veLock));
    }

    function test_SetCurStaking_RevertSameAddress() public {
        address initialStaking = makeAddr("initialStaking");
        vm.prank(owner);
        veLock.setCurStaking(initialStaking);

        vm.prank(owner);
        vm.expectRevert(veCURLock.SameAddress.selector);
        veLock.setCurStaking(initialStaking);
    }

    function test_SetCurStaking_RevertNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(); 
        veLock.setCurStaking(makeAddr("newStaking"));
    }

    function test_SetCurStaking_Event() public {
        address newStaking = makeAddr("newStaking");
        address oldStaking = address(veLock.curStaking());

        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit CurStakingUpdated(oldStaking, newStaking);
        veLock.setCurStaking(newStaking);
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
        incentiveGauge.setUserAmount(alice, gaugeBalance);

        vm.prank(alice);
        vm.expectRevert();
        veLock.lock(DURATION_30);
    }

    function test_Unlock_WhenPaused() public {
        uint256 amount = 1000 * 1e18;

        incentiveGauge.setUserAmount(alice, amount);

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

        incentiveGauge.setUserAmount(alice, amount);

        vm.prank(alice);
        veLock.lock(DURATION_30);

        vm.prank(owner);
        veLock.pause();

        vm.prank(alice);
        veLock.earlyUnlock();

    }

    // ============================================
    // Edge Cases Tests
    // ============================================

    function test_EdgeCase_Unlock_ExactlyAtExpiry() public {
        uint256 gaugeBalance = 1000 * 1e18;
        incentiveGauge.setUserAmount(alice, gaugeBalance);

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
        incentiveGauge.setUserAmount(alice, gaugeBalance);

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
        incentiveGauge.setUserAmount(alice, gaugeBalance);

        vm.prank(alice);
        veLock.lock(DURATION_30);

        vm.warp(block.timestamp + DURATION_30);

        vm.prank(alice);
        vm.expectRevert(veCURLock.AlreadyExpired.selector);
        veLock.earlyUnlock();
    }

    function test_EdgeCase_Penalty_AtStartOfLock() public {
        uint256 gaugeBalance = 1000 * 1e18;
        incentiveGauge.setUserAmount(alice, gaugeBalance);

        vm.prank(alice);
        veLock.lock(DURATION_30);

        uint256 penalty = veLock.calculatePenalty(alice);

        uint256 expectedPenalty = (gaugeBalance * 5000) / 10000;
        assertApproxEqAbs(penalty, expectedPenalty, 1);
    }

    function test_EdgeCase_Penalty_AtMidPoint() public {
        uint256 gaugeBalance = 1000 * 1e18;
        incentiveGauge.setUserAmount(alice, gaugeBalance);

        vm.prank(alice);
        veLock.lock(DURATION_30);

        vm.warp(block.timestamp + 15 days);

        uint256 penalty = veLock.calculatePenalty(alice);
        uint256 expectedPenalty = (gaugeBalance * 5000 * 15 days) / (10000 * DURATION_30);
        assertApproxEqAbs(penalty, expectedPenalty, 1);
    }

    function test_EdgeCase_Penalty_AtEndOfLock() public {
        uint256 gaugeBalance = 1000 * 1e18;
        incentiveGauge.setUserAmount(alice, gaugeBalance);

        vm.prank(alice);
        veLock.lock(DURATION_30);

        vm.warp(block.timestamp + DURATION_30 - 1);

        uint256 penalty = veLock.calculatePenalty(alice);

        assertLt(penalty, gaugeBalance / 1000);
    }

    function test_EdgeCase_Penalty_AfterExpiry() public {
        uint256 gaugeBalance = 1000 * 1e18;
        incentiveGauge.setUserAmount(alice, gaugeBalance);

        vm.prank(alice);
        veLock.lock(DURATION_30);

        vm.warp(block.timestamp + DURATION_30 + 1);

        uint256 penalty = veLock.calculatePenalty(alice);
        assertEq(penalty, 0);
    }

    function test_EdgeCase_Lock_WithMinimumAmount() public {
        uint256 minAmount = 1;
        incentiveGauge.setUserAmount(alice, minAmount);

        vm.prank(alice);
        veLock.lock(DURATION_30);

        (uint256 amount,,,,,) = veLock.locks(alice);
        assertEq(amount, minAmount);
        assertEq(veLock.totalLocked(), minAmount);
    }

    function test_EdgeCase_Lock_WithZeroAmount() public {
        incentiveGauge.setUserAmount(alice, 0);

        vm.prank(alice);
        vm.expectRevert(veCURLock.ZeroSCUR.selector);
        veLock.lock(DURATION_30);
    }

    function test_EdgeCase_Lock_WithLargeAmount() public {
        uint256 largeAmount = 100_000_000 * 1e18; // 1亿 CUR

        incentiveGauge.setUserAmount(alice, largeAmount);

        vm.prank(alice);
        veLock.lock(DURATION_30);

        (uint256 amount,,,,,) = veLock.locks(alice);
        assertEq(amount, largeAmount);
        assertEq(veLock.totalLocked(), largeAmount);
    }

    function test_EdgeCase_Lock_Exactly365Days_WithNFT() public {
        nftChecker.setUserBinding(alice, 1);

        uint256 gaugeBalance = 1000 * 1e18;
        incentiveGauge.setUserAmount(alice, gaugeBalance);

        vm.prank(alice);
        veLock.lock(DURATION_365);

        (,,, uint256 duration, uint256 bonusFactor,) = veLock.locks(alice);
        assertEq(duration, DURATION_365);
        assertEq(bonusFactor, BONUS_365);
    }

    function test_EdgeCase_Lock_366Days_WithoutNFT() public {
        uint256 invalidDuration = 366 days;

        uint256 gaugeBalance = 1000 * 1e18;
        incentiveGauge.setUserAmount(alice, gaugeBalance);

        vm.prank(alice);
        vm.expectRevert(veCURLock.InvalidDuration.selector);
        veLock.lock(invalidDuration);
    }

    function test_EdgeCase_Lock_Exactly730Days_WithAdvancedNFT() public {
        nftChecker.setUserBinding(alice, 2);

        uint256 gaugeBalance = 1000 * 1e18;
        incentiveGauge.setUserAmount(alice, gaugeBalance);

        vm.prank(alice);
        veLock.lock(DURATION_730);

        (,,, uint256 duration, uint256 bonusFactor,) = veLock.locks(alice);
        assertEq(duration, DURATION_730);
        assertEq(bonusFactor, BONUS_730);
    }

    function test_EdgeCase_LockUnlockLock_Successive() public {
        uint256 gaugeBalance = 1000 * 1e18;
        incentiveGauge.setUserAmount(alice, gaugeBalance);

        vm.prank(alice);
        veLock.lock(DURATION_30);

        vm.warp(block.timestamp + DURATION_30 + 1);

        vm.prank(alice);
        veLock.unlock();

        incentiveGauge.setUserAmount(alice, gaugeBalance);
        vm.prank(alice);
        veLock.lock(DURATION_90);

        (,,, uint256 duration,, bool isLocked) = veLock.locks(alice);
        assertEq(duration, DURATION_90);
        assertTrue(isLocked);
    }

    function test_EdgeCase_EarlyUnlockTwice_Reverts() public {
        uint256 gaugeBalance = 1000 * 1e18;
        incentiveGauge.setUserAmount(alice, gaugeBalance);

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
        incentiveGauge.setUserAmount(alice, gaugeBalance);

        vm.prank(alice);
        veLock.lock(DURATION_30);

        vm.warp(block.timestamp + 1000 days);

        uint256 remaining = veLock.getRemainingTime(alice);
        assertEq(remaining, 0);
    }

    function test_EdgeCase_GetBonus_AfterUnlock() public {
        uint256 gaugeBalance = 1000 * 1e18;
        incentiveGauge.setUserAmount(alice, gaugeBalance);

        vm.prank(alice);
        veLock.lock(DURATION_30);

        assertEq(veLock.getBonus(alice), BONUS_30);

        vm.prank(alice);
        veLock.earlyUnlock();

        assertEq(veLock.getBonus(alice), PRECISION);
    }

    function test_EdgeCase_GetBonus_AfterExpiry() public {
        uint256 gaugeBalance = 1000 * 1e18;
        incentiveGauge.setUserAmount(alice, gaugeBalance);

        vm.prank(alice);
        veLock.lock(DURATION_30);

        vm.warp(block.timestamp + DURATION_30 + 1);

        assertEq(veLock.getBonus(alice), PRECISION);
    }

    function test_EdgeCase_TotalLocked_AfterPartialEarlyUnlock() public {
        uint256 gaugeBalance1 = 1000 * 1e18;
        uint256 gaugeBalance2 = 2000 * 1e18;

        incentiveGauge.setUserAmount(alice, gaugeBalance1);
        incentiveGauge.setUserAmount(bob, gaugeBalance2);

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

        incentiveGauge.setUserAmount(alice, gaugeAmount);

        vm.prank(alice);
        veLock.lock(DURATION_30);

        (uint256 amount,,,,, bool isLocked) = veLock.locks(alice);
        assertEq(amount, gaugeAmount);
        assertTrue(isLocked);

        vm.warp(block.timestamp + DURATION_30 + 1);

        vm.prank(alice);
        veLock.unlock();

        (,,,,, isLocked) = veLock.locks(alice);
        assertFalse(isLocked);
    }
}
