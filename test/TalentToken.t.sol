// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ComplianceRegistry} from "../src/ComplianceRegistry.sol";
import {NodeLicense} from "../src/NodeLicense.sol";
import {TalentRegistry, ISupportVault} from "../src/TalentRegistry.sol";
import {TalentToken} from "../src/TalentToken.sol";
import {SupportVault, ITalentRegistry} from "../src/SupportVault.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}
    function decimals() public pure override returns (uint8) { return 6; }
    function mint(address to, uint256 amt) external { _mint(to, amt); }
}

contract TalentTokenTest is Test {
    address admin = address(0xA11CE);
    address treasury = address(0x7EA5);
    address david = address(0xDA71D);      // talent wallet
    address fan = address(0xFA11);
    address outsider = address(0xBAD);
    address nodePool = address(0x9001);
    address community = address(0xC0FE);

    MockUSDC usdc;
    ComplianceRegistry compliance;
    NodeLicense nodes;
    TalentRegistry registry;
    SupportVault vault;

    address[] scouts;

    function setUp() public {
        vm.warp(1_800_000_000);
        usdc = new MockUSDC();
        compliance = new ComplianceRegistry(admin);
        nodes = new NodeLicense(admin, usdc, compliance, treasury);
        registry = new TalentRegistry(admin, nodes, compliance);
        vault = new SupportVault(admin, usdc, 1e6, nodes, compliance, ITalentRegistry(address(registry)));

        vm.startPrank(admin);
        registry.setVault(ISupportVault(address(vault)));
        registry.setVerifyQuorum(3);
        vault.setVoting(5 days, 3);

        uint64 exp = uint64(block.timestamp + 365 days);
        address[] memory ok = new address[](6);
        (ok[0], ok[1], ok[2], ok[3], ok[4], ok[5]) = (david, fan, address(vault), nodePool, community, treasury);
        compliance.setWallets(ok, true, false, 840, exp);

        NodeLicense.Tier[] memory t = new NodeLicense.Tier[](3);
        t[0] = NodeLicense.Tier(1_000, 250e6);  // first 1,000 nodes at $250
        t[1] = NodeLicense.Tier(3_000, 500e6);  // next 2,000 at $500
        t[2] = NodeLicense.Tier(5_000, 1_000e6);// last 2,000 at $1,000
        nodes.setTiers(t);
        nodes.unpause();
        vm.stopPrank();

        for (uint256 i; i < 5; ++i) {
            address s = address(uint160(0x5C0000 + i));
            scouts.push(s);
            vm.prank(admin);
            compliance.setWallet(s, true, false, 840, exp);
            usdc.mint(s, 10_000e6);
            vm.startPrank(s);
            usdc.approve(address(nodes), type(uint256).max);
            nodes.purchase(1);
            vm.stopPrank();
        }
    }

    // ---------------------------------------------------------------- node cap

    function test_MaxSupplyIs5000() public view {
        assertEq(nodes.MAX_SUPPLY(), 5_000);
    }

    function test_CannotMintPast5000() public {
        uint256 toGrant = 5_000 - nodes.totalMinted();
        vm.startPrank(admin);
        nodes.grant(treasury, toGrant);
        vm.expectRevert(NodeLicense.SoldOut.selector);
        nodes.grant(treasury, 1);
        vm.stopPrank();
    }

    function test_TierPricingAcrossBoundary() public {
        uint256 toGrant = 995 - nodes.totalMinted(); // read first: vm.prank applies to the next call only
        vm.prank(admin);
        nodes.grant(treasury, toGrant); // 995 minted
        // 5 @ $250 + 3 @ $500
        assertEq(nodes.quote(8), 5 * 250e6 + 3 * 500e6);
    }

    function test_NonKycCannotBuy() public {
        usdc.mint(outsider, 1_000e6);
        vm.startPrank(outsider);
        usdc.approve(address(nodes), type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(NodeLicense.NotCompliant.selector, outsider));
        nodes.purchase(1);
        vm.stopPrank();
    }

    function test_NodesLockedByDefault() public {
        vm.prank(scouts[0]);
        vm.expectRevert(NodeLicense.TransfersAreLocked.selector);
        nodes.transferFrom(scouts[0], fan, 1);
    }

    function test_PaymentGoesToTreasury() public view {
        assertEq(usdc.balanceOf(treasury), 5 * 250e6);
    }

    // ---------------------------------------------------------------- talent flow

    function _nominateAndVerify() internal returns (uint256 id) {
        vm.prank(scouts[0]);
        id = registry.nominate(1, "King David Andre", TalentRegistry.Sector.Athletics, TalentRegistry.Level.International, "ipfs://kda", david);
        for (uint256 i; i < 3; ++i) {
            uint256[] memory n = new uint256[](1);
            n[0] = i + 1;
            vm.prank(scouts[i]);
            registry.vote(id, n);
        }
    }

    function _params() internal view returns (TalentRegistry.LaunchParams memory) {
        return TalentRegistry.LaunchParams({
            tokenName: "King David Andre Supporter",
            tokenSymbol: "KDA",
            talentAmount: 2_000_000e18,
            vaultAmount: 6_000_000e18,
            nodePoolAmount: 1_000_000e18,
            nodePool: nodePool,
            communityAmount: 1_000_000e18,
            communityTreasury: community,
            tokensPerUnit: 100e18 // 100 KDA per $1
        });
    }

    function _launch() internal returns (uint256 id, TalentToken token) {
        id = _nominateAndVerify();
        vm.prank(admin);
        registry.markIdentityChecked(id);
        vm.prank(david);
        registry.consent(id);
        vm.prank(admin);
        token = TalentToken(registry.launch(id, _params()));
    }

    function test_VotesVerifyNominee() public {
        uint256 id = _nominateAndVerify();
        assertEq(uint256(registry.statusOf(id)), uint256(TalentRegistry.Status.Verified));
    }

    function test_SameNodeCannotVoteTwice() public {
        vm.prank(scouts[0]);
        uint256 id = registry.nominate(1, "X", TalentRegistry.Sector.Music, TalentRegistry.Level.Local, "", david);
        uint256[] memory n = new uint256[](1);
        n[0] = 1;
        vm.startPrank(scouts[0]);
        registry.vote(id, n);
        vm.expectRevert(abi.encodeWithSelector(TalentRegistry.AlreadyVoted.selector, 1));
        registry.vote(id, n);
        vm.stopPrank();
    }

    function test_CannotLaunchWithoutConsent() public {
        uint256 id = _nominateAndVerify();
        vm.startPrank(admin);
        registry.markIdentityChecked(id);
        vm.expectRevert(TalentRegistry.NotReady.selector);
        registry.launch(id, _params());
        vm.stopPrank();
    }

    function test_CannotLaunchWithoutIdentityCheck() public {
        uint256 id = _nominateAndVerify();
        vm.prank(david);
        registry.consent(id);
        vm.prank(admin);
        vm.expectRevert(TalentRegistry.NotReady.selector);
        registry.launch(id, _params());
    }

    function test_LaunchAllocations() public {
        (, TalentToken token) = _launch();
        assertEq(token.totalSupply(), 10_000_000e18);
        assertEq(token.balanceOf(david), 2_000_000e18);
        assertEq(token.balanceOf(address(vault)), 6_000_000e18);
    }

    function test_SupportMintsSupporterTokens() public {
        (uint256 id, TalentToken token) = _launch();
        usdc.mint(fan, 100e6);
        vm.startPrank(fan);
        usdc.approve(address(vault), 100e6);
        vault.support(id, 100e6);
        vm.stopPrank();
        assertEq(token.balanceOf(fan), 10_000e18);
        assertEq(vault.available(id), 100e6);
    }

    function test_TalentTokenBlocksNonKyc() public {
        (uint256 id, TalentToken token) = _launch();
        usdc.mint(fan, 10e6);
        vm.startPrank(fan);
        usdc.approve(address(vault), 10e6);
        vault.support(id, 10e6);
        vm.expectRevert(abi.encodeWithSelector(TalentToken.NotCompliant.selector, outsider));
        token.transfer(outsider, 1e18);
        vm.stopPrank();
    }

    function _fund(uint256 id, uint256 amt) internal {
        usdc.mint(fan, amt);
        vm.startPrank(fan);
        usdc.approve(address(vault), amt);
        vault.support(id, amt);
        vm.stopPrank();
    }

    function test_MilestoneApprovedReleasesFunds() public {
        (uint256 id,) = _launch();
        _fund(id, 1_000e6);
        vm.prank(david);
        uint256 m = vault.proposeMilestone(id, 400e6, "ipfs://trial-trip-spain");
        for (uint256 i; i < 3; ++i) {
            uint256[] memory n = new uint256[](1);
            n[0] = i + 1;
            vm.prank(scouts[i]);
            vault.voteMilestone(m, n, true);
        }
        vm.warp(block.timestamp + 5 days + 1);
        vault.finalizeMilestone(m);
        assertEq(usdc.balanceOf(david), 400e6);
        assertEq(vault.available(id), 600e6);
    }

    function test_MilestoneWithoutQuorumFails() public {
        (uint256 id,) = _launch();
        _fund(id, 1_000e6);
        vm.prank(david);
        uint256 m = vault.proposeMilestone(id, 400e6, "ipfs://x");
        uint256[] memory n = new uint256[](1);
        n[0] = 1;
        vm.prank(scouts[0]);
        vault.voteMilestone(m, n, true);
        vm.warp(block.timestamp + 5 days + 1);
        vault.finalizeMilestone(m);
        assertEq(usdc.balanceOf(david), 0);
        assertEq(vault.available(id), 1_000e6);
    }

    function test_CannotOvercommitEscrow() public {
        (uint256 id,) = _launch();
        _fund(id, 100e6);
        vm.startPrank(david);
        vault.proposeMilestone(id, 80e6, "a");
        vm.expectRevert(SupportVault.InsufficientEscrow.selector);
        vault.proposeMilestone(id, 30e6, "b");
        vm.stopPrank();
    }

    function test_RefundAfterFreeze() public {
        (uint256 id,) = _launch();
        _fund(id, 1_000e6);
        vm.prank(admin);
        vault.freeze(id);
        vm.prank(fan);
        vault.refund(id);
        assertEq(usdc.balanceOf(fan), 1_000e6);
    }
}
