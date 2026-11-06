// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ComplianceRegistry} from "./ComplianceRegistry.sol";

interface ITalentRegistry {
    enum Status { None, Nominated, Verified, Launched, Delisted }
    function statusOf(uint256 talentId) external view returns (Status);
}

/// @title SupportVault
/// @notice Grassroots supporters back a talent with stablecoin (USDC). Money is held in
///         escrow per talent and only released to the talent in MILESTONES that node holders
///         vote to approve (e.g. "trial travel to Spain", "studio time", "tuition").
///         If a talent is delisted, supporters can reclaim their share of unreleased funds.
contract SupportVault is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable paymentToken;       // USDC on Base
    uint256 public immutable paymentUnit;       // 1e6 for USDC
    IERC721 public immutable nodes;
    ComplianceRegistry public immutable compliance;
    ITalentRegistry public immutable registry;

    uint64 public votingPeriod = 5 days;
    uint32 public milestoneQuorum = 50; // node votes (yes + no) required for a valid decision

    struct Pool {
        address token;         // TalentToken
        address talentWallet;
        uint256 tokensPerUnit; // supporter tokens per 1 payment unit
        uint256 raised;
        uint256 released;
        uint256 pending;       // committed to open milestones
        bool active;
    }

    struct Milestone {
        uint256 talentId;
        uint256 amount;
        string uri;            // what the money is for + proof plan
        uint64 deadline;
        uint32 yes;
        uint32 no;
        bool finalized;
        bool approved;
    }

    mapping(uint256 => Pool) public pools;
    mapping(uint256 => mapping(address => uint256)) public contributed;
    mapping(uint256 => mapping(address => bool)) public refunded;
    Milestone[] public milestones;
    mapping(uint256 => mapping(uint256 => bool)) public milestoneNodeVoted; // milestoneId => nodeId

    event TalentRegistered(uint256 indexed talentId, address token, address talentWallet);
    event Supported(uint256 indexed talentId, address indexed supporter, uint256 amount, uint256 tokensOut);
    event MilestoneProposed(uint256 indexed milestoneId, uint256 indexed talentId, uint256 amount, string uri);
    event MilestoneVoted(uint256 indexed milestoneId, uint256 nodeId, bool approve);
    event MilestoneFinalized(uint256 indexed milestoneId, bool approved, uint256 amount);
    event Refunded(uint256 indexed talentId, address indexed supporter, uint256 amount);

    error NotCompliant(address wallet);
    error NotActive();
    error NotTalent();
    error NotNodeHolder();
    error AlreadyVoted(uint256 nodeId);
    error VotingClosed();
    error VotingOpen();
    error InsufficientEscrow();
    error NothingToRefund();

    constructor(
        address admin,
        IERC20 paymentToken_,
        uint256 paymentUnit_,
        IERC721 nodes_,
        ComplianceRegistry compliance_,
        ITalentRegistry registry_
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        paymentToken = paymentToken_;
        paymentUnit = paymentUnit_;
        nodes = nodes_;
        compliance = compliance_;
        registry = registry_;
    }

    function setVoting(uint64 period, uint32 quorum) external onlyRole(DEFAULT_ADMIN_ROLE) {
        votingPeriod = period;
        milestoneQuorum = quorum;
    }

    function registerTalent(uint256 talentId, address token, address talentWallet, uint256 tokensPerUnit) external {
        require(msg.sender == address(registry), "only registry");
        pools[talentId] = Pool(token, talentWallet, tokensPerUnit, 0, 0, 0, true);
        emit TalentRegistered(talentId, token, talentWallet);
    }

    function _live(uint256 talentId) internal view returns (bool) {
        return pools[talentId].active && registry.statusOf(talentId) == ITalentRegistry.Status.Launched;
    }

    // ---------------------------------------------------------------- supporters

    function support(uint256 talentId, uint256 amount) external nonReentrant {
        if (!_live(talentId)) revert NotActive();
        if (!compliance.isAllowed(msg.sender)) revert NotCompliant(msg.sender);
        Pool storage p = pools[talentId];

        uint256 tokensOut = (amount * p.tokensPerUnit) / paymentUnit;
        p.raised += amount;
        contributed[talentId][msg.sender] += amount;

        paymentToken.safeTransferFrom(msg.sender, address(this), amount);
        IERC20(p.token).safeTransfer(msg.sender, tokensOut); // reverts if the vault allocation is used up
        emit Supported(talentId, msg.sender, amount, tokensOut);
    }

    // ---------------------------------------------------------------- milestones

    function available(uint256 talentId) public view returns (uint256) {
        Pool storage p = pools[talentId];
        return p.raised - p.released - p.pending;
    }

    function proposeMilestone(uint256 talentId, uint256 amount, string calldata uri) external returns (uint256 id) {
        if (!_live(talentId)) revert NotActive();
        Pool storage p = pools[talentId];
        if (msg.sender != p.talentWallet) revert NotTalent();
        if (amount > available(talentId)) revert InsufficientEscrow();
        p.pending += amount;
        id = milestones.length;
        milestones.push(Milestone(talentId, amount, uri, uint64(block.timestamp) + votingPeriod, 0, 0, false, false));
        emit MilestoneProposed(id, talentId, amount, uri);
    }

    function voteMilestone(uint256 milestoneId, uint256[] calldata nodeIds, bool approve) external {
        Milestone storage m = milestones[milestoneId];
        if (block.timestamp > m.deadline || m.finalized) revert VotingClosed();
        for (uint256 i; i < nodeIds.length; ++i) {
            uint256 n = nodeIds[i];
            if (nodes.ownerOf(n) != msg.sender) revert NotNodeHolder();
            if (milestoneNodeVoted[milestoneId][n]) revert AlreadyVoted(n);
            milestoneNodeVoted[milestoneId][n] = true;
            if (approve) m.yes += 1; else m.no += 1;
            emit MilestoneVoted(milestoneId, n, approve);
        }
    }

    function finalizeMilestone(uint256 milestoneId) external nonReentrant {
        Milestone storage m = milestones[milestoneId];
        if (m.finalized) revert VotingClosed();
        if (block.timestamp <= m.deadline) revert VotingOpen();
        Pool storage p = pools[m.talentId];

        m.finalized = true;
        p.pending -= m.amount;
        bool ok = (m.yes + m.no) >= milestoneQuorum && m.yes > m.no && _live(m.talentId);
        m.approved = ok;
        if (ok) {
            p.released += m.amount;
            paymentToken.safeTransfer(p.talentWallet, m.amount);
        }
        emit MilestoneFinalized(milestoneId, ok, m.amount);
    }

    // ---------------------------------------------------------------- protection

    /// @notice Admin can freeze a pool (e.g. talent breaks the code of conduct). No new support,
    ///         no new releases; supporters can then refund.
    function freeze(uint256 talentId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        pools[talentId].active = false;
    }

    /// @notice After a pool is frozen or the talent delisted, each supporter can reclaim their
    ///         pro-rata share of money that was never released. `raised` and `released` are fixed
    ///         once the pool is not live, so every supporter gets the same ratio.
    function refund(uint256 talentId) external nonReentrant {
        if (_live(talentId)) revert NotActive();
        Pool storage p = pools[talentId];
        if (p.pending != 0) revert VotingOpen(); // open milestones must be finalized (they will fail) first
        uint256 c = contributed[talentId][msg.sender];
        if (c == 0 || refunded[talentId][msg.sender]) revert NothingToRefund();
        refunded[talentId][msg.sender] = true;
        uint256 amount = (c * (p.raised - p.released)) / p.raised;
        paymentToken.safeTransfer(msg.sender, amount);
        emit Refunded(talentId, msg.sender, amount);
    }

    function milestoneCount() external view returns (uint256) { return milestones.length; }
}
