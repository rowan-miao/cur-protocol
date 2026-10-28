// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "../../src/core/CURToken.sol";
import "../../src/core/sCUR.sol";
import "../../src/core/CURStaking.sol";
import "../../src/modules/veCURLock.sol";
import "../../src/modules/NFTChecker.sol";
import "../../src/modules/IncentiveGauge.sol";
import "../../src/modules/RevenueRebatePool.sol";

contract MockERC721 is ERC721{
    constructor() ERC721("Mock","M"){}
    function mint(address to, uint256 tokenId) external {
        _mint(to,tokenId);
    }

}

contract Handler is Test{
    CURToken public curToken;
    sCUR public sCURToken;
    CURStaking public staking;
    veCURLock public veLock;
    IncentiveGauge public gauge;
    RevenueRebatePool public revenue;
    NFTChecker public nftChecker;
    MockERC721 public mockMidNFT;
    MockERC721 public mockHighNFT;

    address public owner;

    address[] public actors;
    uint256 private nextTokenId = 1;

    constructor(CURToken _cur, sCUR _sCur, CURStaking _staking, veCURLock _veLock, IncentiveGauge _gauge, RevenueRebatePool _revenue, NFTChecker _nftChecker, MockERC721 _midNFT, MockERC721 _highNFT, address _owner){
        curToken = _cur;
        sCURToken = _sCur;
        staking = _staking;
        veLock = _veLock;
        gauge = _gauge;
        revenue = _revenue;
        nftChecker = _nftChecker;
        mockMidNFT = _midNFT;
        mockHighNFT = _highNFT;
        owner = _owner;

        actors.push(makeAddr("actor1"));
        actors.push(makeAddr("actor2"));
        actors.push(makeAddr("actor3"));
    }

    function stake(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];
        amount = bound(amount, 1e12, 1000 * 1e18);

        curToken.transfer(actor, amount);
        vm.startPrank(actor);
        curToken.approve(address(staking), amount);
        staking.stake(amount);
        vm.stopPrank();

    }

    function unstake(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];
        uint256 balance = sCURToken.balanceOf(actor);
        if(balance == 0) return;
        if(veLock.isLocked(actor)) return;

        amount = bound(amount, 1, balance);
        vm.prank(actor);
        staking.unstake(amount);
    }

    function enterGauge(uint256 actorSeed, uint256 amount) external{
        address actor = actors[actorSeed % actors.length];
        uint256 balance = sCURToken.balanceOf(actor);
        if(balance == 0) return;
        if(veLock.isLocked(actor)) return;

        amount = bound(amount, 1, balance);
        vm.startPrank(actor);
        sCURToken.approve(address(staking), amount);
        staking.enterGauge(amount);
        vm.stopPrank();
    }
    
    function exitGauge(uint256 actorSeed, uint256 amount) external{
        address actor = actors[actorSeed % actors.length];
        if(veLock.isLocked(actor)) return;

        uint256 deposited = gauge.getUserAmount(actor);
        if(deposited == 0) return;

        amount = bound(amount, 1, deposited);
        vm.prank(actor);
        staking.exitGauge(amount);

    }

    function lock(uint256 actorSeed, uint256 durationIdx) external{
        address actor = actors[actorSeed % actors.length];
        if(veLock.isLocked(actor)) return;
        if(gauge.getUserAmount(actor) == 0) return;

        uint256 idx = durationIdx % 5;
        uint256 duration;
        if(idx == 0) duration = 30 days;
        else if(idx == 1) duration = 90 days;
        else if(idx == 2) duration = 180 days;
        else if(idx == 3) duration = 365 days;
        else duration = 730 days;

        uint256 maxDuration = veLock.getMaxLockDuration(actor);
        if(duration > maxDuration) return;

        vm.prank(actor);
        veLock.lock(duration);

    }

    function unlock(uint256 actorSeed) external{
        address actor = actors[actorSeed % actors.length];
        if(!veLock.isLocked(actor)) return;
        (,, uint256 endTime,,,) = veLock.locks(actor);
        if(block.timestamp < endTime) return;

        vm.prank(actor);
        veLock.unlock();
    }

    function earlyUnlock(uint256 actorSeed) external{
        address actor = actors[actorSeed % actors.length];
        if(!veLock.isLocked(actor)) return;
        (,, uint256 endTime,,,) = veLock.locks(actor);
        if(block.timestamp >= endTime) return;

        vm.prank(actor);
        veLock.earlyUnlock();
    }

    function getReward(uint256 actorSeed) external{
        address actor = actors[actorSeed % actors.length];

        vm.prank(actor);
        gauge.getReward();
    }
    
    function bindNFT(uint256 actorSeed, bool isHigh) external{
        address actor = actors[actorSeed % actors.length];
        if(nftChecker.isUserBound(actor)) return;
        address nft = isHigh ? address(mockHighNFT) : address(mockMidNFT);
        uint256 tokenId = nextTokenId++; 
        MockERC721(nft).mint(actor, tokenId);

        vm.prank(actor);
        nftChecker.bindNFT(nft, tokenId);

    }
    
    function unBindNFT(uint256 actorSeed) external{
        address actor = actors[actorSeed % actors.length];
        if(!nftChecker.isUserBound(actor)) return;
        if(veLock.isLocked(actor)) return;

        vm.prank(actor);
        nftChecker.unbindNFT();
    }

    function injectRevenue(uint256 actorSeed, uint256 amount) external{
        address actor = actors[actorSeed % actors.length];
        amount = bound(amount, 1e12, 1000 * 1e18);
        curToken.transfer(actor, amount);

        vm.startPrank(actor);
        curToken.approve(address(revenue), amount);
        revenue.depositRevenue(amount);
        vm.stopPrank();

        vm.prank(owner);
        try revenue.injectToSCUR(amount) {} catch {}

    }


    
    function warp(uint256 seconds_) external {
        seconds_ = bound(seconds_, 1 hours, 30 days);
        vm.warp(block.timestamp + seconds_);

    }

    function actorsLength() external view returns (uint256) {
        return actors.length;
    } 

    function getActor(uint256 i) external view returns (address) {
        return actors[i];
    }


}