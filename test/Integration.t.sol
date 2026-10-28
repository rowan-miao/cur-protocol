// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "../src/core/CURToken.sol";
import "../src/core/sCUR.sol";
import "../src/core/CURStaking.sol";
import "../src/modules/veCURLock.sol";
import "../src/modules/NFTChecker.sol";
import "../src/modules/IncentiveGauge.sol";
import "../src/modules/RevenueRebatePool.sol";

contract MockERC721 is ERC721 {
    constructor() ERC721("Mock", "M"){}
    function mint(address to, uint256 tokenId) external{
        _mint(to, tokenId);
    }
}

contract IntegrationTest is Test {
    CURToken public curToken;
    sCUR public sCURToken;
    CURStaking public staking;
    veCURLock public veLock;
    NFTChecker public nftChecker;
    IncentiveGauge public gauge;
    RevenueRebatePool public revenue;
    MockERC721 public mockMidNFT;
    MockERC721 public mockHighNFT;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address owner = makeAddr("owner");


    function setUp() public {
        vm.startPrank(owner);
        curToken = new CURToken();
        
        sCURToken = new sCUR(address(curToken), address(0));
        
        nftChecker = new NFTChecker(address(0));
       
        staking = new CURStaking(address(curToken), address(sCURToken), address(0), address(0), address(0));
       
        veLock = new veCURLock(address(sCURToken), address(nftChecker), address(0));
        
        revenue = new RevenueRebatePool(address(curToken), address(sCURToken), address(staking));
        
        sCURToken.addMinter(address(revenue));
     
        gauge = new IncentiveGauge(address(curToken), address(sCURToken), address(staking), address(veLock), address(revenue));

        sCURToken.setIncentiveGauge(address(gauge));
        sCURToken.setCurStaking(address(staking));

        nftChecker.setVeLock(address(veLock));

        staking.setGauge(address(gauge));
        staking.setVeLock(address(veLock));
        staking.setRevenueRebatePool(address(revenue));

        veLock.setIncentiveGauge(address(gauge));
        veLock.setCurStaking(address(staking));

        revenue.setGauge(address(gauge));

        mockMidNFT= new MockERC721();
        nftChecker.addWhiteListedContract(address(mockMidNFT), 1);
        mockHighNFT = new MockERC721(); 
        nftChecker.addWhiteListedContract(address(mockHighNFT), 2);

        curToken.transfer(address(gauge), 40_000_000 * 1e18);
        curToken.transfer(alice, 10_000 * 1e18);
        curToken.transfer(bob, 10_000 * 1e18);
        vm.stopPrank();

        vm.prank(alice);
        curToken.approve(address(staking), type(uint256).max);
        vm.prank(alice);
        sCURToken.approve(address(staking), type(uint256).max);
        vm.prank(alice);
        curToken.approve(address(revenue), type(uint256).max);

        vm.prank(bob);
        curToken.approve(address(staking), type(uint256).max);
        vm.prank(bob);
        sCURToken.approve(address(staking), type(uint256).max);

        vm.prank(owner);
        curToken.approve(address(revenue), type(uint256).max);

    }

    function test_Integration_FullFlow_Rewards() public {
        vm.prank(alice);
        staking.stake(1000 * 1e18);
    
        vm.prank(alice);
        staking.enterGauge(1000 * 1e18);

        vm.prank(alice);
        veLock.lock(30 days);
        assertEq(veLock.getBonus(alice), 1.15e18);

        vm.warp(block.timestamp + 15 days);

        uint256 curBalBefore1 = curToken.balanceOf(alice);
        
        vm.prank(alice);
        gauge.getReward();

        uint256 reward1 = curToken.balanceOf(alice) - curBalBefore1;
        assertGt(reward1, 0);

        (, uint256 weightDuringLock,,) = gauge.users(alice);
        assertEq(weightDuringLock, 1150 * 1e18);
        
        vm.warp(block.timestamp + 20 days); 

        uint256 curBalBefore2 = curToken.balanceOf(alice);
        vm.prank(alice);
        gauge.getReward();
        uint256 reward2 = curToken.balanceOf(alice) - curBalBefore2;

        assertGt(reward2, 0);

        (, uint256 weightAfterExpiry,,) = gauge.users(alice);
        assertEq(weightAfterExpiry, 1000 * 1e18);

        assertEq(veLock.getBonus(alice), 1.0e18);
    }

    function test_Integration_EarlyUnlock_penalty() public {
        vm.startPrank(alice);
        staking.stake(1000 * 1e18);
        staking.enterGauge(1000 * 1e18);
        veLock.lock(30 days);
        vm.stopPrank();

        vm.warp(block.timestamp + 15 days);
        vm.prank(alice);
        gauge.getReward();

        uint256 guageSCURBalBefore = sCURToken.balanceOf(address(gauge));
        uint256 revenueCURBalBefore = curToken.balanceOf(address(revenue));

        uint256 stakingCURBalBefore = curToken.balanceOf(address(staking));
        uint256 underlyingBefore = sCURToken.totalUnderlying();

        vm.prank(alice);
        veLock.earlyUnlock();

        uint256 expectedPenalty = 250 * 1e18;

        assertEq(sCURToken.balanceOf(address(gauge)), guageSCURBalBefore - expectedPenalty);
        assertEq(curToken.balanceOf(address(staking)), stakingCURBalBefore - expectedPenalty);
        assertEq(sCURToken.totalUnderlying(), underlyingBefore - expectedPenalty);
        assertEq(curToken.balanceOf(address(revenue)), revenueCURBalBefore + expectedPenalty);

        assertEq(gauge.getUserAmount(alice), 1000 * 1e18 - expectedPenalty);
        assertEq(veLock.isLocked(alice), false);
    }

    function test_Integration_longLock() public {
        vm.startPrank(alice);
        staking.stake(1000 * 1e18);
        staking.enterGauge(1000 * 1e18);
        vm.stopPrank();

        vm.prank(alice);
        vm.expectRevert(veCURLock.DurationExceedsPermission.selector);
        veLock.lock(365 days);

        vm.prank(owner);
        mockMidNFT.mint(alice, 1);
        vm.prank(alice);
        nftChecker.bindNFT(address(mockMidNFT), 1);

        vm.prank(alice);
        veLock.lock(365 days);
        assertEq(veLock.getBonus(alice), 2.0e18);

        vm.warp(block.timestamp + 200 days);
        uint256 balBefore = curToken.balanceOf(alice);
        vm.prank(alice);
        gauge.getReward();
        assertGt(curToken.balanceOf(alice), balBefore);
    }
    
    function test_Integration_FullLifecycle_NormalExit() public {
        uint256 initialCUR = curToken.balanceOf(alice);

        vm.startPrank(alice);
        staking.stake(1000 * 1e18);
        staking.enterGauge(1000 * 1e18);
        veLock.lock(30 days);
        vm.stopPrank();

        vm.warp(block.timestamp + 30 days);

        uint256 balanceBeforeReward = curToken.balanceOf(alice);

        vm.prank(alice);
        gauge.getReward();
    
        uint256 rewardEarned = curToken.balanceOf(alice) - balanceBeforeReward;
        assertGt(rewardEarned, 0);

        console.log("Current Rate:", sCURToken.getExchangeRate());
        vm.prank(alice);
        veLock.unlock();
        assertEq(veLock.isLocked(alice), false);

        vm.prank(alice);
        staking.exitGauge(1000 * 1e18);
        assertEq(gauge.getUserAmount(alice), 0);
        assertEq(sCURToken.balanceOf(alice), 1000 * 1e18);

        vm.prank(alice);
        staking.unstake(1000 * 1e18);

        assertEq(curToken.balanceOf(alice), initialCUR + rewardEarned);
        assertEq(sCURToken.balanceOf(alice), 0);
    } 

    function test_Integration_EmergencyWithdraw() public {
        vm.startPrank(alice);
        staking.stake(1000 * 1e18);
        staking.enterGauge(1000 * 1e18);
        veLock.lock(30 days);
        vm.stopPrank();

        vm.warp(block.timestamp + 15 days);

        uint256 aliceCURBefore = curToken.balanceOf(alice);
        uint256 revenueCURBefore = curToken.balanceOf(address(revenue));

        vm.prank(owner);
        staking.pause();

        vm.prank(alice);
        staking.emergencyWithdraw();

        uint256 expectedPenalty = 250 * 1e18;
        uint256 expectedPrincipal = 750 * 1e18;

        assertEq(curToken.balanceOf(alice) - aliceCURBefore, expectedPrincipal);
        assertEq(curToken.balanceOf(address(revenue)) - revenueCURBefore, expectedPenalty);

        assertEq(sCURToken.balanceOf(alice), 0);
        assertEq(veLock.isLocked(alice), false);
        assertEq(gauge.getUserAmount(alice), 0);
    }

    function test_Integration_MultiUser_RewardProRata() public {
        vm.startPrank(alice);
        staking.stake(1000 * 1e18);
        staking.enterGauge(1000 * 1e18);
        veLock.lock(30 days);
        vm.stopPrank();

        vm.startPrank(bob);
        staking.stake(1000 * 1e18);
        staking.enterGauge(1000 * 1e18);
        veLock.lock(180 days);
        vm.stopPrank();

        assertEq(gauge.totalWeight(), (1150 + 1650) * 1e18);

        vm.warp(block.timestamp + 100 days);

        uint256 aliceBefore = curToken.balanceOf(alice);
        uint256 bobBefore = curToken.balanceOf(bob);

        vm.prank(alice);
        gauge.getReward();
        vm.prank(bob);
        gauge.getReward();

        uint256 aliceReward = curToken.balanceOf(alice) - aliceBefore;
        uint256 bobReward = curToken.balanceOf(bob) - bobBefore;

        assertGt(bobReward, aliceReward);

        assertApproxEqRel(bobReward * 1150, aliceReward * 1650, 0.01e18);
    }

    function test_Integration_Unstake_AfterExchangeRateGrowth() public {
        vm.prank(alice);
        staking.stake(1000 * 1e18);

        vm.prank(owner);
        revenue.depositRevenue(500 * 1e18);
        vm.prank(owner);
        revenue.injectToSCUR(500 * 1e18);

        assertEq(sCURToken.getExchangeRate(), 1.5e18);

        uint256 aliceBalBefore = curToken.balanceOf(alice);
    
        vm.prank(alice);
        staking.unstake(1000 * 1e18);
        assertEq(curToken.balanceOf(alice) - aliceBalBefore, 1500 * 1e18);
    }

    function test_Integration_EarlyUnlock_AfterRateGrowth() public {
        vm.startPrank(alice);
        staking.stake(1000 * 1e18);
        staking.enterGauge(1000 * 1e18);
        veLock.lock(180 days);
        vm.stopPrank();

        vm.prank(owner);
        revenue.depositRevenue(500 * 1e18);
        vm.prank(owner);
        revenue.injectToSCUR(500 * 1e18);

        vm.warp(block.timestamp + 90 days);

        vm.prank(alice);
        gauge.getReward();

        uint256 revenueBefore = curToken.balanceOf(address(revenue));

        vm.prank(alice);
        veLock.earlyUnlock();
        uint256 expectedPenalty = 375 * 1e18;

        assertEq(curToken.balanceOf(address(revenue)) - revenueBefore, expectedPenalty);
        
        uint256 gaugeAmount = gauge.getUserAmount(alice);

        vm.prank(alice);
        staking.exitGauge(750 * 1e18);

        uint256 actualSCURInWallet = sCURToken.balanceOf(alice);
        uint256 aliceCURBefore = curToken.balanceOf(alice);

        vm.prank(alice);
        staking.unstake(750 * 1e18);
        
        uint256 expectedCUR = actualSCURInWallet * 1.5e18 / 1e18;
        assertEq(curToken.balanceOf(alice) - aliceCURBefore, expectedCUR);
    }

}