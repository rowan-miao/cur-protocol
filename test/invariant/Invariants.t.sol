// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "./Handler.sol";
import "../../src/core/CURToken.sol";
import "../../src/core/sCUR.sol";
import "../../src/core/CURStaking.sol";
import "../../src/modules/veCURLock.sol";
import "../../src/modules/NFTChecker.sol";
import "../../src/modules/IncentiveGauge.sol";
import "../../src/modules/RevenueRebatePool.sol";

contract InvariantsTest is Test {
    CURToken public curToken;
    sCUR public sCURToken;
    CURStaking public staking;
    veCURLock public veLock;
    IncentiveGauge public gauge;
    RevenueRebatePool public revenue;
    NFTChecker public nftChecker;

    MockERC721 public mockMidNFT;
    MockERC721 public mockHighNFT;

    Handler public handler;

    address public owner;

    function setUp() public {
        owner = makeAddr("owner");
        vm.startPrank(owner);

        curToken = new CURToken();
        sCURToken = new sCUR(address(curToken), address(0));
        nftChecker = new NFTChecker(address(0));
        staking = new CURStaking(address(curToken), address(sCURToken), address(0), address(0), address(0));
        veLock = new veCURLock(address(sCURToken), address(nftChecker), address(0));
        revenue = new RevenueRebatePool(address(curToken), address(sCURToken), address(staking));
        sCURToken.addMinter(address(revenue));
        gauge = new IncentiveGauge(
            address(curToken), address(sCURToken), address(staking), address(veLock), address(revenue)
        );

        mockMidNFT = new MockERC721();
        mockHighNFT = new MockERC721();

        nftChecker.addWhiteListedContract(address(mockMidNFT), 1);
        nftChecker.addWhiteListedContract(address(mockHighNFT), 2);

        sCURToken.setIncentiveGauge(address(gauge));
        sCURToken.setCurStaking(address(staking));

        nftChecker.setVeLock(address(veLock));

        staking.setGauge(address(gauge));
        staking.setVeLock(address(veLock));
        staking.setRevenueRebatePool(address(revenue));

        veLock.setIncentiveGauge(address(gauge));
        veLock.setCurStaking(address(staking));

        revenue.setGauge(address(gauge));
        curToken.transfer(address(gauge), 40_000_000 * 1e18);

        vm.stopPrank();

        handler = new Handler(
            curToken, sCURToken, staking, veLock, gauge, revenue, nftChecker, mockMidNFT, mockHighNFT, owner
        );

        vm.prank(owner);
        curToken.transfer(address(handler), 10_000_000 * 1e18);

        targetContract(address(handler));
    }

    function invariant_UnderlyingMatchesStakingBalance() public view {
        assertEq(sCURToken.totalUnderlying(), curToken.balanceOf(address(staking)));
    }

    function invariant_TotalEmittedNeverExceedsCap() public view {
        assertLe(gauge.totalEmitted(), 40_000_000 * 1e18);
    }

    function invariant_TotalWeightEqualsSum() public view {
        uint256 sum = 0;
        uint256 length = handler.actorsLength();

        for (uint256 i = 0; i < length; i++) {
            address actor = handler.getActor(i);
            (, uint256 weight,,) = gauge.users(actor);
            sum += weight;
        }

        assertEq(gauge.totalWeight(), sum);
    }
}
