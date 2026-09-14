// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/core/CURToken.sol";
import "../src/core/sCUR.sol";
import "../src/core/CURStaking.sol";
import "../src/modules/veCURLock.sol";
import "../src/modules/NFTChecker.sol";
import "../src/modules/IncentiveGauge.sol";
import "../src/modules/RevenueRebatePool.sol";

contract MockCURStaking {
    IncentiveGauge public gauge;

    function setGauge(address _gauge) external {
        gauge = IncentiveGauge(_gauge);
    }

    function deposit(address user, uint256 amount) external {
        gauge.deposit(user, amount);

    }

    function withdraw(address user, uint256 amount) external {
        gauge.withdraw(user, amount);

    }

    function emergencyWithdraw(address user) external {
        gauge.gaugeEmergencyWithdraw(user);

    }

    function withdrawPenalty(uint256 amount) external {
    
    }
}


contract MockveCURLock {
    mapping(address => uint256) public userBonuses;
    IncentiveGauge public gauge;

    function setGauge(address _gauge) external {
        gauge = IncentiveGauge(_gauge);
    }

    function setBonus(address user, uint256 bonus) external {
        userBonuses[user] = bonus;
    }

    function getBonus(address user) external view returns(uint256){
        uint256 bonus = userBonuses[user];

        if(bonus == 0){
            return 1e18;
        }

        return bonus;
    }
     
    function executeLock(address user) external {
        gauge.executeLock(user);
    }

    function executeUnlock(address user) external {
        gauge.executeUnlock(user);
    }

    function executeEarlyUnlock(address user, uint256 penalty) external {
        gauge.executeEarlyUnlock(user, penalty);
    }

}

contract MockRevenueRebatePool {
    

}

