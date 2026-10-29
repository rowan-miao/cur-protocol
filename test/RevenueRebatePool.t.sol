// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/core/CURToken.sol";
import "../src/core/sCUR.sol";
import "../src/core/CURStaking.sol";
import "../src/modules/RevenueRebatePool.sol";

// ============================================
// Mock Contracts
// ============================================

contract MockIncentiveGauge {
    IsCUR public sCURToken;

    constructor(address _sCURToken) {
        sCURToken = IsCUR(_sCURToken);
    }

    function deposit(address user, uint256 amount) external {}

    function withdraw(address user, uint256 amount) external {
        sCURToken.transfer(user, amount);
    }

    function getUserAmount(address user) external view returns (uint256) {
        return 0;
    }

    function gaugeEmergencyWithdraw(address user) external {}

    function emergencyClearReward(address user) external {}
}

contract MockVeCURLock {
    mapping(address => bool) public locked;

    function setLocked(address user, bool _locked) external {
        locked[user] = _locked;
    }

    function isLocked(address user) external view returns (bool) {
        return locked[user];
    }
}

contract RevenueRebatePoolTest is Test {
    CURToken public curToken;
    sCUR public sCURToken;
    RevenueRebatePool public revenuePool;
    MockIncentiveGauge public gauge;
    MockVeCURLock public veLock;
    CURStaking public staking;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    uint256 public constant PRECISION = 1e18;
    uint256 public constant DEFAULT_THRESHOLD = 1000 * 1e18;

    event RevenueDeposited(address indexed user, uint256 amount);
    event RevenueInjected(uint256 amount);
    event RevenueInjectedAll(uint256 amount);
    event ThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event UnallocatedEmissionRecorded(uint256 amount);
    event GaugeUpdated(address indexed oldGauge, address indexed newGauge);

    // ============================================
    // Setup
    // ============================================
    function setUp() public {
        vm.startPrank(owner);

        curToken = new CURToken();
        sCURToken = new sCUR(address(curToken), address(0));
        gauge = new MockIncentiveGauge(address(sCURToken));
        veLock = new MockVeCURLock();

        staking = new CURStaking(address(curToken), address(sCURToken), address(gauge), address(veLock), address(0));

        revenuePool = new RevenueRebatePool(address(curToken), address(sCURToken), address(staking));

        staking.setRevenueRebatePool(address(revenuePool));
        revenuePool.setGauge(address(gauge));

        sCURToken.addMinter(address(staking));
        sCURToken.addMinter(address(revenuePool));

        curToken.transfer(alice, 10_000 * 1e18);
        curToken.transfer(bob, 10_000 * 1e18);
        curToken.transfer(charlie, 10_000 * 1e18);

        vm.stopPrank();

        vm.prank(alice);
        curToken.approve(address(revenuePool), type(uint256).max);
        vm.prank(bob);
        curToken.approve(address(revenuePool), type(uint256).max);
        vm.prank(charlie);
        curToken.approve(address(revenuePool), type(uint256).max);

        vm.prank(alice);
        curToken.approve(address(staking), type(uint256).max);
    }

    // ============================================
    // Constructor Tests
    // ============================================

    function test_constructor_SetsCorrectState() public view {
        assertEq(address(revenuePool.curToken()), address(curToken));
        assertEq(address(revenuePool.sCURToken()), address(sCURToken));
        assertEq(revenuePool.totalRevenue(), 0);
        assertEq(revenuePool.totalUnallocatedEmission(), 0);
        assertEq(revenuePool.threshold(), DEFAULT_THRESHOLD);
        assertEq(revenuePool.owner(), owner);
    }

    function test_constructor_RevertsWhenCurTokenZero() public {
        vm.prank(owner);
        vm.expectRevert(RevenueRebatePool.ZeroAddress.selector);
        new RevenueRebatePool(address(0), address(sCURToken), address(staking));
    }

    function test_constructor_RevertsWhenSCURZero() public {
        vm.prank(owner);
        vm.expectRevert(RevenueRebatePool.ZeroAddress.selector);
        new RevenueRebatePool(address(curToken), address(0), address(staking));
    }

    function test_Constructor_RevertsWhenCurStakingZero() public {
        vm.prank(owner);
        vm.expectRevert(RevenueRebatePool.ZeroAddress.selector);
        new RevenueRebatePool(address(curToken), address(sCURToken), address(0));
    }

    // ============================================
    // DepositRevenue Tests
    // ============================================

    function test_depositRevenue_Success() public {
        uint256 amount = 1000 * 1e18;

        uint256 beforeBalance = curToken.balanceOf(address(revenuePool));

        vm.prank(alice);
        revenuePool.depositRevenue(amount);

        assertEq(curToken.balanceOf(address(revenuePool)), beforeBalance + amount);
        assertEq(revenuePool.totalRevenue(), amount);
    }

    function test_depositRevenue_Event() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit RevenueDeposited(alice, amount);
        revenuePool.depositRevenue(amount);
    }

    function test_depositRevenue_ZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(RevenueRebatePool.ZeroAmount.selector);
        revenuePool.depositRevenue(0);
    }

    function test_depositRevenue_MultipleDeposits() public {
        uint256 amount1 = 500 * 1e18;
        uint256 amount2 = 300 * 1e18;

        vm.prank(alice);
        revenuePool.depositRevenue(amount1);

        vm.prank(bob);
        revenuePool.depositRevenue(amount2);
        assertEq(revenuePool.totalRevenue(), amount1 + amount2);
    }

    // ============================================
    // RecordUnallocatedEmission Tests
    // ============================================
    function test_recordUnallocatedEmission_success() public {
        uint256 amount = 500 * 1e18;

        vm.prank(address(gauge));
        revenuePool.recordUnallocatedEmission(amount);

        assertEq(revenuePool.totalUnallocatedEmission(), amount);
    }

    function test_RecordUnallocatedEmission_Event() public {
        uint256 amount = 500 * 1e18;

        vm.prank(address(gauge));
        vm.expectEmit(false, false, false, true);
        emit UnallocatedEmissionRecorded(amount);
        revenuePool.recordUnallocatedEmission(amount);
    }

    function test_RecordUnallocatedEmission_Unauthorized() public {
        vm.prank(alice);
        vm.expectRevert(RevenueRebatePool.Unauthorized.selector);
        revenuePool.recordUnallocatedEmission(500 * 1e18);
    }

    function test_RecordUnallocatedEmission_ZeroAmount() public {
        vm.prank(address(gauge));
        vm.expectRevert(RevenueRebatePool.ZeroAmount.selector);
        revenuePool.recordUnallocatedEmission(0);
    }

    function test_RecordUnallocatedEmission_Multiple() public {
        uint256 amount1 = 500 * 1e18;
        uint256 amount2 = 300 * 1e18;

        vm.prank(address(gauge));
        revenuePool.recordUnallocatedEmission(amount1);

        vm.prank(address(gauge));
        revenuePool.recordUnallocatedEmission(amount2);

        assertEq(revenuePool.totalUnallocatedEmission(), amount1 + amount2);
    }

    // ============================================
    // InjectToSCUR Tests
    // ============================================

    function test_injectToSCUR_Success() public {
        uint256 depositAmount = 1000 * 1e18;
        uint256 injectAmount = 500 * 1e18;

        vm.prank(alice);
        staking.stake(depositAmount);

        vm.prank(alice);
        revenuePool.depositRevenue(depositAmount);

        uint256 beforeRate = sCURToken.getExchangeRate();
        uint256 beforeStakingBalance = curToken.balanceOf(address(staking));

        vm.prank(owner);
        revenuePool.injectToSCUR(injectAmount);

        assertGt(sCURToken.getExchangeRate(), beforeRate);
        assertEq(curToken.balanceOf(address(staking)), beforeStakingBalance + injectAmount);
        assertEq(revenuePool.totalRevenue(), depositAmount - injectAmount);
    }

    function test_injectToSCUR_Event() public {
        uint256 depositAmount = 1000 * 1e18;
        uint256 injectAmount = 500 * 1e18;

        vm.prank(alice);
        staking.stake(depositAmount);

        vm.prank(alice);
        revenuePool.depositRevenue(depositAmount);

        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit RevenueInjected(injectAmount);
        revenuePool.injectToSCUR(injectAmount);
    }

    function test_injectToSCUR_ZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert(RevenueRebatePool.ZeroAmount.selector);
        revenuePool.injectToSCUR(0);
    }

    function test_injectToSCUR_ExceedsRevenue() public {
        uint256 depositAmount = 1000 * 1e18;

        vm.prank(owner);
        vm.expectRevert(RevenueRebatePool.ExceedsRevenue.selector);
        revenuePool.injectToSCUR(depositAmount);
    }

    function test_InjectToSCUR_NoSCURSupply() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(alice);
        revenuePool.depositRevenue(amount);

        vm.prank(owner);
        vm.expectRevert(RevenueRebatePool.NoSCURSupply.selector);
        revenuePool.injectToSCUR(amount);
    }

    function test_injectToSCUR_InsufficientBalance() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(alice);
        staking.stake(amount);

        vm.prank(alice);
        revenuePool.depositRevenue(amount);

        vm.prank(address(revenuePool));
        curToken.transfer(owner, amount);

        vm.prank(owner);
        vm.expectRevert(RevenueRebatePool.InsufficientBalance.selector);
        revenuePool.injectToSCUR(amount);
    }

    function test_InjectToSCUR_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        revenuePool.injectToSCUR(1000 * 1e18);
    }

    // ============================================
    // InjectAll Tests
    // ============================================

    function test_injectAll_Success() public {
        uint256 depositAmount = 1000 * 1e18;

        vm.prank(alice);
        staking.stake(depositAmount);

        vm.prank(alice);
        revenuePool.depositRevenue(depositAmount);

        vm.prank(owner);
        revenuePool.injectAll();

        assertEq(revenuePool.totalRevenue(), 0);
    }

    function test_injectAll_Event() public {
        uint256 depositAmount = 1000 * 1e18;

        vm.prank(alice);
        staking.stake(depositAmount);

        vm.prank(alice);
        revenuePool.depositRevenue(depositAmount);

        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit RevenueInjectedAll(depositAmount);
        revenuePool.injectAll();
    }

    function test_injectAll_BelowThreshold() public {
        uint256 depositAmount = 500 * 1e18;

        vm.prank(alice);
        staking.stake(depositAmount);

        vm.prank(alice);
        revenuePool.depositRevenue(depositAmount);

        vm.prank(owner);
        vm.expectRevert(RevenueRebatePool.BelowThreshold.selector);
        revenuePool.injectAll();
    }

    function test_InjectAll_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        revenuePool.injectAll();
    }

    // ============================================
    // SetThreshold Tests
    // ============================================
    function test_setNewthreshold_Success() public {
        uint256 newThreshold = 500 * 1e18;

        vm.prank(owner);
        revenuePool.setNewthreshold(newThreshold);

        assertEq(revenuePool.threshold(), newThreshold);
    }

    function test_setNetThreshold_Event() public {
        uint256 oldThreshold = revenuePool.threshold();
        uint256 newThreshold = 2000 * 1e18;

        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit ThresholdUpdated(oldThreshold, newThreshold);
        revenuePool.setNewthreshold(newThreshold);
    }

    function test_setNewthreshold_NotOwner() public {
        uint256 newThreshold = 500 * 1e18;

        vm.prank(alice);
        vm.expectRevert();
        revenuePool.setNewthreshold(newThreshold);
    }

    // ============================================
    // SetGauge Tests
    // ============================================

    function test_SetGauge_Success() public {
        address newGauge = makeAddr("newGauge");

        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit GaugeUpdated(address(gauge), newGauge);
        revenuePool.setGauge(newGauge);

        assertEq(address(revenuePool.gauge()), newGauge);
    }

    function test_SetGauge_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(RevenueRebatePool.ZeroAddress.selector);
        revenuePool.setGauge(address(0));
    }

    function test_SetGauge_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        revenuePool.setGauge(makeAddr("newGauge"));
    }

    function test_SetGauge_SelfAddress() public {
        vm.prank(owner);
        vm.expectRevert(RevenueRebatePool.InvalidAddress.selector);
        revenuePool.setGauge(address(revenuePool));
    }

    function test_SetGauge_SameAddress() public {
        address currentGauge = address(revenuePool.gauge());
        vm.prank(owner);
        vm.expectRevert(RevenueRebatePool.SameAddress.selector);
        revenuePool.setGauge(currentGauge);
    }

    // ============================================
    // GetContractBalance Tests
    // ============================================
    function test_GetContractBalance() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(alice);
        revenuePool.depositRevenue(amount);

        assertEq(revenuePool.getContractBalance(), amount);
    }

    // ============================================
    // Pause Tests
    // ============================================

    function test_pause_Success() public {
        vm.prank(owner);
        revenuePool.pause();

        assertTrue(revenuePool.paused());
    }

    function test_unpause_Success() public {
        vm.prank(owner);
        revenuePool.pause();

        vm.prank(owner);
        revenuePool.unpause();

        assertFalse(revenuePool.paused());
    }

    function test_Pause_FailsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        revenuePool.pause();
    }

    function test_Unpause_FailsIfNotOwner() public {
        vm.prank(owner);
        revenuePool.pause();

        vm.prank(alice);
        vm.expectRevert();
        revenuePool.unpause();
    }

    function test_DepositRevenue_WhenPaused() public {
        vm.prank(owner);
        revenuePool.pause();

        vm.prank(alice);
        vm.expectRevert();
        revenuePool.depositRevenue(1000 * 1e18);
    }

    function test_InjectToSCUR_WhenPaused() public {
        uint256 depositAmount = 1000 * 1e18;

        vm.prank(owner);
        revenuePool.pause();

        vm.prank(owner);
        vm.expectRevert();
        revenuePool.injectToSCUR(500 * 1e18);
    }

    // ============================================
    // Edge Case Tests
    // ============================================

    function test_EdgeCase_DepositAndInjectSameAmount() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(alice);
        staking.stake(amount);

        vm.prank(alice);
        revenuePool.depositRevenue(amount);

        vm.prank(owner);
        revenuePool.injectToSCUR(amount);

        assertEq(revenuePool.totalRevenue(), 0);
        assertEq(revenuePool.getContractBalance(), 0);
        assertEq(curToken.balanceOf(address(staking)), amount * 2);
    }

    function test_EdgeCase_InjectMoreThanDeposited() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(alice);
        staking.stake(amount);

        vm.prank(alice);
        revenuePool.depositRevenue(amount);

        vm.prank(owner);
        vm.expectRevert(RevenueRebatePool.ExceedsRevenue.selector);
        revenuePool.injectToSCUR(amount + 1);
    }

    function test_EdgeCase_ExactlyAtThreshold() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(alice);
        staking.stake(amount);

        vm.prank(alice);
        revenuePool.depositRevenue(amount);

        vm.prank(owner);
        revenuePool.injectAll();

        assertEq(revenuePool.totalRevenue(), 0);
    }

    function test_EdgeCase_ZeroThreshold() public {
        vm.prank(owner);
        vm.expectRevert(RevenueRebatePool.InvalidThreshold.selector);
        revenuePool.setNewthreshold(0);
    }

    function test_EdgeCase_InjectPartialThenInjectAll() public {
        uint256 amount = 2000 * 1e18;
        vm.prank(alice);
        staking.stake(amount);

        vm.prank(alice);
        revenuePool.depositRevenue(amount);

        vm.prank(owner);
        revenuePool.injectToSCUR(800 * 1e18);
        assertEq(revenuePool.totalRevenue(), 1200 * 1e18);

        vm.prank(owner);
        revenuePool.injectAll();
        assertEq(revenuePool.totalRevenue(), 0);
    }

    function test_EdgeCase_MultipleDepositsAndInjections() public {
        vm.prank(alice);
        staking.stake(1000 * 1e18);

        for (uint256 i = 0; i < 5; i++) {
            uint256 depositAmount = 200 * 1e18;
            uint256 injectAmount = 100 * 1e18;

            vm.prank(alice);
            revenuePool.depositRevenue(depositAmount);

            vm.prank(owner);
            revenuePool.injectToSCUR(injectAmount);
        }

        assertEq(revenuePool.totalRevenue(), 500 * 1e18);
    }

    function test_EdgeCase_ChangeThresholdAfterDeposit() public {
        uint256 amount = 600 * 1e18;
        vm.prank(alice);
        staking.stake(amount);

        vm.prank(alice);
        revenuePool.depositRevenue(amount);

        vm.prank(owner);
        vm.expectRevert(RevenueRebatePool.BelowThreshold.selector);
        revenuePool.injectAll();

        vm.prank(owner);
        revenuePool.setNewthreshold(500 * 1e18);

        vm.prank(owner);
        revenuePool.injectAll();
        assertEq(revenuePool.totalRevenue(), 0);
    }

    // ============================================
    // Fuzz Tests
    // ============================================

    function test_Fuzz_DepositRevenue(uint256 amount) public {
        amount = bound(amount, 1, 10000 * 1e18);
        uint256 beforeTotalRevenue = revenuePool.totalRevenue();

        vm.prank(alice);
        revenuePool.depositRevenue(amount);

        assertEq(revenuePool.totalRevenue(), beforeTotalRevenue + amount);
    }

    function test_Fuzz_InjectToSCUR(uint256 depositAmount, uint256 injectAmount) public {
        address user = makeAddr("fuzzUser");
        depositAmount = bound(depositAmount, 1e12, 10_000 * 1e18);
        injectAmount = bound(injectAmount, 1, depositAmount);

        vm.prank(owner);
        curToken.transfer(user, depositAmount * 2);

        vm.prank(user);
        curToken.approve(address(staking), type(uint256).max);
        vm.prank(user);
        curToken.approve(address(revenuePool), type(uint256).max);

        vm.prank(user);
        staking.stake(depositAmount);

        vm.prank(user);
        revenuePool.depositRevenue(depositAmount);

        uint256 beforeTotal = revenuePool.totalRevenue();

        vm.prank(owner);
        revenuePool.injectToSCUR(injectAmount);

        assertEq(revenuePool.totalRevenue(), beforeTotal - injectAmount);
    }
}
