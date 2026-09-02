// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/core/CURToken.sol";
import "../src/core/sCUR.sol";
import "../src/modules/RevenueRebatePool.sol";

contract MockSCUR {
    uint256 public exchangeRate = 1e18;
    uint256 public totalUnderlying;
    address public lastCaller;
    uint256 public lastAmount;
    uint256 public totalSupply;

    event ExchangeRateUpdated(uint256 oldRate, uint256 newRate);
    
    function updateExchangeRate(uint256 additionalCUR) external returns (uint256) {
        lastCaller = msg.sender;
        lastAmount = additionalCUR;
        
        uint256 oldRate = exchangeRate;
        totalUnderlying += additionalCUR;

        if(totalSupply > 0){
            exchangeRate = (totalUnderlying * 1e18) / totalSupply;
        }
        
        emit ExchangeRateUpdated(oldRate, exchangeRate);
        return exchangeRate;
    }

    function getExchangeRate() external view returns(uint256){
        return exchangeRate;
    }

    function setTotalSupply(uint256 _supply) external {
        totalSupply = _supply;
    }


}

contract MockCURStaking {
    uint256 public receivedCUR;
    
    function getExchangeRate() external pure returns (uint256) {
        return 1e18;
    }
}


contract RevenueRebatePoolTest is Test {
    RevenueRebatePool public revenuePool;
    CURToken public curToken;
    MockSCUR public mockSCUR;
    MockCURStaking public staking;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public protocol = makeAddr("protocol");

    uint256 public constant PRECISION = 1e18;
    uint256 public constant DEFAULT_THRESHOLD = 1000 * 1e18;

    event RevenueDeposited(address indexed user, uint256 amount);
    event RevenueInjected(uint256 amount);
    event RevenueInjectedAll(uint256 amount);
    event ThresholdUpdated(uint256 newthreshold);

    // ============================================
    // Setup
    // ============================================
    function setUp() public {
        vm.startPrank(owner);

        curToken = new CURToken();
        mockSCUR = new MockSCUR();
        staking = new MockCURStaking();
        revenuePool = new RevenueRebatePool(address(curToken), address(mockSCUR), address(staking));
        curToken.transfer(protocol, 100000 * 1e18);

        vm.stopPrank();
    }

    // ============================================
    // Constructor Tests
    // ============================================

    function test_constructor_SetsCorrectState() public view {
        assertEq(address(revenuePool.curToken()), address(curToken));
        assertEq(address(revenuePool.sCURToken()), address(mockSCUR));
        assertEq(revenuePool.totalRevenue(), 0);
        assertEq(revenuePool.threshold(), DEFAULT_THRESHOLD);
        assertEq(revenuePool.owner(), owner);
    }

    function test_constructor_RevertsWhenCurTokenZero() public {
        vm.prank(owner);
        vm.expectRevert(RevenueRebatePool.ZeroAddress.selector);
        new RevenueRebatePool(address(0), address(mockSCUR), address(staking));
    }
    
    function test_constructor_RevertsWhenSCURZero() public {
        vm.prank(owner);
        vm.expectRevert(RevenueRebatePool.ZeroAddress.selector);
        new RevenueRebatePool(address(curToken), address(0), address(staking));
    }

    function test_Constructor_RevertsWhenCurStakingZero() public {
        vm.prank(owner);
        vm.expectRevert(RevenueRebatePool.ZeroAddress.selector);
        new RevenueRebatePool(address(curToken), address(mockSCUR), address(0));
    }

    // ============================================
    // DepositRevenue Tests
    // ============================================

    function test_depositRevenue_Success() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(protocol);
        curToken.approve(address(revenuePool), amount);
        uint256 beforeBalance = curToken.balanceOf(address(revenuePool));
        uint256 beforeTotalRevenue = revenuePool.totalRevenue();

        vm.prank(protocol);
        revenuePool.depositRevenue(amount);

        assertEq(curToken.balanceOf(address(revenuePool)), beforeBalance + amount);
        assertEq(revenuePool.totalRevenue(), beforeTotalRevenue + amount);

    }

    function test_depositRevenue_Event() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(protocol);
        curToken.approve(address(revenuePool), amount);

        vm.prank(protocol);
        vm.expectEmit(true, false, false, true);
        emit RevenueDeposited(protocol, amount);
        revenuePool.depositRevenue(amount);

    }
    
    function test_depositRevenue_ZeroAmount() public {
        vm.prank(protocol);
        vm.expectRevert(RevenueRebatePool.ZeroAmount.selector);
        revenuePool.depositRevenue(0);

    }

    function test_depositRevenue_MultipleDeposits() public {
        uint256 amount1 = 500 * 1e18;
        uint256 amount2 = 300 * 1e18;

        vm.startPrank(protocol);
        curToken.approve(address(revenuePool), amount1 + amount2);
        
        revenuePool.depositRevenue(amount1);
        assertEq(revenuePool.totalRevenue(), amount1);
        
        revenuePool.depositRevenue(amount2);
        assertEq(revenuePool.totalRevenue(), amount1 + amount2);
        vm.stopPrank();
    }

    // ============================================
    // InjectToSCUR Tests
    // ============================================

    function test_injectToSCUR_Success() public {
        uint256 depositAmount = 1000 * 1e18;
        uint256 injectAmount = 500 * 1e18;

        vm.prank(protocol);
        curToken.approve(address(revenuePool), depositAmount);

        vm.prank(protocol);
        revenuePool.depositRevenue(depositAmount);

        vm.prank(owner);
        revenuePool.injectToSCUR(injectAmount);

        assertEq(revenuePool.totalRevenue(), depositAmount - injectAmount);
        assertEq(mockSCUR.lastCaller(), address(revenuePool));
        assertEq(mockSCUR.lastAmount(), injectAmount);
    }

    function test_injectToSCUR_Event() public {
        uint256 depositAmount = 1000 * 1e18;
        uint256 injectAmount = 500 * 1e18;

        vm.prank(protocol);
        curToken.approve(address(revenuePool), depositAmount);

        vm.prank(protocol);
        revenuePool.depositRevenue(depositAmount);

        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit RevenueInjected(injectAmount);
        revenuePool.injectToSCUR(injectAmount);

    }

    function test_injectToSCUR_NotOwner() public {
        uint256 depositAmount = 1000 * 1e18;
        uint256 injectAmount = 500 * 1e18;

        vm.prank(protocol);
        curToken.approve(address(revenuePool), depositAmount);

        vm.prank(protocol);
        revenuePool.depositRevenue(depositAmount);

        vm.prank(alice);
        vm.expectRevert();
        revenuePool.injectToSCUR(injectAmount);


    }

    function test_injectToSCUR_ZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert(RevenueRebatePool.ZeroAmount.selector);
        revenuePool.injectToSCUR(0);

    }

    function test_injectToSCUR_ExceedsRevenue() public {
        uint256 depositAmount = 1000 * 1e18;
       
        vm.prank(protocol);
        curToken.approve(address(revenuePool), depositAmount);

        vm.prank(protocol);
        revenuePool.depositRevenue(depositAmount);

        vm.prank(owner);
        vm.expectRevert(RevenueRebatePool.ExceedsRevenue.selector);
        revenuePool.injectToSCUR(depositAmount + 1);


    }

    function test_injectToSCUR_InsufficientBalance() public {
        uint256 amount = 1000 * 1e18;
       
        vm.prank(protocol);
        curToken.approve(address(revenuePool), amount);
        vm.prank(protocol);
        revenuePool.depositRevenue(amount);

        vm.prank(address(revenuePool));
        curToken.transfer(address(0x1234), amount);
        
        vm.prank(owner);
        vm.expectRevert(RevenueRebatePool.InsufficientBalance.selector);
        revenuePool.injectToSCUR(amount);

    }

    function test_injectToSCUR_MultipleInjections() public {
        uint256 depositAmount = 3000 * 1e18;
        uint256 injectAmount1 = 1000 * 1e18;
        uint256 injectAmount2 = 1000 * 1e18;

        vm.prank(protocol);
        curToken.approve(address(revenuePool), depositAmount);
        vm.prank(protocol);
        revenuePool.depositRevenue(depositAmount);

        vm.prank(owner);
        revenuePool.injectToSCUR(injectAmount1);
        assertEq(revenuePool.totalRevenue(), depositAmount - injectAmount1);

        vm.prank(owner);
        revenuePool.injectToSCUR(injectAmount2);
        assertEq(revenuePool.totalRevenue(), depositAmount - injectAmount1 - injectAmount2);
    }

    // ============================================
    // InjectAll Tests
    // ============================================

    function test_injectAll_Success() public {
        uint256 depositAmount = 1000 * 1e18;

        mockSCUR.setTotalSupply(1000000 ether);

        vm.prank(protocol);
        curToken.approve(address(revenuePool), depositAmount);

        vm.prank(protocol);
        revenuePool.depositRevenue(depositAmount);

        vm.prank(owner);
        revenuePool.injectAll();

        assertEq(revenuePool.totalRevenue(), 0);
        assertEq(mockSCUR.lastCaller(), address(revenuePool));
        assertEq(mockSCUR.lastAmount(), depositAmount);

    }

    function test_injectAll_Emit() public {
        uint256 depositAmount = 1000 * 1e18;

        vm.prank(protocol);
        curToken.approve(address(revenuePool), depositAmount);

        vm.prank(protocol);
        revenuePool.depositRevenue(depositAmount);

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit RevenueInjectedAll(depositAmount);
        revenuePool.injectAll();

    }

    function test_injectAll_NotOwner() public {
        uint256 depositAmount = 1000 * 1e18;

        vm.prank(protocol);
        curToken.approve(address(revenuePool), depositAmount);

        vm.prank(protocol);
        revenuePool.depositRevenue(depositAmount);

        vm.prank(alice);
        vm.expectRevert();
        revenuePool.injectAll();

    }

    function test_injectAll_BelowThreshold() public {
        uint256 depositAmount = 500 * 1e18;

        vm.prank(protocol);
        curToken.approve(address(revenuePool), depositAmount);

        vm.prank(protocol);
        revenuePool.depositRevenue(depositAmount);

        vm.prank(owner);
        vm.expectRevert(RevenueRebatePool.BelowThreshold.selector);
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

    function test_setNetThreshold_Emit() public {
        uint256 newThreshold = 500 * 1e18;

        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit ThresholdUpdated(newThreshold);
        revenuePool.setNewthreshold(newThreshold);

    }

    function test_setNewthreshold_NotOwner() public {
        uint256 newThreshold = 500 * 1e18;

        vm.prank(alice);
        vm.expectRevert();
        revenuePool.setNewthreshold(newThreshold);

    }

    // ============================================
    // GetContractBalance Tests
    // ============================================
    function test_getContractBalance_ReturnsCorrectBalance() public {
        uint256 depositAmount = 1000 * 1e18;
        
        vm.prank(protocol);
        curToken.approve(address(revenuePool), depositAmount);
        vm.prank(protocol);
        revenuePool.depositRevenue(depositAmount);
        
        assertEq(revenuePool.getContractBalance(), depositAmount);

    }

    function test_GetContractBalance_AfterDeposit() public {
        uint256 amount = 1000 * 1e18;
        
        vm.prank(protocol);
        curToken.approve(address(revenuePool), amount);
        vm.prank(protocol);
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
        
        uint256 amount = 1000 * 1e18;
        vm.prank(protocol);
        curToken.approve(address(revenuePool), amount);
        
        vm.prank(protocol);
        vm.expectRevert();
        revenuePool.depositRevenue(amount);
    }
    
    function test_InjectToSCUR_WhenPaused() public {
        uint256 depositAmount = 1000 * 1e18;
        
        vm.prank(protocol);
        curToken.approve(address(revenuePool), depositAmount);
        vm.prank(protocol);
        revenuePool.depositRevenue(depositAmount);
        
        vm.prank(owner);
        revenuePool.pause();
        
        vm.prank(owner);
        vm.expectRevert();
        revenuePool.injectToSCUR(500 * 1e18);
    }

     function test_InjectAll_WhenPaused() public {
        uint256 depositAmount = 2000 * 1e18;
        
        vm.prank(protocol);
        curToken.approve(address(revenuePool), depositAmount);
        vm.prank(protocol);
        revenuePool.depositRevenue(depositAmount);
        
        vm.prank(owner);
        revenuePool.pause();
        
        vm.prank(owner);
        vm.expectRevert();
        revenuePool.injectAll();
    }

    // ============================================
    // Edge Case Tests
    // ============================================

    function test_EdgeCase_DepositAndInjectSameAmount() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(protocol);
        curToken.approve(address(revenuePool), amount);

        vm.prank(protocol);
        revenuePool.depositRevenue(amount);
        vm.prank(owner);
        revenuePool.injectToSCUR(amount);
    
        assertEq(revenuePool.totalRevenue(), 0);
        assertEq(revenuePool.getContractBalance(), 0);
        assertEq(curToken.balanceOf(address(staking)), amount);
    }

    function test_EdgeCase_InjectMoreThanDeposited() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(protocol);
        curToken.approve(address(revenuePool), amount);

        vm.prank(protocol);
        revenuePool.depositRevenue(amount);

        vm.prank(owner);
        vm.expectRevert(RevenueRebatePool.ExceedsRevenue.selector);
        revenuePool.injectToSCUR(amount + 1);
    }

    function test_EdgeCase_InjectAllWhenTotalRevenueZero() public {
        vm.prank(owner);
        vm.expectRevert(RevenueRebatePool.BelowThreshold.selector);
        revenuePool.injectAll();
    }

    function test_EdgeCase_ExactlyAtThreshold() public {
        uint256 amount = 1000 * 1e18;  
    
        vm.prank(protocol);
        curToken.approve(address(revenuePool), amount);
        vm.prank(protocol);
        revenuePool.depositRevenue(amount);
    
    
        vm.prank(owner);
        revenuePool.injectAll();
    
        assertEq(revenuePool.totalRevenue(), 0);

    }

    function test_EdgeCase_ZeroThreshold() public {
        vm.prank(owner);
        revenuePool.setNewthreshold(0);
          
        uint256 amount = 100 * 1e18;
        vm.prank(protocol);
        curToken.approve(address(revenuePool), amount);
        vm.prank(protocol);
        revenuePool.depositRevenue(amount);
    
        vm.prank(owner);
        revenuePool.injectAll();
        assertEq(revenuePool.totalRevenue(), 0);
    }

    function test_EdgeCase_InjectPartialThenInjectAll() public {
        uint256 amount = 2000 * 1e18;
        vm.prank(protocol);
        curToken.approve(address(revenuePool), amount);
        vm.prank(protocol);
        revenuePool.depositRevenue(amount);

        vm.prank(owner);
        revenuePool.injectToSCUR(800 * 1e18);
        assertEq(revenuePool.totalRevenue(), 1200 * 1e18);

        vm.prank(owner);
        revenuePool.injectAll();
        assertEq(revenuePool.totalRevenue(), 0);
    }

    function test_EdgeCase_MultipleDepositsAndInjections() public {
        for (uint256 i = 0; i < 5; i++) {
            uint256 depositAmount = 200 * 1e18;
            uint256 injectAmount = 100 * 1e18;
        
            vm.prank(protocol);
            curToken.approve(address(revenuePool), depositAmount);
            vm.prank(protocol);
            revenuePool.depositRevenue(depositAmount);
        
            vm.prank(owner);
            revenuePool.injectToSCUR(injectAmount);
        }
    
    
        assertEq(revenuePool.totalRevenue(), 500 * 1e18);
    }

    function test_EdgeCase_ChangeThresholdAfterDeposit() public {
        uint256 amount = 600 * 1e18;
        vm.prank(protocol);
        curToken.approve(address(revenuePool), amount);
        vm.prank(protocol);
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
        vm.assume(amount > 0);
        vm.assume(amount < 10000 * 1e18);

        vm.prank(protocol);
        curToken.approve(address(revenuePool), amount);

        uint256 beforeTotalRevenue = revenuePool.totalRevenue();

        vm.prank(protocol);
        revenuePool.depositRevenue(amount);

        assertEq(revenuePool.totalRevenue(), beforeTotalRevenue + amount);

    }

    function test_Fuzz_InjectToSCUR(uint256 depositAmount, uint256 injectAmount) public {
        vm.assume(depositAmount > 0);
        vm.assume(depositAmount < 100000 * 1e18);
        vm.assume(injectAmount > 0);
        vm.assume(injectAmount <= depositAmount);

        vm.prank(protocol);
        curToken.approve(address(revenuePool), depositAmount);
        vm.prank(protocol);
        revenuePool.depositRevenue(depositAmount);
        
        uint256 beforeTotal = revenuePool.totalRevenue();
        
        vm.prank(owner);
        revenuePool.injectToSCUR(injectAmount);
        
        assertEq(revenuePool.totalRevenue(), beforeTotal - injectAmount);
        assertEq(mockSCUR.lastAmount(), injectAmount);

    }

    function test_Fuzz_SetThreshold(uint256 newThreshold) public {
        vm.assume(newThreshold <= 100_000_000 * 1e18);
        vm.prank(owner);
        revenuePool.setNewthreshold(newThreshold);
        
        assertEq(revenuePool.threshold(), newThreshold);

    }



}