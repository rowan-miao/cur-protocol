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
import "@openzeppelin/contracts/governance/TimelockController.sol";

contract DeployScript is Script {
    uint256 constant PRECISION = 1e18;

    uint256 constant STAKING_REWARD = 40_000_000 * PRECISION;

    uint256 constant ECO_FUND = 25_000_000 * PRECISION;

    uint256 constant TEAM = 15_000_000 * PRECISION;

    uint256 constant AIRDROP = 10_000_000 * PRECISION;

    uint256 constant TREASURY = 10_000_000 * PRECISION;

    uint256 constant TIMELOCK_DELAY = 3 days;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        address deployer = vm.addr(deployerPrivateKey);
        address multisig = vm.envAddress("MULTISIG");
        
        address team = vm.envAddress("TEAM_ADDRESS");
        address eco = vm.envAddress("ECO_ADDRESS");
        address treasury = vm.envAddress("TREASURY_ADDRESS");

        require(multisig != address(0), "MULTISIG is zero");
        require(team != address(0), "TEAM_ADDRESS is zero");
        require(eco != address(0), "ECO_ADDRESS is zero");
        require(treasury != address(0), "TREASURY_ADDRESS is zero");

        console.log("========================================");
        console.log("CUR Protocol Deployment");
        console.log("========================================");
        console.log("Deployer:", deployer);
        console.log("Multisig:", multisig);
        
        vm.startBroadcast(deployerPrivateKey);

        // ============================================
        // Deploy TimelockController
        // ============================================

        address[] memory proposers = new address[](1);
        proposers[0] = multisig;

        address[] memory executors = new address[](1);
        executors[0] = address(0);

        TimelockController timelock = new TimelockController(
            TIMELOCK_DELAY,
            proposers,
            executors,
            deployer  
        );
        console.log("TimelockController:", address(timelock));
        console.log("Timelock delay:", TIMELOCK_DELAY);

        CURToken curToken = new CURToken();
        console.log("CURToken:", address(curToken));

        sCUR sCURToken = new sCUR(address(curToken), address(0));
        console.log("sCUR:", address(sCURToken));

        NFTChecker nftChecker = new NFTChecker(address(0));
        console.log("NFTChecker:", address(nftChecker));

        CURStaking staking = new CURStaking(address(curToken), address(sCURToken), address(0), address(0), address(0));
        console.log("CURStaking:", address(staking));

        veCURLock veLock = new veCURLock(address(sCURToken), address(nftChecker), address(0));
        console.log("veCURLock:", address(veLock));

        RevenueRebatePool revenue = new RevenueRebatePool(address(curToken), address(sCURToken), address(staking));
        console.log("RevenueRebatePool:", address(revenue));

        sCURToken.addMinter(address(revenue));
        console.log("RevenueRebatePool added as minter for sCUR");
        
        IncentiveGauge gauge = new IncentiveGauge(
            address(curToken), address(sCURToken), address(staking), address(veLock), address(revenue)
        );
        console.log("IncentiveGauge:", address(gauge));

        sCURToken.setIncentiveGauge(address(gauge));
        sCURToken.setCurStaking(address(staking));
        console.log("sCUR dependencies set");

        nftChecker.setVeLock(address(veLock));
        console.log("NFTChecker dependencies set");

        staking.setGauge(address(gauge));
        staking.setVeLock(address(veLock));
        staking.setRevenueRebatePool(address(revenue));
        console.log("CURStaking dependencies set");

        veLock.setIncentiveGauge(address(gauge));
        console.log("veCURLock dependencies set");

        revenue.setGauge(address(gauge));
        console.log("RevenueRebatePool dependencies set");

        Airdrop airdrop = new Airdrop(address(curToken));
        console.log("Airdrop:", address(airdrop));

        // =========================================================
        // Deploy Team VestingWallet
        // =========================================================

        uint64 start = uint64(block.timestamp + 180 days);
        uint64 vestingDuration = uint64(1460 days);

        VestingWallet teamVesting = new VestingWallet(team, start, vestingDuration);
        console.log("TeamVesting:", address(teamVesting));

        // =========================================================
        //  CUR distribution (BEFORE ownership transfer)
        // =========================================================

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

        require(curToken.balanceOf(deployer) == 0, "CUR distribution failed");
        console.log("CUR distribution completed");

        // =========================================================
        // Transfer ownership to Timelock
        // =========================================================
        
        curToken.transferOwnership(address(timelock));
        console.log("CUR ownership -> timelock");

        sCURToken.transferOwnership(address(timelock));
        console.log("sCUR ownership -> Timelock");

        staking.transferOwnership(address(timelock));
        console.log("CURStaking ownership -> Timelock");

        gauge.transferOwnership(address(timelock));
        console.log("IncentiveGauge ownership -> Timelock");

        veLock.transferOwnership(address(timelock));
        console.log("veCURLock ownership -> Timelock");

        revenue.transferOwnership(address(timelock));
        console.log("RevenueRebatePool ownership -> Timelock");

        nftChecker.transferOwnership(address(timelock));
        console.log("NFTChecker ownership -> Timelock");

        airdrop.transferOwnership(address(timelock));
        console.log("Airdrop ownership -> Timelock");

        // =========================================================
        // Renounce deployer's Timelock admin role
        // =========================================================

        bytes32 defaultAdminRole = timelock.DEFAULT_ADMIN_ROLE();
        require(
            timelock.hasRole(defaultAdminRole, deployer),
            "Deployer is not Timelock admin"
        );

        timelock.grantRole(defaultAdminRole, multisig);
        console.log("Multisig granted Timelock admin role");

        timelock.renounceRole(defaultAdminRole, deployer);
        console.log("Deployer Timelock admin role renounced");

        // =========================================================
        // Final verification
        // =========================================================

        require(curToken.owner() == address(timelock), "CURToken owner mismatch");
        require(sCURToken.owner() == address(timelock), "sCUR owner mismatch");
        require(staking.owner() == address(timelock), "CURStaking owner mismatch");
        require(gauge.owner() == address(timelock), "Gauge owner mismatch");
        require(veLock.owner() == address(timelock), "veCURLock owner mismatch");
        require(revenue.owner() == address(timelock), "Revenue owner mismatch");
        require(nftChecker.owner() == address(timelock), "NFTChecker owner mismatch");
        require(airdrop.owner() == address(timelock), "Airdrop owner mismatch");

        require(
            timelock.hasRole(timelock.PROPOSER_ROLE(), multisig),
            "Multisig proposer missing"
        );

        require(
            timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0)),
            "Open executor missing"
        );

        require(
            !timelock.hasRole(defaultAdminRole, deployer),
            "Deployer still has Timelock admin"
        );

        console.log("========================================");
        console.log("Deployment completed successfully");
        console.log("Timelock:", address(timelock));
        console.log("========================================");

        vm.stopBroadcast();
    }
}
