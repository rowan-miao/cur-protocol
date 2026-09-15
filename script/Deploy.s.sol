// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/core/CURToken.sol";
import "../src/core/sCUR.sol";
import "../src/core/CURStaking.sol";
import "../src/modules/veCURLock.sol";
import "../src/modules/NFTChecker.sol";
import "../src/modules/IncentiveGauge.sol";
import "../src/modules/RevenueRebatePool.sol";
import "../src/modules/Airdrop.sol";
import "@openzeppelin/contracts/finance/VestingWallet.sol";

contract DeployScript is Script {
    uint256 constant PRECISION = 1e18;

    uint256 constant STAKING_REWARD = 40_000_000 * PRECISION;

    uint256 constant ECO_FUND = 25_000_000 * PRECISION;

    uint256 constant TEAM = 15_000_000 * PRECISION;

    uint256 constant AIRDROP = 10_000_000 * PRECISION;

    uint256 constant TREASURY = 10_000_000 * PRECISION;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);

        address team = vm.envAddress("TEAM_ADDRESS");
        address eco = vm.envAddress("ECO_ADDRESS");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address dao = vm.envAddress("DAO_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        CURToken curToken = new CURToken();
        console.log("CURToken:", address(curToken));

        sCUR sCURToken = new sCUR(address(curToken));
        console.log("sCUR:", address(sCURToken));

        NFTChecker nftchecker = new NFTChecker();
        console.log("NFTChecker:", address(nftchecker));

        CURStaking staking = new CURStaking(address(curToken), address(sCURToken), address(0), address(0), address(0));
        console.log("CURStaking:", address(staking));

        sCURToken.addMinter(address(staking));
        console.log("CURStaking added as minter for sCUR");

        veCURLock veLock = new veCURLock(address(sCURToken), address(staking), address(nftchecker), address(0));
        console.log("veCURLock:", address(veLock));

        RevenueRebatePool revenue = new RevenueRebatePool(address(curToken), address(sCURToken), address(staking));
        console.log("RevenueRebatePool:", address(revenue));

        IncentiveGauge gauge = new IncentiveGauge(
            address(curToken), address(sCURToken), address(staking), address(veLock), address(revenue)
        );
        console.log("IncentiveGauge:", address(gauge));

        sCURToken.setIncentiveGauge(address(gauge));
        console.log("sCUR dependencies set");

        staking.setGauge(address(gauge));
        staking.setVeLock(address(veLock));
        staking.setRevenueRebatePool(address(revenue));
        console.log("CURStaking dependencies set");

        veLock.setIncentiveGauge(address(gauge));
        console.log("veCURLock dependencies set");

        Airdrop airdrop = new Airdrop(address(curToken));
        console.log("Airdrop:", address(airdrop));

        uint64 start = uint64(block.timestamp + 180 days);

        VestingWallet teamVesting = new VestingWallet(team, start, uint64(1460 days));
        console.log("TeamVesting:", address(teamVesting));

        curToken.transfer(address(gauge), STAKING_REWARD);
        console.log("Transferred 40M CUR to IncentiveGauge");

        curToken.transfer(eco, ECO_FUND);
        console.log("Transferred 25M CUR to Eco");

        curToken.transfer(address(teamVesting), TEAM);
        console.log("Transferred 15M CUR to TeamVesting");

        curToken.transfer(address(airdrop), AIRDROP);
        console.log("Transferred 10M CUR to Airdrop");

        curToken.transfer(treasury, TREASURY);
        console.log("Transferred 10M CUR to Treasury");

        require(curToken.balanceOf(owner) == 0, "CUR distribution failed");
        console.log("CUR distribution completed");

        curToken.transferOwnership(dao);
        console.log("CUR ownership transferred to DAO");

        vm.stopBroadcast();
    }
}
