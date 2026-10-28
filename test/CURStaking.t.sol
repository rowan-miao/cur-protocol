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

    function getRemainingRewards() external pure returns (uint256) {
        return 0;
    }

    function getCurrentEmissionRate() external pure returns (uint256) {
        return 0;
    }

    function setUserAmount(address user, uint256 amount) external {
        users[user].amount = amount;
    }

    function getUserAmount(address user) public view returns (uint256) {
        return users[user].amount;
    }

    function paused() external pure returns (bool) {
        return false;
    }
}

contract MockVeCURLock {
    mapping(address => bool) public locked;

    function setLocked(address user, bool _locked) external {
        locked[user] = _locked;
    }

    function isLocked(address user) external view returns (bool) {
        return locked[user];
    }

    function emergencyBreakLock(address user) external view returns (uint256) {
        return 0; 
    }

    function paused() external pure returns (bool) {
        return false;
    }
}

contract MockRevenueRebatePool {}

contract CURStakingTest is Test {
    CURStaking public staking;
    CURToken public curToken;
    sCUR public sCURToken;
    MockIncentiveGauge public gauge;
    MockVeCURLock public veLock;
    MockRevenueRebatePool public revenuePool;

    uint256 public constant INITIAL_BALANCE = 100_000 * 1e18;

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
    event EmergencyWithdrawn(address indexed user, uint256 totalSCUR, uint256 actualSCURRedeemed);
    event PenaltyExecuted(address indexed user, uint256 CURAmount);
    event GaugeUpdated(address indexed oldAddress, address indexed newAddress);
    event VeLockUpdated(address indexed oldAddress, address indexed newAddress);
    event RevenueRebatePoolUpdated(address indexed oldAddress, address indexed newAddress);

    // ============================================
    // Setup
    // ============================================
    function setUp() public {
        vm.startPrank(owner);

        curToken = new CURToken();

        sCURToken = new sCUR(address(curToken), address(0));

        gauge = new MockIncentiveGauge(address(sCURToken));

        veLock = new MockVeCURLock();

        revenuePool = new MockRevenueRebatePool();

        staking = new CURStaking(
            address(curToken), address(sCURToken), address(gauge), address(veLock), address(revenuePool)
        );

        sCURToken.addMinter(address(staking));
        sCURToken.addMinter(address(this));

        vm.stopPrank();

        vm.startPrank(owner);

        curToken.transfer(alice, INITIAL_BALANCE);
        curToken.transfer(bob, INITIAL_BALANCE);
        curToken.transfer(charlie, INITIAL_BALANCE);

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

    function test_Constructor_AllowsZeroDependencies() public {
        vm.prank(owner);
        CURStaking newStaking =
            new CURStaking(address(curToken), address(sCURToken), address(0), address(0), address(0));

        assertEq(address(newStaking.curToken()), address(curToken));
        assertEq(address(newStaking.sCURToken()), address(sCURToken));
        assertEq(address(newStaking.gauge()), address(0));
        assertEq(address(newStaking.veLock()), address(0));
        assertEq(address(newStaking.revenueRebatePool()), address(0));
        assertEq(newStaking.owner(), owner);
    }

    // ============================================
    // Stake Tests
    // ============================================

    function test_Stake_Success() public {
        uint256 curAmount = 1000 * 1e18;

        uint256 beforeSCUR = sCURToken.balanceOf(alice);
        uint256 beforeCUR = curToken.balanceOf(address(staking));

        vm.prank(alice);
        staking.stake(curAmount);

        uint256 expectedSCUR = (curAmount * PRECISION) / sCURToken.getExchangeRate();

        assertEq(sCURToken.balanceOf(alice), beforeSCUR + expectedSCUR);
        assertEq(curToken.balanceOf(address(staking)), beforeCUR + curAmount);
    }

    function test_Stake_ZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(CURStaking.ZeroAmount.selector);
        staking.stake(0);
    }

    function test_Stake_BelowMinimumStake(uint256) public {
        uint256 minimumStake = staking.getMinimumStakeAmount();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(CURStaking.BelowMinimumStake.selector, minimumStake));
        staking.stake(minimumStake - 1);
    }

    function test_Stake_AfterExchangeRateGrowth() public {
        vm.prank(alice);
        staking.stake(1000 * 1e18);
    
        sCURToken.updateExchangeRate(500 * 1e18);

        assertEq(sCURToken.getExchangeRate(), 1.5e18);
 
        vm.prank(bob);
        staking.stake(1500 * 1e18);
    
        assertEq(sCURToken.balanceOf(bob), 1000 * 1e18);
    }

    function test_Stake_Event() public {
        uint256 curAmount = 1000 * 1e18;
        uint256 expectedSCUR = (curAmount * PRECISION) / sCURToken.getExchangeRate();

        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit Staked(alice, curAmount, expectedSCUR);
        staking.stake(curAmount);
    }

    // ============================================
    // Unstake Tests
    // ============================================

    function test_Unstake_success() public {
        uint256 curAmount = 1000 * 1e18;

        vm.prank(alice);
        staking.stake(curAmount);

        uint256 beforeCUR = curToken.balanceOf(alice);
        uint256 beforeSCUR = sCURToken.balanceOf(alice);

        vm.prank(alice);
        staking.unstake(curAmount);

        assertEq(sCURToken.balanceOf(alice), beforeSCUR - curAmount);
        assertEq(curToken.balanceOf(alice), beforeCUR + curAmount);
    }

    function test_Unstake_ZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(CURStaking.ZeroAmount.selector);
        staking.unstake(0);
    }

    function test_Unstake_WhenLocked() public {
        uint256 curAmount = 1000 * 1e18;

        vm.prank(alice);
        staking.stake(curAmount);

        veLock.setLocked(alice, true);

        vm.prank(alice);
        vm.expectRevert(CURStaking.PositionLocked.selector);
        staking.unstake(curAmount);
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

    function test_Unstake_Partial() public {
        uint256 curAmount = 1000 * 1e18;
        uint256 unstakeAmount = 400 * 1e18;

        vm.prank(alice);
        staking.stake(curAmount);

        vm.prank(alice);
        staking.unstake(unstakeAmount);

        assertEq(sCURToken.balanceOf(alice), curAmount - unstakeAmount);
        assertEq(curToken.balanceOf(address(staking)), curAmount - unstakeAmount);
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

        assertEq(sCURToken.balanceOf(alice), 500 * 1e18);
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

    function test_EnterGauge_WhenLocked() public {
        vm.prank(alice);
        staking.stake(1000 * 1e18);

        veLock.setLocked(alice, true);

        vm.prank(alice);
        vm.expectRevert(CURStaking.PositionLocked.selector);
        staking.enterGauge(1000 * 1e18);
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

        assertEq(sCURToken.balanceOf(alice), 1000 * 1e18);
    }

    function test_ExitGauge_ZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(CURStaking.ZeroAmount.selector);
        staking.exitGauge(0);
    }

    function test_ExitGauge_WhenLocked() public {
        vm.prank(alice);
        staking.stake(1000 * 1e18);

        vm.prank(alice);
        staking.enterGauge(1000 * 1e18);

        veLock.setLocked(alice, true);

        vm.prank(alice);
        vm.expectRevert(CURStaking.PositionLocked.selector);
        staking.exitGauge(1000 * 1e18);
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

        vm.prank(owner);
        staking.pause();

        uint256 beforeCUR = curToken.balanceOf(alice);

        vm.prank(alice);
        staking.emergencyWithdraw();

        assertEq(curToken.balanceOf(alice), beforeCUR + stakeAmount);
        assertEq(sCURToken.balanceOf(alice), 0);
    }

    function test_emergencyWithdraw_Event() public {
        uint256 stakeAmount = 1000 * 1e18;

        vm.prank(alice);
        staking.stake(stakeAmount);

        vm.prank(owner);
        staking.pause();

        uint256 aliceSCUR = sCURToken.balanceOf(alice);
        uint256 expectedActualSCUR = aliceSCUR;

        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit EmergencyWithdrawn(alice, aliceSCUR, expectedActualSCUR);
        staking.emergencyWithdraw();
    }

    function test_emergencyWithdraw_WhenNotPaused() public {
        assertFalse(staking.paused());

        vm.prank(alice);
        vm.expectRevert(CURStaking.SystemNotPaused.selector);
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
    function test_ExecutePenalty_Success() public {
        uint256 CURAmount = 1000 * 1e18;
        uint256 curAmount = 200 * 1e18;

        vm.prank(alice);
        staking.stake(CURAmount);

        vm.prank(alice);
        staking.enterGauge(CURAmount);

        uint256 initialRevenueBalance = curToken.balanceOf(address(revenuePool));
        uint256 initialStakingBalance = curToken.balanceOf(address(staking));

        vm.prank(address(gauge));
        staking.executePenalty(alice, curAmount);

        assertEq(curToken.balanceOf(address(revenuePool)), initialRevenueBalance + curAmount);
        assertEq(curToken.balanceOf(address(staking)), initialStakingBalance - curAmount);
    }

    function test_ExecutePenalty_Event() public {
        uint256 CURAmount = 1000 * 1e18;
        uint256 curAmount = 200 * 1e18;

        vm.prank(alice);
        staking.stake(CURAmount);

        vm.prank(alice);
        staking.enterGauge(CURAmount);

        vm.prank(address(gauge));
        vm.expectEmit(true, false, false, true);
        emit PenaltyExecuted(alice, curAmount);
        staking.executePenalty(alice, curAmount);
    }

    function test_ExecutePenalty_ZeroAmount() public {
        vm.prank(address(gauge));
        vm.expectRevert(CURStaking.ZeroAmount.selector);
        staking.executePenalty(alice, 0);
    }

    function test_ExecutePenalty_RevertNotGauge() public {
        uint256 CURAmount = 1000 * 1e18;
        uint256 curAmount = 200 * 1e18;

        vm.prank(alice);
        staking.stake(CURAmount);

        vm.prank(alice);
        vm.expectRevert(CURStaking.Unauthorized.selector);
        staking.executePenalty(alice, curAmount);
    }

    // ============================================
    // View Function Tests
    // ============================================

    function test_GetTotalStaked_ReturnsCorrectAmount() public {
        vm.prank(alice);
        staking.stake(1000 * 1e18);

        vm.prank(bob);
        staking.stake(2000 * 1e18);

        assertEq(staking.getTotalStaked(), 3000 * 1e18);
    }

    function test_GetMinimumStakeAmount() public view {
        uint256 minimum = staking.getMinimumStakeAmount();

        assertGe(minimum, staking.MIN_STAKE_CUR());
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
        staking.unstake(500 * 1e18);
        assertEq(sCURToken.balanceOf(alice), 500 * 1e18);
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
        staking.exitGauge(500 * 1e18);

        assertEq(sCURToken.balanceOf(alice), 1000 * 1e18);
    }

    // ============================================
    // Admin Function Tests
    // ============================================

    function test_SetGauge_Success() public {
        address newGauge = makeAddr("newGauge");

        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit GaugeUpdated(address(gauge), newGauge);
        staking.setGauge(newGauge);

        assertEq(address(staking.gauge()), newGauge);
    }

    function test_SetGauge_RevertsWhenZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(CURStaking.ZeroAddress.selector);
        staking.setGauge(address(0));
    }

    function test_SetGauge_RevertsWhenSelfAddress() public {
        vm.prank(owner);
        vm.expectRevert(CURStaking.InvalidAddress.selector);
        staking.setGauge(address(staking)); 
    }

    function test_SetGauge_RevertsWhenSameAddress() public {
        vm.prank(owner);
        vm.expectRevert(CURStaking.SameAddress.selector);
        staking.setGauge(address(gauge));
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
        vm.expectEmit(true, true, false, true);
        emit VeLockUpdated(address(veLock), newVeLock);
        staking.setVeLock(newVeLock);

        assertEq(address(staking.veLock()), newVeLock);
    }

    function test_SetVeLock_WhenZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(CURStaking.ZeroAddress.selector);
        staking.setVeLock(address(0));
    }

    function test_SetVeLock_RevertsWhenSelfAddress() public {
        vm.prank(owner);
        vm.expectRevert(CURStaking.InvalidAddress.selector);
        staking.setVeLock(address(staking)); 
    }

    function test_SetVeLock_RevertsWhenSameAddress() public {
        vm.prank(owner);
        vm.expectRevert(CURStaking.SameAddress.selector);
        staking.setVeLock(address(veLock));
    }

    function test_SetVeLock_WhenNotOwner() public {
        address newVeLock = makeAddr("newVeLock");

        vm.prank(alice);
        vm.expectRevert();
        staking.setVeLock(newVeLock);
    }

    function test_SetRevenueRebatePool_Success() public {
        address newPool = makeAddr("newPool");

        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit RevenueRebatePoolUpdated(address(revenuePool), newPool);
        staking.setRevenueRebatePool(newPool);

        assertEq(address(staking.revenueRebatePool()), newPool);
    }

    function test_SetRevenueRebatePool_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(CURStaking.ZeroAddress.selector);
        staking.setRevenueRebatePool(address(0));
    }

    function test_SetRevenueRebatePool_RevertsWhenSelfAddress() public {
        vm.prank(owner);
        vm.expectRevert(CURStaking.InvalidAddress.selector);
        staking.setRevenueRebatePool(address(staking));
    }

    function test_SetRevenueRebatePool_RevertsWhenSameAddress() public {
        vm.prank(owner);
        vm.expectRevert(CURStaking.SameAddress.selector);
        staking.setRevenueRebatePool(address(revenuePool));
    }

    function test_SetRevenueRebatePool_RevertsWhenNotOwner() public {
        address newPool = makeAddr("newPool");

        vm.prank(alice);
        vm.expectRevert();
        staking.setRevenueRebatePool(newPool);
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
        assertEq(curToken.balanceOf(address(staking)), 0);
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

        uint256 gaugeBalance = sCURToken.balanceOf(address(gauge));
        assertEq(gaugeBalance, 0);
        assertEq(sCURToken.balanceOf(alice), stakeAmount);
    }

    function test_EdgeCase_StakeMaximumAmount() public {
        uint256 maxAmount = curToken.balanceOf(alice);

        uint256 minimum = staking.getMinimumStakeAmount();
        assertGe(maxAmount, minimum);

        vm.prank(alice);
        staking.stake(maxAmount);

        assertEq(staking.getTotalStaked(), maxAmount);
        assertEq(curToken.balanceOf(alice), 0);
    }

    // ============================================
    // Fuzz Tests
    // ============================================

    function test_Fuzz_Stake(uint256 CURAmount) public {
        uint256 minimum = staking.getMinimumStakeAmount();
        CURAmount = bound(CURAmount, minimum, INITIAL_BALANCE);

        vm.prank(alice);
        staking.stake(CURAmount);

        assertGt(sCURToken.balanceOf(alice), 0);
        assertEq(curToken.balanceOf(address(staking)), CURAmount);
    }

    function testFuzz_StakeUnstake(uint256 CURAmount) public {
        uint256 minimum = staking.getMinimumStakeAmount();
        CURAmount = bound(CURAmount, minimum, INITIAL_BALANCE);

        uint256 beforeCUR = curToken.balanceOf(alice);

        // Stake
        vm.prank(alice);
        staking.stake(CURAmount);

        // Unstake
        vm.prank(alice);
        staking.unstake(CURAmount);

        // 验证余额恢复
        assertEq(curToken.balanceOf(alice), beforeCUR);
    }
}
