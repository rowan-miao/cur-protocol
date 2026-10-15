// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/core/CURToken.sol";
import "../src/core/sCUR.sol";
import "../src/modules/IncentiveGauge.sol";

contract MockCURStaking {
    function executePenalty(address user, uint256 penalty) external {
        
    }
}

contract MockveCURLock {
    IncentiveGauge public gauge;  
    mapping(address => uint256) public bonus;

    function setGauge(address _gauge) external {   
        gauge = IncentiveGauge(_gauge);
    }

    function setBonus(address user, uint256 _bonus) external {
        bonus[user] = _bonus;
    }

    function getBonus(address user) external view returns (uint256) {
        uint256 b = bonus[user];

        if (b == 0) {
            return 1e18;
        }

        return b;
    }

    function executeLock(address user) external {
        gauge.executeLock(user);
    }

    function executeUnlock(address user) external {
        bonus[user] = 1e18;
        gauge.executeUnlock(user);
    }

    function executeEarlyUnlock(address user, uint256 penalty) external {
        bonus[user] = 1e18;
        gauge.executeEarlyUnlock(user, penalty);
    }
}

contract MockRevenueRebatePool {
    function recordUnallocatedEmission(uint256 amount) external {
    }
}


contract IncentiveGaugeTest is Test {
    CURToken public curToken;
    sCUR public sCURToken;
    IncentiveGauge public gauge;
    MockCURStaking public mockCurStake;
    MockveCURLock public veLock;
    MockRevenueRebatePool public revenuePool;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    uint256 public constant PRECISION = 1e18;
    uint256 public constant SECONDS_PER_YEAR = 365 days;
    uint256 public constant EMISSION_RATE_Y1 = (15_000_000 * 1e18) / SECONDS_PER_YEAR;
    uint256 public constant EMISSION_RATE_Y2 = (12_000_000 * 1e18) / SECONDS_PER_YEAR;
    uint256 public constant EMISSION_RATE_Y3 = (8_000_000 * 1e18) / SECONDS_PER_YEAR;
    uint256 public constant EMISSION_RATE_Y4 = (5_000_000 * 1e18) / SECONDS_PER_YEAR;
    uint256 public constant INITIAL_REWARDS = 1_000_000 * 1e18;


    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event GetReward(address indexed user, uint256 reward);
    event LockExecuted(address indexed user);
    event UnlockExecuted(address indexed user);
    event EarlyUnlockExecuted(address indexed user, uint256 penalty, uint256 oldWeight, uint256 newWeight);
    event EmergencyWithdrawn(address indexed user, uint256 amount);
    event RewardsCleared(address indexed user, uint256 amount);
    event IdleRewardsAccumulated(uint256 rewardAdded);
    event IdleRewardsFlushed(uint256 amount);

    // ============================================
    // Setup
    // ============================================
    function setUp() public {
        vm.startPrank(owner);
        curToken = new CURToken();
        sCURToken = new sCUR(address(curToken), address(0));
        mockCurStake = new MockCURStaking();
        veLock = new MockveCURLock();
        revenuePool = new  MockRevenueRebatePool();

        gauge = new IncentiveGauge(
            address(curToken), address(sCURToken), address(mockCurStake), address(veLock), address(revenuePool)
        );

        sCURToken.addMinter(owner);
        veLock.setGauge(address(gauge));
        sCURToken.setIncentiveGauge(address(gauge));

        curToken.transfer(address(gauge), 10_000_000 * 1e18);
      
        curToken.transfer(alice, 100_000 * 1e18);
        curToken.transfer(bob, 100_000 * 1e18);
        curToken.transfer(charlie, 100_000 * 1e18);

        vm.stopPrank();

        vm.prank(alice);
        curToken.approve(address(revenuePool), type(uint256).max);
        vm.prank(bob);
        curToken.approve(address(revenuePool), type(uint256).max);
        vm.prank(charlie);
        curToken.approve(address(revenuePool), type(uint256).max);

        vm.startPrank(owner);
        veLock.setBonus(alice, 1e18);
        veLock.setBonus(bob, 1e18);
        veLock.setBonus(charlie, 1e18);
        vm.stopPrank();
    }

    // ============================================
    // Constructor Tests
    // ============================================
    function test_Constructor_SetsCorrectState() public view {
        assertEq(address(gauge.curToken()), address(curToken));
        assertEq(address(gauge.sCURToken()), address(sCURToken));
        assertEq(address(gauge.curStake()), address(mockCurStake));
        assertEq(address(gauge.veLock()), address(veLock));
        assertEq(address(gauge.revenueRebatePool()), address(revenuePool));
        assertEq(gauge.totalWeight(), 0);
        assertEq(gauge.rewardPerToken(), 0);
        assertEq(gauge.accumulatedIdleRewards(), 0);
    
    }

    function test_Constructor_RevertsWhenCurTokenZero() public {
        vm.prank(owner);
        vm.expectRevert(IncentiveGauge.ZeroAddress.selector);
        new IncentiveGauge(address(0), address(sCURToken), address(mockCurStake), address(veLock), address(revenuePool));
    }

    function test_Constructor_RevertsWhenSCURTokenZero() public {
        vm.prank(owner);
        vm.expectRevert(IncentiveGauge.ZeroAddress.selector);
        new IncentiveGauge(address(curToken), address(0), address(mockCurStake), address(veLock), address(revenuePool));
    }

    function test_Constructor_RevertsWhenmockCurStakeZero() public {
        vm.prank(owner);
        vm.expectRevert(IncentiveGauge.ZeroAddress.selector);
        new IncentiveGauge(address(curToken), address(sCURToken), address(0), address(veLock), address(revenuePool));
    }

    function test_Constructor_RevertsWhenVeLockZero() public {
        vm.prank(owner);
        vm.expectRevert(IncentiveGauge.ZeroAddress.selector);
        new IncentiveGauge(address(curToken), address(sCURToken), address(mockCurStake), address(0), address(revenuePool));
    }

    function test_Constructor_RevertsWhenRevenuePoolZero() public {
        vm.prank(owner);
        vm.expectRevert(IncentiveGauge.ZeroAddress.selector);
        new IncentiveGauge(address(curToken), address(sCURToken), address(mockCurStake), address(veLock), address(0));
    }

    // ============================================
    // Deposit Tests
    // ============================================

    function test_Deposit_Success() public {
        uint256 amount = 5000 * 1e18;

        vm.prank(owner);
        sCURToken.mint(address(gauge), amount);

        vm.prank(address(mockCurStake));
        gauge.deposit(alice, amount);

        assertEq(gauge.totalWeight(), amount);

        (uint256 userAmount, uint256 userWeight, , ) = gauge.users(alice);
        assertEq(userAmount, amount);
        assertEq(userWeight, amount);
    }

    function test_Deposit_Event() public {
        vm.prank(owner);
        sCURToken.mint(address(gauge), 1000 * 1e18);

        vm.prank(address(mockCurStake));
        vm.expectEmit(true, false, false, true);
        emit Deposit(alice, 1000 * 1e18);
        gauge.deposit(alice, 1000 * 1e18);
    }

    function test_Deposit_Unauthorized() public {
        vm.prank(alice);
        vm.expectRevert(IncentiveGauge.Unauthorized.selector);
        gauge.deposit(alice, 1000 * 1e18);
    }

    function test_Deposit_ZeroAmount() public {
        vm.prank(address(mockCurStake));
        vm.expectRevert(IncentiveGauge.ZeroAmount.selector);
        gauge.deposit(alice, 0);
    }

    function test_Deposit_WithBonus() public {
        uint256 amount = 1000 * 1e18;
        uint256 bonus = 2.0 * 1e18;

        veLock.setBonus(alice, bonus);

        vm.prank(owner);
        sCURToken.mint(address(gauge), amount);

        vm.prank(address(mockCurStake));
        gauge.deposit(alice, amount);

        (uint256 userAmount, uint256 userWeight, , ) = gauge.users(alice);
        assertEq(userAmount, amount);
        assertEq(userWeight, amount * 2);
    }

    // ============================================
    // Withdraw Tests
    // ============================================

    function test_Withdraw_Success() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(owner);
        sCURToken.mint(address(gauge), amount);

        vm.prank(address(mockCurStake));
        gauge.deposit(alice, amount);

        vm.prank(address(mockCurStake));
        gauge.withdraw(alice, amount);

        (uint256 userAmount, uint256 userWeight,,) = gauge.users(alice);
        assertEq(userAmount, 0);
        assertEq(userWeight, 0);
        assertEq(gauge.totalWeight(), 0);
    }

    function test_Withdraw_Event() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(owner);
        sCURToken.mint(address(gauge), amount);

        vm.prank(address(mockCurStake));
        gauge.deposit(alice, amount);

        vm.prank(address(mockCurStake));
        vm.expectEmit(true, false, false, true);
        emit Withdraw(alice, amount);
        gauge.withdraw(alice, amount);
    }

    function test_Withdraw_Unauthorized() public {
        vm.prank(alice);
        vm.expectRevert(IncentiveGauge.Unauthorized.selector);
        gauge.withdraw(alice, 100 * 1e18);
    }

    function test_Withdraw_InsufficientAmount() public {
        vm.prank(address(mockCurStake));
        vm.expectRevert(IncentiveGauge.InsufficientAmount.selector);
        gauge.withdraw(alice, 1000 * 1e18);
    }

    function test_Withdraw_ZeroAmount() public {
        vm.prank(address(mockCurStake));
        vm.expectRevert(IncentiveGauge.ZeroAmount.selector);
        gauge.withdraw(alice, 0);
    }

    
    // ============================================
    // ExecuteLock Tests
    // ============================================

    function test_ExecuteLock_Success() public {
        uint256 amount = 1000 * 1e18;
        uint256 bonus = 2.0 * 1e18;

        vm.prank(owner);
        veLock.setBonus(alice, bonus);

        vm.prank(owner);
        sCURToken.mint(address(gauge), amount);

        vm.prank(address(mockCurStake));
        gauge.deposit(alice, amount);

        vm.prank(address(veLock));
        gauge.executeLock(alice);

        (, uint256 weight, , ) = gauge.users(alice);
        assertEq(weight, amount * 2);
    }

    function test_ExecuteLock_Event() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(owner);
        sCURToken.mint(address(gauge), amount);

        vm.prank(address(mockCurStake));
        gauge.deposit(alice, amount);

        vm.prank(address(veLock));
        vm.expectEmit(true, false, false, true);
        emit LockExecuted(alice);
        gauge.executeLock(alice);
    }

    function test_ExecuteLock_Unauthorized() public {
        vm.prank(alice);
        vm.expectRevert(IncentiveGauge.Unauthorized.selector);
        gauge.executeLock(alice);
    }


    // ============================================
    // ExecuteUnlock Tests
    // ============================================

    function test_ExecuteUnlock_Success() public {
        uint256 amount = 1000 * 1e18;
        uint256 bonus = 2.0 * 1e18;

        vm.prank(owner);
        veLock.setBonus(alice, bonus);

        vm.prank(owner);
        sCURToken.mint(address(gauge), amount);

        vm.prank(address(mockCurStake));
        gauge.deposit(alice, amount);
        
        vm.prank(address(veLock));
        gauge.executeLock(alice);

        vm.prank(owner);
        veLock.setBonus(alice, 1e18);

        vm.prank(address(veLock));
        gauge.executeUnlock(alice);
        
        (, uint256 weight, , ) = gauge.users(alice);
        assertEq(weight, amount);
    
    }

    function test_ExecuteUnlock_Unauthorized() public {
        vm.prank(alice);
        vm.expectRevert(IncentiveGauge.Unauthorized.selector);
        gauge.executeUnlock(alice);
    }


    // ============================================
    // ExecuteEarlyUnlock Tests
    // ============================================

    function test_ExecuteEarlyUnlock_success() public {
        uint256 amount = 1000 * 1e18;
        uint256 penalty = 200 * 1e18;
        uint256 bonus = 2.0 * 1e18;

        vm.prank(owner);
        veLock.setBonus(alice, bonus);

        vm.prank(owner);
        sCURToken.mint(address(gauge), amount);

        vm.prank(address(mockCurStake));
        gauge.deposit(alice, amount);

        vm.prank(address(veLock));
        veLock.executeLock(alice);

        vm.prank(address(veLock));
        veLock.executeEarlyUnlock(alice, penalty);

        (uint256 userAmount, uint256 userWeight, , ) = gauge.users(alice);
        assertEq(userWeight, userAmount);
        assertEq(gauge.totalWeight(), userAmount);
    }

    function test_ExecuteEarlyUnlock_Event() public {
        uint256 amount = 1000 * 1e18;
        uint256 bonus = 2e18;
        uint256 penalty = 200 * 1e18;

        vm.prank(owner);
        veLock.setBonus(alice, bonus);

        vm.prank(owner);
        sCURToken.mint(address(gauge), amount);

        vm.prank(address(mockCurStake));
        gauge.deposit(alice, amount);

        veLock.executeLock(alice);

        uint256 oldWeight = (amount * bonus) / PRECISION;      
        uint256 newWeight = (amount - penalty) * 1e18 / PRECISION;    

        vm.expectEmit(true, false, false, true);
        emit EarlyUnlockExecuted(alice, penalty, oldWeight, newWeight);
        veLock.executeEarlyUnlock(alice, penalty);
    }


    function test_ExecuteEarlyUnlock_Unauthorized() public {
        uint256 penalty = 200 * 1e18;

        vm.prank(alice);
        vm.expectRevert(IncentiveGauge.Unauthorized.selector);
        gauge.executeEarlyUnlock(alice, penalty);
    }

   
  

    // ============================================
    // Emergency Functions Tests
    // ============================================

    function test_EmergencyWithdraw_Success() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(owner);
        sCURToken.mint(address(gauge), amount);

        vm.prank(address(mockCurStake));
        gauge.deposit(alice, amount);

        vm.prank(owner);
        gauge.pause();

        uint256 beforeBalance = sCURToken.balanceOf(alice);
        uint256 beforeTotalWeight = gauge.totalWeight();

        vm.prank(address(mockCurStake));
        gauge.gaugeEmergencyWithdraw(alice);

        assertEq(sCURToken.balanceOf(alice), beforeBalance + amount);
        assertEq(gauge.totalWeight(), beforeTotalWeight - amount);

        (uint256 userAmount, uint256 userWeight,, uint256 pending) = gauge.users(alice);
        assertEq(userAmount, 0);
        assertEq(userWeight, 0);
        assertEq(pending, 0);
    }

    function test_EmergencyWithdraw_RevertsWhenNotPaused() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(address(mockCurStake));
        gauge.deposit(alice, amount);

        vm.prank(address(mockCurStake));
        vm.expectRevert();
        gauge.gaugeEmergencyWithdraw(alice);
    }

    function test_EmergencyWithdraw_NoAssets() public {
        vm.prank(owner);
        gauge.pause();

        vm.prank(address(mockCurStake));
        vm.expectRevert(IncentiveGauge.NoAssets.selector);
        gauge.gaugeEmergencyWithdraw(alice);
    }

    function test_EmergencyWithdraw_Unauthorized() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(address(mockCurStake));
        gauge.deposit(alice, amount);

        vm.prank(owner);
        gauge.pause();

        vm.prank(alice);
        vm.expectRevert(IncentiveGauge.Unauthorized.selector);
        gauge.gaugeEmergencyWithdraw(alice);
    }

    function test_EmergencyClearReward_Success() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(owner);
        sCURToken.mint(address(gauge), amount);

        vm.prank(address(mockCurStake));
        gauge.deposit(alice, amount);

        vm.warp(block.timestamp + 365 days);

        vm.prank(address(mockCurStake));
        gauge.deposit(bob, 100 * 1e18);

        uint256 pendingBefore = gauge.getPendingReward(alice);
        assertGt(pendingBefore, 0);

        vm.prank(owner);
        gauge.pause();

        vm.prank(address(mockCurStake));
        gauge.emergencyClearReward(alice);

        uint256 pendingAfter = gauge.getPendingReward(alice);
        assertEq(pendingAfter, 0);
    }

    function test_EmergencyClearReward_RevertsWhenNotPaused() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(address(mockCurStake));
        gauge.deposit(alice, amount);

        vm.prank(address(mockCurStake));
        vm.expectRevert();
        gauge.emergencyClearReward(alice);
    }

    // ============================================
    // GetReward Tests
    // ============================================

    function test_getReward_Success() public {
        uint256 amount = 1000 * 1e18;
        
        vm.prank(owner);
        sCURToken.mint(address(gauge), amount);

        vm.prank(address(mockCurStake));
        gauge.deposit(alice, amount);

        vm.warp(block.timestamp + 100 days);

        vm.prank(address(mockCurStake));
        gauge.deposit(bob, amount);

        vm.prank(alice);
        gauge.flushIdleRewards();

        uint256 reward = gauge.getPendingReward(alice);
        assertGt(reward, 0);

        uint256 beforeBalance = curToken.balanceOf(alice);

        vm.prank(alice);
        gauge.getReward();

        assertEq(curToken.balanceOf(alice), beforeBalance + reward);

        (,,, uint256 pendingRewards) = gauge.users(alice);
        assertEq(pendingRewards, 0);
    }

    function test_getReward_ZeroReward() public {
        vm.prank(alice);
        vm.expectRevert(IncentiveGauge.ZeroReward.selector);
        gauge.getReward();
    }

    function test_getReward_Event() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(owner);
        sCURToken.mint(address(gauge), amount);

        vm.prank(address(mockCurStake));
        gauge.deposit(alice, amount);

        vm.warp(block.timestamp + 100 days);
        vm.prank(address(mockCurStake));
        gauge.deposit(bob, 100 * 1e18);

        vm.prank(alice);
        gauge.flushIdleRewards();

        uint256 reward = gauge.getPendingReward(alice);

        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit GetReward(alice, reward);
        gauge.getReward();
    }

    // ============================================
    // Idle Rewards Tests
    // ============================================

    function test_FlushIdleRewards_Success() public {
        uint256 slot = 8;
        uint256 idleAmount = 1000 * 1e18;

        vm.store(address(gauge), bytes32(slot), bytes32(idleAmount));

        uint256 beforeBalance = curToken.balanceOf(address(revenuePool));

        vm.prank(alice);
        gauge.flushIdleRewards();

        assertEq(gauge.accumulatedIdleRewards(), 0);
        assertEq(curToken.balanceOf(address(revenuePool)), beforeBalance + idleAmount);
    }

    function test_FlushIdleRewards_ZeroAmount() public {
        vm.prank(alice);
        gauge.flushIdleRewards();
    
        assertEq(gauge.accumulatedIdleRewards(), 0);
    }

    function test_FlushIdleRewards_Event() public {
        uint256 slot = 8;
        uint256 idleAmount = 1000 * 1e18;

        vm.store(address(gauge), bytes32(slot), bytes32(idleAmount));

        vm.prank(alice);
        vm.expectEmit(false, false, false, true);
        emit IdleRewardsFlushed(idleAmount);
        gauge.flushIdleRewards();
    }


    // ============================================
    //  View Functions Tests
    // ============================================
    function test_GetPendingReward_NewUser() public view {
        assertEq(gauge.getPendingReward(alice), 0);
    }

    

    function test_GetRemainingRewards() public view {
        assertEq(gauge.getRemainingRewards(), 10_000_000 * 1e18);
    }

   
    // ============================================
    // Emission Rate Tests
    // ============================================
    function test_EmissionRateYear1() public {
        vm.warp(block.timestamp + 100 days);

        assertEq(gauge.getCurrentEmissionRate(), EMISSION_RATE_Y1);
    }

    function test_EmissionRateYear2() public {
        vm.warp(block.timestamp + 400 days);

        assertEq(gauge.getCurrentEmissionRate(), EMISSION_RATE_Y2);
    }

    function test_EmissionRateYear3() public {
        vm.warp(block.timestamp + 800 days);

        assertEq(gauge.getCurrentEmissionRate(), EMISSION_RATE_Y3);
    }

    function test_EmissionRateYear4() public {
        vm.warp(block.timestamp + 1200 days);

        assertEq(gauge.getCurrentEmissionRate(), EMISSION_RATE_Y4);
    }

    function test_EmissionRateAfterFourYears() public {
        vm.warp(block.timestamp + 1500 days);

        assertEq(gauge.getCurrentEmissionRate(), 0);
    }

    function test_GetUserAmount() public {
        uint256 amount = 1000 * 1e18;
        
        vm.prank(owner);
        sCURToken.mint(address(gauge), amount);

        vm.prank(address(mockCurStake));
        gauge.deposit(alice, amount);

        assertEq(gauge.getUserAmount(alice), amount);
    }


    // ============================================
    // Pause Tests
    // ============================================

    function test_Pause_Success() public {
        vm.prank(owner);
        gauge.pause();

        assertTrue(gauge.paused());
    }

    function test_Unpause_Success() public {
        vm.prank(owner);
        gauge.pause();

        vm.prank(owner);
        gauge.unpause();

        assertFalse(gauge.paused());
    }

    function test_Pause_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        gauge.pause();
    }

    function test_Pause_Deposit() public {
        vm.prank(owner);
        gauge.pause();

        vm.prank(address(mockCurStake));
        vm.expectRevert();
        gauge.deposit(alice, 1000 * 1e18);
    }

    function test_Pause_Withdraw() public {
        vm.prank(address(mockCurStake));
        gauge.deposit(alice, 1000 * 1e18);

        vm.prank(owner);
        gauge.pause();

        vm.prank(address(mockCurStake));
        vm.expectRevert();
        gauge.withdraw(alice, 100 * 1e18);
    }

    function test_Pause_GetReward() public {
        vm.prank(owner);
        gauge.pause();

        vm.prank(alice);
        vm.expectRevert();
        gauge.getReward();
    }

    function test_Pause_ExecuteLock() public {
        vm.prank(owner);
        gauge.pause();

        vm.expectRevert();
        veLock.executeLock(alice);
    }

    // ============================================
    // Edge Cases Tests
    // ============================================

    function test_EdgeCase_MultipleDepositsAndWithdraws() public {
        uint256 aliceAmount = 1000 * 1e18;
        uint256 bobAmount = 2000 * 1e18;
        uint256 charlieAmount = 500 * 1e18;

        vm.prank(owner);
        sCURToken.mint(address(gauge), aliceAmount + bobAmount + charlieAmount);

        vm.prank(address(mockCurStake));
        gauge.deposit(alice, aliceAmount);

        vm.prank(address(mockCurStake));
        gauge.deposit(bob, bobAmount);
        assertEq(gauge.totalWeight(), aliceAmount + bobAmount);

        vm.prank(address(mockCurStake));
        gauge.withdraw(alice, 500 * 1e18);
        assertEq(gauge.totalWeight(), (aliceAmount - 500 * 1e18) + bobAmount);

        vm.prank(address(mockCurStake));
        gauge.deposit(charlie, charlieAmount);
        assertEq(gauge.totalWeight(), (aliceAmount - 500 * 1e18) + bobAmount + charlieAmount);
    }

    function test_EdgeCase_LockAndUnlock() public {
        uint256 amount = 1000 * 1e18;
        uint256 bonus = 2.0 * 1e18;
        
        vm.prank(owner);
        veLock.setBonus(alice, bonus);

        vm.prank(owner);
        sCURToken.mint(address(gauge), amount);

        vm.prank(address(mockCurStake));
        gauge.deposit(alice, amount);

        vm.prank(address(veLock));
        veLock.executeLock(alice);
        assertEq(gauge.totalWeight(), (amount * bonus) / PRECISION);

        vm.prank(owner);
        veLock.setBonus(alice, 1e18);

        vm.prank(address(veLock));
        gauge.executeUnlock(alice);
       
        assertEq(gauge.totalWeight(), amount);
    }

    // ============================================
    // Fuzz Tests
    // ============================================
    function testFuzz_Deposit(uint256 amount) public {
        amount = bound(amount, 1, 10_000_000 * 1e18);

        vm.prank(owner);
        sCURToken.mint(address(gauge), amount);

        vm.prank(address(mockCurStake));
        gauge.deposit(alice, amount);

        assertEq(gauge.totalWeight(), amount);

        (uint256 userAmount, uint256 userWeight, , ) = gauge.users(alice);
        assertEq(userAmount, amount);
        assertEq(userWeight, amount);
    }

    function testFuzz_ExecuteLock(uint256 amount, uint256 bonus) public {
        amount = bound(amount, 1, 10_000_000 * 1e18);
        bonus = bound(bonus, 1e18, 2e18);

        vm.prank(owner);
        veLock.setBonus(alice, bonus);

        vm.prank(owner);
        sCURToken.mint(address(gauge), amount);

        vm.prank(address(mockCurStake));
        gauge.deposit(alice, amount);

        vm.prank(address(veLock));
        gauge.executeLock(alice);

        uint256 expectedWeight = (amount * bonus) / PRECISION;
        (, uint256 userWeight,,) = gauge.users(alice);
        assertEq(userWeight, expectedWeight);
        assertEq(gauge.totalWeight(), expectedWeight);
    }

    function testFuzz_ExecuteUnlock(uint256 amount, uint256 bonus) public {
        amount = bound(amount, 1, 10_000_000 * 1e18);
        bonus = bound(bonus, 1e18, 2e18);

        vm.prank(owner);
        veLock.setBonus(alice, bonus);

        vm.prank(owner);
        sCURToken.mint(address(gauge), amount);

        vm.prank(address(mockCurStake));
        gauge.deposit(alice, amount);

        vm.prank(address(veLock));
        gauge.executeLock(alice);

        vm.prank(owner);
        veLock.setBonus(alice, 1e18);

        vm.prank(address(veLock));
        gauge.executeUnlock(alice);

        (, uint256 userWeight,,) = gauge.users(alice);
        assertEq(userWeight, amount);
        assertEq(gauge.totalWeight(), amount);
    }

    function testFuzz_ExecuteEarlyUnlock(uint256 amount, uint256 bonus, uint256 penalty) public {
        amount = bound(amount, 100 * 1e18, 1_000_000 * 1e18);
        bonus = bound(bonus, 1e18, 2e18);
        penalty = bound(penalty, 0, amount / 2);

        vm.prank(owner);
        veLock.setBonus(alice, bonus);

        vm.prank(owner);
        sCURToken.mint(address(gauge), amount);

        vm.prank(address(mockCurStake));
        gauge.deposit(alice, amount);

        veLock.executeLock(alice);

        veLock.executeEarlyUnlock(alice, penalty);

        uint256 actualAmount = amount - penalty;
        assertEq(gauge.totalWeight(), actualAmount);

        (uint256 userAmount, uint256 userWeight,,) = gauge.users(alice);
        assertEq(userAmount, actualAmount);
        assertEq(userWeight, actualAmount);
    }
}