contract IncentiveGaugeTest is Test {
    CURToken public curToken;
    sCUR public sCURToken;
    IncentiveGauge public gauge;
    MockCURStaking public curStake;
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


    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event GetReward(address indexed user, uint256 reward);
    event LockExecuted(address indexed user, uint256 additialWeight);
    event UnlockExecuted(address indexed user, uint256 removeWeight);
    event EarlyUnlockExecuted(address indexed user, uint256 penalty, uint256 removeWeight);

    // ============================================
    // Setup
    // ============================================
    function setUp() public {
        vm.startPrank(owner);
        curToken = new CURToken();
        sCURToken = new sCUR(address(curToken));
        curStake = new MockCURStaking();
        veLock = new MockveCURLock();
        revenuePool = new MockRevenueRebatePool();

        gauge = new IncentiveGauge(
            address(curToken),
            address(sCURToken),
            address(curStake),
            address(veLock),
            address(revenuePool)
        );
        
        sCURToken.setIncentiveGauge(address(gauge));

        curStake.setGauge(address(gauge));
        veLock.setGauge(address(gauge));

        curToken.transfer(address(gauge), 90_000_000 * 1e18);
        curToken.transfer(address(sCURToken), 10_000_000 * 1e18);

        sCURToken.addMinter(address(this));
        sCURToken.addMinter(address(gauge));

        vm.stopPrank();

        sCURToken.mint(alice, 10_000_000 * 1e18);
        sCURToken.mint(bob, 10_000_000 * 1e18);
        sCURToken.mint(charlie, 10_000_000 * 1e18);

        vm.prank(alice);
        sCURToken.approve(address(gauge), type(uint256).max);
        vm.prank(bob);
        sCURToken.approve(address(gauge), type(uint256).max);
        vm.prank(charlie);
        sCURToken.approve(address(gauge), type(uint256).max);
        
        vm.prank(owner);
        veLock.setBonus(alice, 1e18);
        veLock.setBonus(bob, 1e18);
        veLock.setBonus(charlie, 1e18);
    }

    // ============================================
    // Constructor Tests
    // ============================================
    function test_Constructor_SetsCorrectState() public view {
        assertEq(address(gauge.curToken()), address(curToken));
        assertEq(address(gauge.sCURToken()), address(sCURToken));
        assertEq(address(gauge.curStake()), address(curStake));
        assertEq(address(gauge.veLock()), address(veLock));
        assertEq(address(gauge.revenueRebatePool()), address(revenuePool));
        assertEq(gauge.owner(), owner);
        assertEq(gauge.totalWeight(), 0);
        assertEq(gauge.rewardPerToken(), 0);
        assertEq(gauge.emissionRate(), EMISSION_RATE_Y1);

    }

    function test_Constructor_RevertsWhenCurTokenZero() public {
        vm.prank(owner);
        vm.expectRevert(IncentiveGauge.ZeroAddress.selector);
        new IncentiveGauge(address(0), address(sCURToken), address(curStake), address(veLock), address(revenuePool));
    }
    
    function test_Constructor_RevertsWhenSCURTokenZero() public {
        vm.prank(owner);
        vm.expectRevert(IncentiveGauge.ZeroAddress.selector);
        new IncentiveGauge(address(curToken), address(0), address(curStake), address(veLock), address(revenuePool));
    }
    
    function test_Constructor_RevertsWhenCurStakeZero() public {
        vm.prank(owner);
        vm.expectRevert(IncentiveGauge.ZeroAddress.selector);
        new IncentiveGauge(address(curToken), address(sCURToken), address(0), address(veLock), address(revenuePool));
    }

    function test_Constructor_RevertsWhenVeLockZero() public {
        vm.prank(owner);
        vm.expectRevert(IncentiveGauge.ZeroAddress.selector);
        new IncentiveGauge(address(curToken), address(sCURToken), address(curStake), address(0), address(revenuePool));
    }
    
    function test_Constructor_RevertsWhenRevenuePoolZero() public {
        vm.prank(owner);
        vm.expectRevert(IncentiveGauge.ZeroAddress.selector);
        new IncentiveGauge(address(curToken), address(sCURToken), address(curStake), address(veLock), address(0));
    }

    // ============================================
    // Deposit Tests
    // ============================================

    function test_Deposit_Success() public {
        uint256 amount = 5000 * 1e18;

        vm.prank(address(curStake));
        gauge.deposit(alice, amount);

        assertEq(gauge.totalWeight(), amount);

        (, uint256 userWeight,,) = gauge.users(alice);
        assertEq(userWeight, amount);


    }
    
    function test_Deposit_Event() public {
        vm.prank(address(curStake));
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
        vm.prank(address(curStake));
        vm.expectRevert(IncentiveGauge.ZeroAmount.selector);
        gauge.deposit(alice, 0);
    }

    function test_Deposit_WithBonus_AppliesWeightCorrectly() public {
        uint256 amount = 1000 * 1e18;
        uint256 bonus = 2.0 * 1e18;
    
        veLock.setBonus(alice, bonus);
    
        vm.prank(address(curStake));
        gauge.deposit(alice, amount);
    
        uint256 expectedWeight = (amount * bonus) / PRECISION;
    
        (, uint256 userWeight, , ) = gauge.users(alice);
        assertEq(userWeight, expectedWeight);
        assertEq(gauge.totalWeight(), expectedWeight);
    }


    // ============================================
    // Withdraw Tests
    // ============================================

    function test_Withdraw_Success() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(alice);
        sCURToken.transfer(address(gauge), amount);

        vm.prank(address(curStake));
        gauge.deposit(alice, amount);

        vm.prank(address(curStake));
        gauge.withdraw(alice, amount);

        (uint256 userAmount, uint256 userWeight,,) = gauge.users(alice);
        assertEq(userAmount, 0);
        assertEq(userWeight, 0);
        assertEq(gauge.totalWeight(), 0);
       
    }

    function test_Withdraw_Event() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(alice);
        sCURToken.transfer(address(gauge), amount);

        vm.prank(address(curStake));
        gauge.deposit(alice, amount);

        vm.prank(address(curStake));
        vm.expectEmit(true, false,false, true);
        emit Withdraw(alice, amount);
        gauge.withdraw(alice, amount);
        
    }

    function test_Withdraw_Unauthorized() public {
        vm.prank(address(curStake));
        gauge.deposit(alice, 1000 * 1e18);
        
        vm.prank(alice);
        vm.expectRevert(IncentiveGauge.Unauthorized.selector);
        gauge.withdraw(alice, 100 * 1e18);
        
    }

    function test_Withdraw_ProportionalWeightRemoval() public {
        uint256 amount = 1000 * 1e18;
        uint256 bonus = 2.0 * 1e18;
    
        veLock.setBonus(alice, bonus);

        vm.prank(alice);
        sCURToken.transfer(address(gauge), amount);

        vm.prank(address(curStake));
        gauge.deposit(alice, amount);
   
        vm.prank(address(curStake));
        gauge.withdraw(alice, 300 * 1e18);
    
        uint256 expectedWeight = 700* 1e18 * bonus / PRECISION;
    
        (, uint256 userWeight, , ) = gauge.users(alice);
        assertEq(userWeight, expectedWeight);
        assertEq(gauge.totalWeight(), expectedWeight);
    }


    // ============================================
    // ExecuteLock Tests
    // ============================================

    function test_ExecuteLock_Success() public {
        uint256 amount = 1000 * 1e18;
        uint256 bonus = 2.0 * 1e18;

        veLock.setBonus(alice, bonus);

        vm.prank(address(curStake));
        gauge.deposit(alice, amount);

        veLock.executeLock(alice);

        uint256 additialWeight = (amount * bonus) / PRECISION;
        assertEq(gauge.totalWeight(), additialWeight);

    }

    function test_ExecuteLock_Event() public {
        uint256 amount = 1000 * 1e18;
        uint256 bonus = 2.0 * 1e18;

        veLock.setBonus(alice, bonus);
      
        vm.prank(address(curStake));
        gauge.deposit(alice, amount);

        (, uint256 oldWeight, ,) = gauge.users(alice);

        uint256 newWeight = amount * bonus / PRECISION;

        uint256 added = newWeight - oldWeight;
     
        vm.expectEmit(true, false, false, true);
        emit LockExecuted(alice, added);
        veLock.executeLock(alice);

    }

    function test_ExecuteLock_Unauthorized() public {
        vm.prank(alice);
        vm.expectRevert(IncentiveGauge.Unauthorized.selector);
        gauge.executeLock(alice);

    }
    
    function test_ExecuteLock_UpdatesWeightCorrectly() public {
        uint256 amount = 1000 * 1e18;
        uint256 bonus = 2.0 * 1e18;
    
        vm.prank(address(curStake));
        gauge.deposit(alice, amount);

        vm.prank(owner);
        veLock.setBonus(alice, bonus);
    
        veLock.executeLock(alice);
    
        uint256 expectedWeight = (amount * bonus) / PRECISION;
        (, uint256 newWeight, , ) = gauge.users(alice);
        assertEq(newWeight, expectedWeight);
    }

    // ============================================
    // ExecuteUnlock Tests
    // ============================================
    
    function test_ExecuteUnlock_Success() public {
        uint256 amount = 1000 * 1e18;
        uint256 bonus = 2.0 * 1e18;

        veLock.setBonus(alice, bonus);
        
        vm.prank(address(curStake));
        gauge.deposit(alice, amount);
        
        veLock.executeLock(alice);
        
        uint256 beforeWeight = gauge.totalWeight();

        veLock.setBonus(alice, 1e18);
    
        veLock.executeUnlock(alice);
        
        uint256 expectedWeight = amount;

        assertEq(gauge.totalWeight(), expectedWeight);
        assertEq(gauge.totalWeight(), beforeWeight - amount);
    }

    function test_ExecuteUnlock_Unauthorized() public {
        vm.prank(alice);
        vm.expectRevert(IncentiveGauge.Unauthorized.selector);
        gauge.executeUnlock(alice);
    }
    
    
    function test_ExecuteUnlock_UpdatesWeightCorrectly() public {
        uint256 amount = 1000 * 1e18;
        uint256 bonus = 2.0 * 1e18;

        veLock.setBonus(alice, bonus);
    
        vm.prank(address(curStake));
        gauge.deposit(alice, amount);
    
        veLock.executeLock(alice);
    
        uint256 weightAfterLock = (amount * bonus) / PRECISION;
        (, uint256 weight, , ) = gauge.users(alice);
        assertEq(weight, weightAfterLock);
  
        veLock.setBonus(alice, 1.0 * 1e18);
    
        veLock.executeUnlock(alice);
    
        (, uint256 newWeight, , ) = gauge.users(alice);
        assertEq(newWeight, amount);
    }

    // ============================================
    // ExecuteEarlyUnlock Tests
    // ============================================

    function test_ExecuteEarlyUnlock_success() public {
        uint256 amount = 1000 * 1e18;
        uint256 penalty = 200 * 1e18;
        uint256 bonus = 2.0 * 1e18;

        veLock.setBonus(alice, bonus);

        vm.prank(alice);
        sCURToken.transfer(address(gauge), amount);

        vm.prank(address(curStake));
        gauge.deposit(alice, amount);
        
        vm.prank(address(veLock));
        veLock.executeLock(alice);
        
        uint256 beforeWeight = gauge.totalWeight();
        uint256 beforeBalance = sCURToken.balanceOf(alice);

        uint256 expectedLockWeight = (amount * bonus) / PRECISION;
        assertEq(beforeWeight, expectedLockWeight);

        vm.prank(address(veLock));
        veLock.executeEarlyUnlock(alice, penalty);

        uint256 actualAmount = amount - penalty;
        assertEq(gauge.totalWeight(), actualAmount);
        assertEq(sCURToken.balanceOf(alice), beforeBalance);

        (uint256 userAmount, uint256 userWeight, , ) = gauge.users(alice);
        assertEq(userAmount, actualAmount);
        assertEq(userWeight, actualAmount);
    }

    function test_ExecuteEarlyUnlock_NoPenalty() public {
        uint256 amount = 1000 * 1e18;
    
        vm.prank(address(curStake));
        gauge.deposit(alice, amount);
  
        veLock.executeLock(alice);
        
        uint256 beforeSCURBalance = sCURToken.balanceOf(alice);
        
        veLock.executeEarlyUnlock(alice, 0);
        
        assertEq(sCURToken.balanceOf(alice), beforeSCURBalance);
        
        assertEq(gauge.totalWeight(), amount);

        (uint256 userAmount, uint256 userWeight, ,) = gauge.users(alice);

        assertEq(userAmount, amount);
        assertEq(userWeight, amount);
    }

    function test_ExecuteEarlyUnlock_FullPenalty() public {
        uint256 amount = 1000 * 1e18;
        uint256 penalty = amount;

        uint256 beforeSCURBalance = sCURToken.balanceOf(alice);

        vm.prank(alice);
        sCURToken.transfer(address(gauge), amount);

        vm.prank(address(curStake));
        gauge.deposit(alice, amount);
        
        veLock.executeLock(alice);
        
        veLock.executeEarlyUnlock(alice, penalty);
        
        assertEq(sCURToken.balanceOf(alice), beforeSCURBalance - amount);
        
        assertEq(gauge.totalWeight(), 0);
        (uint256 userAmount, uint256 userWeight, ,) = gauge.users(alice);

        assertEq(userAmount, 0);
        assertEq(userWeight, 0);

    }
    

    function test_ExecuteEarlyUnlock_Unauthorized() public {
        uint256 amount = 1000 * 1e18;
        uint256 penalty = 200 * 1e18;

        vm.prank(address(curStake));
        gauge.deposit(alice, amount);

        veLock.executeLock(alice);

        vm.prank(alice);
        vm.expectRevert(IncentiveGauge.Unauthorized.selector);
        gauge.executeEarlyUnlock(alice, penalty);


    }

    function test_ExecuteEarlyUnlock_InsufficientAmount() public {
        uint256 amount = 100 * 1e18;
        uint256 penalty = 200 * 1e18;

        vm.prank(address(curStake));
        gauge.deposit(alice, amount);
    
        veLock.executeLock(alice);

        vm.expectRevert(IncentiveGauge.InsufficientAmount.selector);
        veLock.executeEarlyUnlock(alice, penalty);
    }
    
    function test_ExecuteEarlyUnlock_Event() public {
        uint256 amount = 1000 * 1e18;
        uint256 penalty = 200 * 1e18;
        uint256 bonus = 2.0 * 1e18;

        veLock.setBonus(alice, bonus);

        vm.prank(alice);
        sCURToken.transfer(address(gauge), amount);

        vm.prank(address(curStake));
        gauge.deposit(alice, amount);

        vm.prank(address(veLock));
        veLock.executeLock(alice);
    
        uint256 oldWeight = amount * bonus / PRECISION;
        uint256 newWeight = amount - penalty;
        uint256 removeWeight = oldWeight - newWeight;

        vm.expectEmit(true, false, false, true);
        emit EarlyUnlockExecuted(alice, penalty, removeWeight);
        vm.prank(address(veLock));
        veLock.executeEarlyUnlock(alice, penalty);

    }

    
    function test_ExecuteEarlyUnlock_TransfersPendingRewardsToRevenuePool() public {
        uint256 amount = 1000 * 1e18;
        uint256 penalty = 200 * 1e18;

        vm.prank(alice);
        sCURToken.transfer(address(gauge), amount);

        vm.prank(address(curStake));
        gauge.deposit(alice, amount);
    
        veLock.executeLock(alice);
    
        vm.warp(block.timestamp + 365 days);
        vm.prank(address(curStake));
        gauge.deposit(bob, 100 * 1e18);

        uint256 pendingReward = gauge.getPendingReward(alice);
        assertGt(pendingReward, 0);

        veLock.executeEarlyUnlock(alice, penalty);
        
        (,,, uint256 pending) = gauge.users(alice);
        assertEq(pending, 0);
    
    }
    
    // ============================================
    // Emergency Functions Tests
    // ============================================

    function test_EmergencyWithdraw_Success() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(alice);
        sCURToken.transfer(address(gauge), amount);
    
        vm.prank(address(curStake));
        gauge.deposit(alice, amount);
    
        vm.prank(owner);
        gauge.pause();
    
        uint256 beforeBalance = sCURToken.balanceOf(alice);
        uint256 beforeTotalWeight = gauge.totalWeight();
    
        vm.prank(address(curStake));
        gauge.gaugeEmergencyWithdraw(alice);
    
        assertEq(sCURToken.balanceOf(alice), beforeBalance + amount);
        assertEq(gauge.totalWeight(), beforeTotalWeight - amount);
    
        (uint256 userAmount, uint256 userWeight, , uint256 pending) = gauge.users(alice);
        assertEq(userAmount, 0);
        assertEq(userWeight, 0);
        assertEq(pending, 0);
    }

    function test_EmergencyWithdraw_RevertsWhenNotPaused() public {
        uint256 amount = 1000 * 1e18;
    
        vm.prank(address(curStake));
        gauge.deposit(alice, amount);
    
        vm.prank(address(curStake));
        vm.expectRevert();  
        gauge.gaugeEmergencyWithdraw(alice);
    }

    function test_EmergencyWithdraw_NoAssets() public {
        vm.prank(owner);
        gauge.pause();
    
        vm.prank(address(curStake));
        vm.expectRevert(IncentiveGauge.NoAssets.selector);
        gauge.gaugeEmergencyWithdraw(alice);
    }

    function test_EmergencyWithdraw_Unauthorized() public {
        uint256 amount = 1000 * 1e18;
    
        vm.prank(address(curStake));
        gauge.deposit(alice, amount);
    
        vm.prank(owner);
        gauge.pause();
    
        vm.prank(alice);
        vm.expectRevert(IncentiveGauge.Unauthorized.selector);
        gauge.gaugeEmergencyWithdraw(alice);
    }

    function test_EmergencyClearReward_Success() public {
        uint256 amount = 1000 * 1e18;
    
        veLock.setBonus(alice, 2.0 * 1e18);

        vm.prank(address(curStake));
        gauge.deposit(alice, amount);
    
        veLock.executeLock(alice);
    
        vm.warp(block.timestamp + 365 days);
    
        vm.prank(address(curStake));
        gauge.deposit(bob, 100 * 1e18);
    
        uint256 pendingBefore = gauge.getPendingReward(alice);
        assertGt(pendingBefore, 0);
    
        vm.prank(owner);
        gauge.pause();
    
        vm.prank(address(curStake));
        gauge.emergencyClearReward(alice);

        (, , , uint256 pendingRewards) = gauge.users(alice);
        assertEq(pendingRewards, 0);
    
        uint256 pendingAfter = gauge.getPendingReward(alice);
        assertEq(pendingAfter, 0);
    }

    function test_EmergencyClearReward_RevertsWhenNotPaused() public {
        uint256 amount = 1000 * 1e18;
    
        vm.prank(address(curStake));
        gauge.deposit(alice, amount);
    
        vm.prank(address(curStake));
        vm.expectRevert();
        gauge.emergencyClearReward(alice);
    }

    // ============================================
    // GetReward Tests
    // ============================================

    function test_GetReward_Success() public {
        uint256 amount = 1000 * 1e18;
        uint256 bonus = 2.0 * 1e18;

        veLock.setBonus(alice, bonus);
        
        vm.prank(address(curStake));
        gauge.deposit(alice, amount);
        
        veLock.executeLock(alice);

        vm.warp(block.timestamp + 365 days);

        vm.prank(address(curStake));
        gauge.deposit(bob, amount);

        uint256 reward = gauge.getPendingReward(alice);
        assertGt(reward, 0);
        
        uint256 beforeBalance = curToken.balanceOf(alice);
        
        vm.prank(alice);
        gauge.getReward();
        
        assertEq(curToken.balanceOf(alice), beforeBalance + reward);
        
        (,,, uint256 pendingRewards) = gauge.users(alice);
        assertEq(pendingRewards, 0);

    }

    function test_GetReward_ZeroReward() public {
        vm.prank(alice);
        vm.expectRevert(IncentiveGauge.ZeroReward.selector);
        gauge.getReward();

    }

    function test_GetReward_Event() public {
        uint256 amount = 1000 * 1e18;
        uint256 bonus = 2.0 * 1e18;
        
        veLock.setBonus(alice, bonus);
        
        vm.prank(address(curStake));
        gauge.deposit(alice, amount);
        
        veLock.executeLock(alice);

        vm.warp(block.timestamp + 365 days);
        vm.prank(address(curStake));
        gauge.deposit(bob, 100 * 1e18);
        
        uint256 reward = gauge.getPendingReward(alice);
        
        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit GetReward(alice, reward);
        gauge.getReward();

    }

    // ============================================
    // GetPendingReward Tests
    // ============================================
    function test_GetPendingReward_NewUser() public view {
        assertEq(gauge.getPendingReward(alice), 0);
    }

    function test_GetPendingReward_AfterRewardsPositive() public {
        uint256 amount = 1000 * 1e18;
        uint256 bonus = 2.0 * 1e18;

        veLock.setBonus(alice, bonus);
        vm.prank(alice);
        sCURToken.transfer(address(gauge), amount);

        vm.prank(address(curStake));
        gauge.deposit(alice, amount);
        
        vm.warp(block.timestamp + 365 days);

        vm.prank(address(curStake));
        gauge.withdraw(alice, amount);

        assertGt(gauge.getPendingReward(alice), 0);

    }

    function test_GetPendingReward_AfterClaim() public {
        uint256 amount = 1000 * 1e18;
        uint256 bonus = 2.0 * 1e18;

        veLock.setBonus(alice, bonus);

        vm.prank(alice);
        sCURToken.transfer(address(gauge), amount);

        vm.prank(address(curStake));
        gauge.deposit(alice, amount);

        vm.warp(block.timestamp + 365 days);

        vm.prank(address(curStake));
        gauge.withdraw(alice, 100 * 1e18);

        uint256 beforeReward = gauge.getPendingReward(alice);

        assertGt(beforeReward, 0);

        vm.prank(alice);
        gauge.getReward();
        
        uint256 afterReward = gauge.getPendingReward(alice);
        
        assertLt(afterReward, beforeReward);

    }

    // ============================================
    // GetRemainingRewards Tests
    // ============================================

    function test_GetRemainingRewards() public view {
        assertEq(gauge.getRemainingRewards(), 90_000_000 * 1e18);

    }

    function test_GetRemainingRewards_DecreasesAfterClaim() public {
        uint256 amount = 1000 * 1e18;
        uint256 bonus = 2.0 * 1e18;

        veLock.setBonus(alice, bonus);

        vm.prank(address(curStake));
        gauge.deposit(alice, amount);
        
        vm.prank(address(veLock));
        gauge.executeLock(alice);

        vm.warp(block.timestamp + 365 days);

        vm.prank(address(curStake));
        gauge.deposit(bob, 100 * 1e18);

        uint256 reward = gauge.getPendingReward(alice);
        uint256 beforeRemaining = gauge.getRemainingRewards();

        vm.prank(alice);
        gauge.getReward();

        assertEq(gauge.getRemainingRewards(), beforeRemaining - reward);

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
        
        assertEq(gauge.getCurrentEmissionRate(),0);
    }

    // ============================================
    // RewardPerToken Tests
    // ============================================
    
    function test_RewardPerToken_IncreasesWithTime() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(address(curStake));
        gauge.deposit(alice, amount);

        uint256 beforeReward = gauge.rewardPerToken();

        vm.warp(block.timestamp + 100 days);
        vm.prank(address(curStake));
        gauge.deposit(bob, 100 * 1e18);

        uint256 afterReward = gauge.rewardPerToken();
        assertGt(afterReward, beforeReward);
    }

    function test_RewardPerToken_NoIncreaseWithoutUsers() public {
        assertEq(gauge.totalWeight(), 0);
    
        uint256 beforeReward = gauge.rewardPerToken();
    
        vm.warp(block.timestamp + 100 days);
        
        uint256 afterReward = gauge.rewardPerToken();
        assertEq(afterReward, beforeReward);
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
     function test_RevertWhen_PauseNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        gauge.pause();
    }
    
    function test_RevertWhen_DepositPaused() public {
        vm.prank(owner);
        gauge.pause();
        
        vm.prank(address(curStake));
        vm.expectRevert();
        gauge.deposit(alice, 1000 * 1e18);
    }
    
    function test_RevertWhen_WithdrawPaused() public {
        vm.prank(address(curStake));
        gauge.deposit(alice, 1000 * 1e18);
        
        vm.prank(owner);
        gauge.pause();
        
        vm.prank(address(curStake));
        vm.expectRevert();
        gauge.withdraw(alice, 100 * 1e18);
    }
    
    function test_RevertWhen_GetRewardPaused() public {
        vm.prank(owner);
        gauge.pause();
        
        vm.prank(alice);
        vm.expectRevert();
        gauge.getReward();
    }
    
    function test_RevertWhen_ExecuteLockPaused() public {
        vm.prank(owner);
        gauge.pause();
        
        vm.expectRevert();
        veLock.executeLock(alice);
    }

    // ============================================
    // Edge Cases Tests
    // ============================================

    function test_EdgeCase_MultipleDepositsAndWithdraws() public {
        vm.prank(alice);
        sCURToken.transfer(address(gauge), 1000 * 1e18);
        vm.prank(bob);
        sCURToken.transfer(address(gauge), 2000 * 1e18);
        vm.prank(charlie);
        sCURToken.transfer(address(gauge), 500 * 1e18);

        vm.prank(address(curStake));
        gauge.deposit(alice, 1000 * 1e18);

        vm.prank(address(curStake));
        gauge.deposit(bob, 2000 * 1e18);
        assertEq(gauge.totalWeight(), 3000 * 1e18);
        
        vm.prank(address(curStake));
        gauge.withdraw(alice, 500 * 1e18);
        assertEq(gauge.totalWeight(), 2500 * 1e18);
        
        vm.prank(address(curStake));
        gauge.deposit(charlie, 500 * 1e18);
        assertEq(gauge.totalWeight(), 3000 * 1e18);
      
    }

    function test_EdgeCase_LockAndUnlock() public {
        uint256 amount = 1000 * 1e18;
        uint256 bonus = 2.0 * 1e18;

        veLock.setBonus(alice, bonus);
        
        vm.prank(address(curStake));
        gauge.deposit(alice, amount);
        
        veLock.executeLock(alice);
        assertEq(gauge.totalWeight(), (amount * bonus) / PRECISION);
        
        veLock.setBonus(alice, 1e18);
        veLock.executeUnlock(alice);
        
        assertEq(gauge.totalWeight(), amount);
    }

    // ============================================
    // Fuzz Tests
    // ============================================
    function testFuzz_Deposit(uint256 amount) public {
        amount = bound(amount, 1, 10_000_000 * 1e18);
        
        vm.prank(address(curStake));
        gauge.deposit(alice, amount);
        
        assertEq(gauge.totalWeight(), amount);
    }
    
    function testFuzz_ExecuteLock(uint256 amount, uint256 bonus) public {
        amount = bound(amount, 1, 10_000_000 * 1e18);
        bonus = bound(bonus, 1e18, 2e18);

        veLock.setBonus(alice, bonus);
        
        vm.prank(address(curStake));
        gauge.deposit(alice, amount);
        
        veLock.executeLock(alice);
        
        uint256 expectedWeight = (amount * bonus) / PRECISION;
        (, uint256 userWeight,,) = gauge.users(alice);
        assertEq(userWeight, expectedWeight);
        assertEq(gauge.totalWeight(), expectedWeight);
    }
    
    function testFuzz_ExecuteUnlock(uint256 amount, uint256 bonus) public {
        amount = bound(amount, 1, 10_000_000 * 1e18);
        bonus = bound(bonus, 1e18, 2e18);

        veLock.setBonus(alice, bonus);
        
        vm.prank(address(curStake));
        gauge.deposit(alice, amount);
        
        veLock.executeLock(alice);

        veLock.setBonus(alice, 1e18);
        
        veLock.executeUnlock(alice);
        
        (, uint256 userWeight,,) = gauge.users(alice);
        assertEq(userWeight, amount);
        assertEq(gauge.totalWeight(), amount);
    }
    
    function testFuzz_ExecuteEarlyUnlock(uint256 amount, uint256 bonus, uint256 penalty) public {
        amount = bound(amount, 100 * 1e18, 1_000_000 * 1e18);
        bonus = bound(bonus, 1e18, 2e18);
        penalty = bound(penalty, 0, amount / 2);

        veLock.setBonus(alice, bonus);

        vm.prank(alice);
        sCURToken.transfer(address(gauge), amount);

        vm.prank(address(curStake));
        gauge.deposit(alice, amount);

        veLock.executeLock(alice);
        
        uint256 beforeBalance = sCURToken.balanceOf(alice);
        
        veLock.executeEarlyUnlock(alice, penalty);
        
        uint256 actualAmount = amount - penalty;

        assertEq(gauge.totalWeight(), actualAmount);
        assertEq(sCURToken.balanceOf(alice), beforeBalance);

        (uint256 userAmount, uint256 userWeight, , ) = gauge.users(alice);
        assertEq(userAmount, actualAmount);
        assertEq(userWeight, actualAmount);
    }
    
  
}