// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/core/CURStaking.sol";
import "../src/core/sCUR.sol";
import "../src/core/CURToken.sol";
import "../src/interfaces/IsCUR.sol";
import "../src/interfaces/IIncentiveGauge.sol";
import "../src/interfaces/IveCURLock.sol";

// Mock contracts for testing
contract MockIncentiveGauge {
    IsCUR public sCURToken;
    constructor(address _sCUR) {
        sCURToken = IsCUR(_sCUR);
    }

    struct UserInfo {
        uint256 amount;
        uint256 weight;
        uint256 rewardPerTokenPaid;
        uint256 pendingRewards;
    }
 
    mapping(address => UserInfo) public users;
    
    function deposit(address user, uint256 amount) external {
        users[user].amount += amount;
        users[user].weight += amount;
    }
    
    function withdraw(address user, uint256 amount) external {
        users[user].amount -= amount;
        users[user].weight -= amount;
        sCURToken.transfer(user, amount);
    }

    function gaugeEmergencyWithdraw(address user) external {
        uint256 amount = users[user].amount;

        users[user].amount = 0;
        users[user].weight = 0;
        users[user].pendingRewards = 0;
        users[user].rewardPerTokenPaid = 0;

        sCURToken.transfer(user, amount);
    }

    function emergencyClearReward(address user) external {
        users[user].pendingRewards = 0;
    }
    
    function getRemainingRewards() external pure returns (uint256){
        return 0;
    }

    function getCurrentEmissionRate() external pure returns (uint256){
        return 0;
    }

}

contract MockVeCURLock {
    mapping(address => uint256) public userBonuses;
    
    function setBonus(address user, uint256 bonus) external {
        userBonuses[user] = bonus;
    }
    
    function getBonus(address user) external view returns (uint256) {
        return userBonuses[user];
    }
}

contract MockRevenueRebatePool {

}

