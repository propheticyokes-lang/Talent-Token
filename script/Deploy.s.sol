// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ComplianceRegistry} from "../src/ComplianceRegistry.sol";
import {NodeLicense} from "../src/NodeLicense.sol";
import {TalentRegistry} from "../src/TalentRegistry.sol";
import {SupportVault, ITalentRegistry} from "../src/SupportVault.sol";

/// Usage (TESTNET FIRST):
///   forge script script/Deploy.s.sol --rpc-url base_sepolia --broadcast --verify
/// Env: ADMIN (a Safe multisig on mainnet), TREASURY, USDC
///   Base Sepolia USDC: 0x036CbD53842c5426634e7929541eC2318f3dCF7e
///   Base mainnet USDC: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
contract Deploy is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN");
        address treasury = vm.envAddress("TREASURY");
        IERC20 usdc = IERC20(vm.envAddress("USDC"));

        vm.startBroadcast();
        ComplianceRegistry compliance = new ComplianceRegistry(admin);
        NodeLicense nodes = new NodeLicense(admin, usdc, compliance, treasury);
        TalentRegistry registry = new TalentRegistry(admin, nodes, compliance);
        SupportVault vault = new SupportVault(admin, usdc, 1e6, nodes, compliance, ITalentRegistry(address(registry)));
        vm.stopBroadcast();

        console2.log("ComplianceRegistry", address(compliance));
        console2.log("NodeLicense       ", address(nodes));
        console2.log("TalentRegistry    ", address(registry));
        console2.log("SupportVault      ", address(vault));
        console2.log("Next, from ADMIN: registry.setVault(vault); allow-list vault, treasury, node pool,");
        console2.log("community treasury in ComplianceRegistry; nodes.setTiers(...); nodes.unpause().");
    }
}
