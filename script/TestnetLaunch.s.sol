// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ComplianceRegistry} from "../src/ComplianceRegistry.sol";
import {NodeLicense} from "../src/NodeLicense.sol";
import {TalentRegistry, ISupportVault} from "../src/TalentRegistry.sol";
import {SupportVault, ITalentRegistry} from "../src/SupportVault.sol";

/// BASE SEPOLIA ONLY. One-shot test launch:
///  1. a throwaway deployer key deploys everything and acts as temporary admin,
///  2. wires the contracts, allow-lists OWNER, sets node tiers, opens the sale,
///  3. hands every admin role to OWNER and renounces its own roles.
/// After this runs the deployer key controls nothing.
///
/// Env: DEPLOYER_PRIVATE_KEY (created inside the CI run), OWNER (owner 0x wallet)
contract TestnetLaunch is Script {
    address constant BASE_SEPOLIA_USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

    function run() external {
        require(block.chainid == 84532, "Base Sepolia only");
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address owner = vm.envAddress("OWNER");
        IERC20 usdc = IERC20(BASE_SEPOLIA_USDC);

        vm.startBroadcast(pk);

        ComplianceRegistry compliance = new ComplianceRegistry(deployer);
        NodeLicense nodes = new NodeLicense(deployer, usdc, compliance, owner); // sale money goes to OWNER
        TalentRegistry registry = new TalentRegistry(deployer, nodes, compliance);
        SupportVault vault =
            new SupportVault(deployer, usdc, 1e6, nodes, compliance, ITalentRegistry(address(registry)));

        // wiring + small quorums so a handful of testers can run the whole flow
        registry.setVault(ISupportVault(address(vault)));
        registry.setVerifyQuorum(1);
        vault.setVoting(1 hours, 1);

        uint64 exp = uint64(block.timestamp + 365 days);
        compliance.setWallet(owner, true, false, 840, exp);
        compliance.setWallet(address(vault), true, false, 840, exp);

        NodeLicense.Tier[] memory t = new NodeLicense.Tier[](3);
        t[0] = NodeLicense.Tier(1_000, 250e6);
        t[1] = NodeLicense.Tier(3_000, 500e6);
        t[2] = NodeLicense.Tier(5_000, 1_000e6);
        nodes.setTiers(t);
        nodes.unpause();

        // founding node #1 to the owner so they can nominate and vote right away
        nodes.grant(owner, 1);

        // hand over every role, then renounce
        bytes32 ADMIN = 0x00;
        compliance.grantRole(compliance.COMPLIANCE_ROLE(), owner);
        compliance.grantRole(ADMIN, owner);
        nodes.grantRole(nodes.SALE_ADMIN_ROLE(), owner);
        nodes.grantRole(ADMIN, owner);
        registry.grantRole(registry.VERIFIER_ROLE(), owner);
        registry.grantRole(ADMIN, owner);
        vault.grantRole(ADMIN, owner);

        compliance.renounceRole(compliance.COMPLIANCE_ROLE(), deployer);
        compliance.renounceRole(ADMIN, deployer);
        nodes.renounceRole(nodes.SALE_ADMIN_ROLE(), deployer);
        nodes.renounceRole(ADMIN, deployer);
        registry.renounceRole(registry.VERIFIER_ROLE(), deployer);
        registry.renounceRole(ADMIN, deployer);
        vault.renounceRole(ADMIN, deployer);

        vm.stopBroadcast();

        console2.log("OWNER             ", owner);
        console2.log("ComplianceRegistry", address(compliance));
        console2.log("NodeLicense       ", address(nodes));
        console2.log("TalentRegistry    ", address(registry));
        console2.log("SupportVault      ", address(vault));
    }
}