contract CURStakingTest is Test {
    CURStaking public staking;
    CURToken public curToken;
    sCUR public sCURToken;
    MockIncentiveGauge public gauge;
    MockVeCURLock public veLock;
    MockRevenueRebatePool public revenuePool;
    
    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    
    uint256 public constant PRECISION = 1e18;
    uint256 public constant TOTAL_SUPPLY = 100_000_000 * 1e18;
    uint256 public constant INITIAL_EXCHANGE_RATE = 1e18;
    
    // Events
    event Staked(address indexed user, uint256 CURAmount, uint256 sCURAmount);
    event UnStaked(address indexed user, uint256 sCURAmount, uint256 CURAmount);
    event EnterGauge(address indexed user, uint256 sCURAmount); 
    event ExitGauge(address indexed user, uint256 sCURAmount);
    event EmergencyWithdrawn(address indexed user, uint256 sCURAmount, uint256 CURAmount);
    event PenaltyWithdrawn(address indexed receiver, uint256 CURAmount);

    // ============================================
    // Setup
    // ============================================
    function setUp() public {
        vm.startPrank(owner);

        curToken = new CURToken();
        
        sCURToken = new sCUR(address(curToken));
        
        gauge = new MockIncentiveGauge(address(sCURToken));
        
        veLock = new MockVeCURLock();
       
        revenuePool = new MockRevenueRebatePool();

        staking = new CURStaking(
            address(curToken),
            address(sCURToken),
            address(gauge),
            address(veLock),
            address(revenuePool)
        );
        
        sCURToken.addMinter(address(staking));

        vm.stopPrank();

        vm.startPrank(owner);

        curToken.transfer(alice, 100_000 * 1e18);
        curToken.transfer(bob, 100_000 * 1e18);
        curToken.transfer(charlie, 100_000 * 1e18);

        vm.stopPrank();

        vm.prank(alice);
        curToken.approve(address(staking), type(uint256).max);
        vm.prank(bob);
        curToken.approve(address(staking), type(uint256).max);
        vm.prank(charlie);
        curToken.approve(address(staking), type(uint256).max);

        vm.prank(alice);
        sCURToken.approve(address(staking), type(uint256).max);
        vm.prank(bob);
        sCURToken.approve(address(staking), type(uint256).max);
        vm.prank(charlie);
        sCURToken.approve(address(staking), type(uint256).max);
    }
    
    // ============================================
    // Constructor Tests
    // ============================================
    
    function test_Constructor() public view {
        assertEq(address(staking.curToken()), address(curToken));
        assertEq(address(staking.sCURToken()), address(sCURToken));
        assertEq(address(staking.gauge()), address(gauge));
        assertEq(address(staking.veLock()), address(veLock));
        assertEq(address(staking.revenueRebatePool()), address(revenuePool));
        assertEq(staking.owner(), owner);
    }

    function test_Constructor_RevertsWhenCurTokenZero() public {
        vm.prank(owner);
        vm.expectRevert(CURStaking.ZeroAddress.selector);
        new CURStaking(address(0), address(sCURToken), address(gauge), address(veLock), address(revenuePool));
    }
    
    function test_Constructor_RevertsWhenSCURTokenZero() public {
        vm.prank(owner);
        vm.expectRevert(CURStaking.ZeroAddress.selector);
        new CURStaking(address(curToken), address(0), address(gauge), address(veLock), address(revenuePool));
    }
    
    function test_Constructor_RevertsWhenGaugeZero() public {
        vm.prank(owner);
        vm.expectRevert(CURStaking.ZeroAddress.selector);
        new CURStaking(address(curToken), address(sCURToken), address(0), address(veLock), address(revenuePool));
    }

    function test_Constructor_RevertsWhenVeLockZero() public {
        vm.prank(owner);
        vm.expectRevert(CURStaking.ZeroAddress.selector);
        new CURStaking(address(curToken), address(sCURToken), address(gauge), address(0), address(revenuePool));
    }

    function test_Constructor_RevertsWhenRevenuePoolZero() public {
        vm.prank(owner);
        vm.expectRevert(CURStaking.ZeroAddress.selector);
        new CURStaking(address(curToken), address(sCURToken), address(gauge), address(veLock), address(0));
    }
    
    
    // ============================================
    // Stake Tests
    // ============================================
    
    function test_Stake_Success() public {
        uint256 curAmount = 1000 * 1e18;
        
        vm.prank(alice);
        staking.stake(curAmount);
        
        ( uint256 stakedSCUR, uint256 depositedGauge) = staking.getUserInfo(alice);
        
        assertEq(stakedSCUR, curAmount); 
        assertEq(depositedGauge, 0);
        assertEq(sCURToken.balanceOf(alice), curAmount);
    }
    
    function test_Stake_ZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(CURStaking.ZeroAmount.selector);
        staking.stake(0);
    }
    
    
    function test_Stake_Event() public {
        uint256 curAmount = 1000 * 1e18;
        
        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit Staked(alice, curAmount, curAmount);
        staking.stake(curAmount);
    }
    
    // ============================================
    // Unstake Tests
    // ============================================
    
    function test_Unstake_success() public {
        uint256 curAmount = 1000 * 1e18;

        vm.prank(alice);
        staking.stake(curAmount);

        assertEq(sCURToken.balanceOf(alice), curAmount);
        assertEq(curToken.balanceOf(address(staking)), curAmount);

        uint256 beforeBalance = curToken.balanceOf(alice);

        vm.prank(alice);
        staking.unstake(curAmount);
        
        (uint256 stakedSCUR,) = staking.getUserInfo(alice);
        
        assertEq(stakedSCUR, 0);
        assertEq(sCURToken.balanceOf(alice), 0);
        assertEq(curToken.balanceOf(alice), beforeBalance + curAmount);
        assertEq(curToken.balanceOf(address(staking)), 0);
    }
    
    function test_Unstake_ZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(CURStaking.ZeroAmount.selector);
        staking.unstake(0);
    }
    
    function test_Unstake_InsufficientFreeSCUR() public {
        vm.prank(alice);
        staking.stake(1000 * 1e18);
        
        vm.prank(alice);
        staking.enterGauge(600 * 1e18);
        
        vm.prank(alice);
        vm.expectRevert(CURStaking.InsufficientFreeSCUR.selector);
        staking.unstake(500 * 1e18); 
    }

    function test_Unstake_Event() public {
        uint256 curAmount = 1000 * 1e18;

        vm.prank(alice);
        staking.stake(curAmount);
        
        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit UnStaked(alice, curAmount, curAmount);
        staking.unstake(curAmount);
    }

    
    // ============================================
    // EnterGauge Tests
    // ============================================
    
    function test_EnterGauge_success() public {
        vm.prank(alice);
        staking.stake(1000 * 1e18);
        
        vm.prank(alice);
        staking.enterGauge(500 * 1e18);
        
        (uint256 stakedSCUR, uint256 depositedGauge) = staking.getUserInfo(alice);
        assertEq(stakedSCUR, 1000 * 1e18);
        assertEq(depositedGauge, 500 * 1e18);

        (uint256 amount,,,) = gauge.users(alice);
        assertEq(amount, 500 *1e18);
        assertEq(sCURToken.balanceOf(alice), 500 * 1e18);
        assertEq(sCURToken.balanceOf(address(gauge)), 500 * 1e18);

    }

    function test_EnterGauge_InsufficientAmount() public {
        vm.prank(alice);
        staking.stake(500 * 1e18);
        
        vm.prank(alice);
        vm.expectRevert(CURStaking.InsufficientAmount.selector);
        staking.enterGauge(600 * 1e18);
    
    }
    
    function test_EnterGauge_ZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(CURStaking.ZeroAmount.selector);
        staking.enterGauge(0);
    }

    
    function test_EnterGauge_Event() public {
        vm.prank(alice);
        staking.stake(1000 * 1e18);
        
        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit EnterGauge(alice, 500 * 1e18);
        staking.enterGauge(500 * 1e18);
    }
    
    // ============================================
    // ExitGauge Tests
    // ============================================
    
    function test_ExitGauge_success() public {
        vm.prank(alice);
        staking.stake(1000 * 1e18);
        vm.prank(alice);
        staking.enterGauge(500 * 1e18);
        
        vm.prank(alice);
        staking.exitGauge(500 * 1e18);
        
        (uint256 stakedSCUR, uint256 depositedGauge) = staking.getUserInfo(alice);
        assertEq(stakedSCUR, 1000 * 1e18);
        assertEq(depositedGauge, 0);

        (uint256 amount,,,) = gauge.users(alice);
        assertEq(amount, 0);
        assertEq(sCURToken.balanceOf(alice), 1000 * 1e18);
        assertEq(staking.getTotalStaked(), 1000 * 1e18);
    }
    
    function test_ExitGauge_ZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(CURStaking.ZeroAmount.selector);
        staking.exitGauge(0);
    }
    
    function test_ExitGauge_InsufficientAmount() public {
        vm.prank(alice);
        staking.stake(1000 * 1e18);
        vm.prank(alice);
        staking.enterGauge(500 * 1e18);
        
        vm.prank(alice);
        vm.expectRevert(CURStaking.InsufficientAmount.selector);
        staking.exitGauge(600 * 1e18);
    }
    
    function test_ExitGauge_Event() public {
        vm.prank(alice);
        staking.stake(1000 * 1e18);

        vm.prank(alice);
        staking.enterGauge(500 * 1e18);

        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit ExitGauge(alice, 500 * 1e18);
        staking.exitGauge(500 * 1e18);
    }

    // ============================================
    // emergencyWithdraw Tests
    // ============================================

    function test_emergencyWithdraw_Success() public {
        uint256 stakeAmount = 1000 * 1e18; 

        vm.prank(alice);
        staking.stake(stakeAmount);

        vm.prank(alice);
        staking.enterGauge(stakeAmount);

        vm.prank(owner);
        staking.pause();

        vm.prank(alice);
        staking.emergencyWithdraw();
        (uint256 stakedSCUR, uint256 depositedGauge) = staking.getUserInfo(alice);
        assertEq(stakedSCUR, 0);
        assertEq(depositedGauge, 0);

        (uint256 afterAmount,,, uint256 afterPendingRewards) = gauge.users(alice);
       
        assertEq(afterAmount, 0);
        assertEq(afterPendingRewards, 0);

        assertEq(staking.getTotalStaked(), 0);
        assertEq(sCURToken.totalSupply(), 0);
        
      
    }

    function test_emergencyWithdraw_Event() public {
        uint256 stakeAmount = 1000 * 1e18; 

        vm.prank(alice);
        staking.stake(stakeAmount);

        vm.prank(alice);
        staking.enterGauge(stakeAmount);

        vm.prank(owner);
        staking.pause();

        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit EmergencyWithdrawn(alice, stakeAmount, stakeAmount);
        staking.emergencyWithdraw();
    }
    
    function test_emergencyWithdraw_WhenNotPaused() public {
        assertFalse(staking.paused());

        vm.prank(alice);
        vm.expectRevert();
        staking.emergencyWithdraw();
    }

    function test_emergencyWithdraw_NoAssets() public {
        vm.prank(owner);
        staking.pause();

        vm.prank(bob);
        vm.expectRevert(CURStaking.NoAssets.selector);
        staking.emergencyWithdraw();
    }

    function test_emergencyWithdraw_OnlyOwnerCanPause() public {
        vm.prank(alice);
        vm.expectRevert();
        staking.pause();
    }

    // ============================================
    // withdrawPenalty Tests
    // ============================================
    function test_withdrawPenalty_Success() public {
        uint256 penaltyAmount = 500 * 1e18;

        vm.prank(owner);
        curToken.transfer(address(staking), penaltyAmount);

        uint256 beforeCUR = curToken.balanceOf(address(revenuePool));
        uint256 beforeStaking = curToken.balanceOf(address(staking));

        vm.prank(address(gauge));
        staking.withdrawPenalty(penaltyAmount);

        assertEq(curToken.balanceOf(address(revenuePool)), beforeCUR + penaltyAmount);
        assertEq(curToken.balanceOf(address(staking)), beforeStaking - penaltyAmount);
    }

    function test_withdrawPenalty_Event() public {
        uint256 penaltyAmount = 500 * 1e18;
        
        vm.prank(owner);
        curToken.transfer(address(staking), penaltyAmount);

        vm.prank(address(gauge));
        vm.expectEmit(true, false, false, true);
        emit PenaltyWithdrawn(address(revenuePool), penaltyAmount);
        staking.withdrawPenalty(penaltyAmount);
    }

    function test_withdrawPenalty_WhenUnauthorized() public {
        uint256 penaltyAmount = 500 * 1e18;

        vm.prank(alice);
        vm.expectRevert(CURStaking.Unauthorized.selector);
        staking.withdrawPenalty(penaltyAmount);
    }

    function test_withdrawPenalty_WhenZeroAmount() public {
        vm.prank(address(gauge));
        vm.expectRevert(CURStaking.ZeroAmount.selector);
        staking.withdrawPenalty(0);
    }

    function test_withdrawPenalty_WhenInsufficientCURBalance() public {
        uint256 penaltyAmount = 100_000_000 * 1e18; // 超过 Staking 余额

        vm.prank(address(gauge));
        vm.expectRevert(CURStaking.InsufficientCURBalance.selector);
        staking.withdrawPenalty(penaltyAmount);
    }

    function test_withdrawPenalty_MultipleWithdrawals() public {
        uint256 penaltyAmount1 = 200 * 1e18;
        uint256 penaltyAmount2 = 300 * 1e18;
        uint256 totalPenalty = penaltyAmount1 + penaltyAmount2;
        
        vm.prank(owner);
        curToken.transfer(address(staking), totalPenalty);

        uint256 beforeRevenue = curToken.balanceOf(address(revenuePool));

        vm.prank(address(gauge));
        staking.withdrawPenalty(penaltyAmount1);

        vm.prank(address(gauge));
        staking.withdrawPenalty(penaltyAmount2);

        assertEq(curToken.balanceOf(address(revenuePool)), beforeRevenue + totalPenalty);
    }

    
    // ============================================
    // View Function Tests
    // ============================================
    
    function test_GetUserInfo_ReturnsCorrectData() public {
        uint256 stakeAmount = 1000 * 1e18;
        uint256 gaugeAmount = 400 * 1e18;
        
        vm.prank(alice);
        staking.stake(stakeAmount);
        
        vm.prank(alice);
        staking.enterGauge(gaugeAmount);
        
        (uint256 stakedSCUR, uint256 depositedGauge) = staking.getUserInfo(alice);
    
        assertEq(stakedSCUR, stakeAmount);
        assertEq(depositedGauge, gaugeAmount);
    }

    function test_GetTotalStaked_ReturnsCorrectAmount() public {
        vm.prank(alice);
        staking.stake(1000 * 1e18);
        
        vm.prank(bob);
        staking.stake(2000 * 1e18);
        
        assertEq(staking.getTotalStaked(), 3000 * 1e18);
    }


    // ============================================
    // Pause Tests
    // ============================================
    
    function test_Pause() public {
        vm.prank(owner);
        staking.pause();
        
        assertTrue(staking.paused());
    }
    
    function test_Unpause() public {
        vm.prank(owner);
        staking.pause();
        
        vm.prank(owner);
        staking.unpause();
        
        assertFalse(staking.paused());
    }
    
    function test_Pause_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        staking.pause();
    }
    
    function test_Stake_WhenPaused() public {
        vm.prank(owner);
        staking.pause();
        
        vm.prank(alice);
        vm.expectRevert();
        staking.stake(1000 * 1e18);
    }
    
    function test_Unstake_WhenPaused() public {
        vm.prank(alice);
        staking.stake(1000 * 1e18);
        
        vm.prank(owner);
        staking.pause();
        
        vm.prank(alice);
        vm.expectRevert();
        staking.unstake(500 * 1e18);
    }

    function test_EnterGauge_WhenPaused() public {
        vm.prank(alice);
        staking.stake(1000 * 1e18);
        
        vm.prank(owner);
        staking.pause();
        
        vm.prank(alice);
        vm.expectRevert();
        staking.enterGauge(500 * 1e18);
    }
     
    function test_ExitGauge_WhenPaused() public {
        vm.prank(alice);
        staking.stake(1000 * 1e18);
        vm.prank(alice);
        staking.enterGauge(500 * 1e18);
        
        vm.prank(owner);
        staking.pause();
        
        vm.prank(alice);
        vm.expectRevert();
        staking.exitGauge(500 * 1e18);
    }

    function test_withdrawPenalty_WhenPaused() public {
        uint256 penaltyAmount = 500 * 1e18;

        vm.prank(owner);
        curToken.transfer(address(staking), penaltyAmount);

        vm.prank(owner);
        staking.pause();

        vm.prank(address(gauge));
        vm.expectRevert(); 
        staking.withdrawPenalty(penaltyAmount);
    }


       
    // ============================================
    // Admin Function Tests
    // ============================================
    
    function test_SetGauge_Success() public {
        address newGauge = makeAddr("newGauge");
        
        vm.prank(owner);
        staking.setGauge(newGauge);
        
        assertEq(address(staking.gauge()), newGauge);
    }
    
    function test_SetGauge_RevertsWhenZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(CURStaking.ZeroAddress.selector);
        staking.setGauge(address(0));
    }
    
    function test_SetGauge_RevertsWhenNotOwner() public {
        address newGauge = makeAddr("newGauge");
        
        vm.prank(alice);
        vm.expectRevert();
        staking.setGauge(newGauge);
    }
    
    function test_SetVeLock_Success() public {
        address newVeLock = makeAddr("newVeLock");
        
        vm.prank(owner);
        staking.setVeLock(newVeLock);
        
        assertEq(address(staking.veLock()), newVeLock);
    }
    
    function test_SetVeLock_WhenZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(CURStaking.ZeroAddress.selector);
        staking.setVeLock(address(0));
    }
    
    function test_SetVeLock_WhenNotOwner() public {
        address newVeLock = makeAddr("newVeLock");
        
        vm.prank(alice);
        vm.expectRevert();
        staking.setVeLock(newVeLock);
    }
    
    // ============================================
    // Edge Cases Tests
    // ============================================
    
    function test_EdgeCase_StakeAndUnstakeMultipleTimes() public {
        uint256 amount = 100 * 1e18;
        
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(alice);
            staking.stake(amount);
            
            vm.prank(alice);
            staking.unstake(amount);
        }
        
        assertEq(staking.getTotalStaked(), 0);
        assertEq(sCURToken.balanceOf(alice), 0);
    }
    
    function test_EdgeCase_EnterAndExitGaugeMultipleTimes() public {
        uint256 stakeAmount = 1000 * 1e18;
        uint256 gaugeAmount = 500 * 1e18;
        
        vm.prank(alice);
        staking.stake(stakeAmount);
        
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(alice);
            staking.enterGauge(gaugeAmount);
            
            vm.prank(alice);
            staking.exitGauge(gaugeAmount);
        }
        
        (, uint256 depositedGauge) = staking.getUserInfo(alice);
        assertEq(depositedGauge, 0);
    }
    
    function test_EdgeCase_StakeMaximumAmount() public {
        uint256 maxAmount = curToken.balanceOf(alice);
        
        vm.prank(alice);
        staking.stake(maxAmount);
        
        assertEq(staking.getTotalStaked(), maxAmount);
        assertEq(curToken.balanceOf(alice), 0);
    }
    
    // ============================================
    // Fuzz Tests
    // ============================================
    
    function test_Fuzz_Stake(uint256 curAmount) public {
        curAmount = bound(curAmount, 1, 10000 * 1e18);
        
        vm.prank(alice);
        staking.stake(curAmount);

        (uint256 stakedSCUR,) = staking.getUserInfo(alice);
        assertEq(stakedSCUR, curAmount);
        assertEq(staking.getTotalStaked(), curAmount);
    }
    
    function test_Fuzz_StakeAndUnstake(uint256 curAmount) public {
        curAmount = bound(curAmount, 1, 10000 * 1e18);
        
        vm.prank(alice);
        staking.stake(curAmount);
        
        vm.prank(alice);
        staking.unstake(curAmount);
        
        (uint256 stakedSCUR, uint256 depositedGauge) = staking.getUserInfo(alice);
        assertEq(stakedSCUR, 0);
        assertEq(depositedGauge, 0);
        assertEq(staking.getTotalStaked(), 0);
    }
    
    function test_Fuzz_EnterAndExitGauge(uint256 stakeAmount, uint256 gaugeAmount) public {
        stakeAmount = bound(stakeAmount, 1, 10000 * 1e18);
        gaugeAmount = bound(gaugeAmount, 1, stakeAmount);
        
        vm.prank(alice);
        staking.stake(stakeAmount);
        
        vm.prank(alice);
        staking.enterGauge(gaugeAmount);
        
        (, uint256 depositedGauge) = staking.getUserInfo(alice);
        assertEq(depositedGauge, gaugeAmount);
        
        vm.prank(alice);
        staking.exitGauge(gaugeAmount);
        
        (, depositedGauge) = staking.getUserInfo(alice);
        assertEq(depositedGauge, 0);
    }

}