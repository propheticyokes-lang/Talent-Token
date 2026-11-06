// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ComplianceRegistry} from "./ComplianceRegistry.sol";
import {TalentToken} from "./TalentToken.sol";

interface ISupportVault {
    function registerTalent(uint256 talentId, address token, address talentWallet, uint256 tokensPerUnit) external;
}

/// @title TalentRegistry
/// @notice Node holders (Talent Scouts) nominate godly-gifted talent and vote to verify them.
///         A verified, consenting ADULT talent can then be launched with its own TalentToken.
///         Minors can be listed for scouting visibility but can never be tokenized.
contract TalentRegistry is AccessControl {
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE"); // checks ID, age, consent off-chain

    enum Sector { Athletics, Music, Academia, Entrepreneurship, Ministry }
    enum Level { Local, Regional, National, International }
    enum Status { None, Nominated, Verified, Launched, Delisted }

    struct Talent {
        string name;
        string metadataURI;   // IPFS JSON: bio, highlights, stats, photos
        address wallet;       // talent's own wallet (must be KYC'd)
        Sector sector;
        Level level;
        Status status;
        bool identityChecked; // VERIFIER confirmed identity + age 18+
        bool consented;       // talent signed their own acceptance on-chain
        uint32 votes;
        address token;
        address nominatedBy;
    }

    IERC721 public immutable nodes;
    ComplianceRegistry public immutable compliance;
    ISupportVault public vault;

    uint32 public verifyQuorum = 25; // node votes needed to verify a nominee
    uint256 public nextTalentId = 1;

    mapping(uint256 => Talent) public talents;
    mapping(uint256 => mapping(uint256 => bool)) public nodeVoted; // talentId => nodeId => voted

    event Nominated(uint256 indexed talentId, string name, Sector sector, Level level, address indexed by);
    event Voted(uint256 indexed talentId, uint256 nodeId, uint32 totalVotes);
    event Verified(uint256 indexed talentId);
    event IdentityChecked(uint256 indexed talentId);
    event Consented(uint256 indexed talentId);
    event Launched(uint256 indexed talentId, address token);
    event Delisted(uint256 indexed talentId, string reason);

    error NotNodeHolder();
    error WrongStatus();
    error AlreadyVoted(uint256 nodeId);
    error NotReady();

    constructor(address admin, IERC721 nodes_, ComplianceRegistry compliance_) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(VERIFIER_ROLE, admin);
        nodes = nodes_;
        compliance = compliance_;
    }

    function setVault(ISupportVault v) external onlyRole(DEFAULT_ADMIN_ROLE) { vault = v; }
    function setVerifyQuorum(uint32 q) external onlyRole(DEFAULT_ADMIN_ROLE) { verifyQuorum = q; }

    // ---------------------------------------------------------------- scouting

    function nominate(
        uint256 nodeId,
        string calldata name,
        Sector sector,
        Level level,
        string calldata metadataURI,
        address wallet
    ) external returns (uint256 id) {
        if (nodes.ownerOf(nodeId) != msg.sender) revert NotNodeHolder();
        id = nextTalentId++;
        Talent storage t = talents[id];
        t.name = name;
        t.metadataURI = metadataURI;
        t.wallet = wallet;
        t.sector = sector;
        t.level = level;
        t.status = Status.Nominated;
        t.nominatedBy = msg.sender;
        emit Nominated(id, name, sector, level, msg.sender);
    }

    /// @notice One vote per node per nominee. Pass every node you hold to vote with all of them.
    function vote(uint256 talentId, uint256[] calldata nodeIds) external {
        Talent storage t = talents[talentId];
        if (t.status != Status.Nominated) revert WrongStatus();
        for (uint256 i; i < nodeIds.length; ++i) {
            uint256 n = nodeIds[i];
            if (nodes.ownerOf(n) != msg.sender) revert NotNodeHolder();
            if (nodeVoted[talentId][n]) revert AlreadyVoted(n);
            nodeVoted[talentId][n] = true;
            t.votes += 1;
            emit Voted(talentId, n, t.votes);
        }
        if (t.votes >= verifyQuorum) {
            t.status = Status.Verified;
            emit Verified(talentId);
        }
    }

    /// @notice Off-chain check done: government ID, age 18+, and (for athletes) no conflict
    ///         with club, federation or college eligibility rules.
    function markIdentityChecked(uint256 talentId) external onlyRole(VERIFIER_ROLE) {
        talents[talentId].identityChecked = true;
        emit IdentityChecked(talentId);
    }

    /// @notice The talent must personally opt in from their own wallet. Nobody can be tokenized without it.
    function consent(uint256 talentId) external {
        Talent storage t = talents[talentId];
        require(msg.sender == t.wallet, "only the talent");
        t.consented = true;
        emit Consented(talentId);
    }

    // ---------------------------------------------------------------- launch

    struct LaunchParams {
        string tokenName;      // "King David Andre Supporter"
        string tokenSymbol;    // "KDA"
        uint256 talentAmount;  // kept by the talent (e.g. 20%)
        uint256 vaultAmount;   // sold/given to supporters through the SupportVault (e.g. 60%)
        uint256 nodePoolAmount;// early-access pool for node holders (e.g. 10%)
        address nodePool;
        uint256 communityAmount; // ecosystem / ministry treasury (e.g. 10%)
        address communityTreasury;
        uint256 tokensPerUnit; // supporter tokens per 1 unit of payment token (USDC: per 1e6)
    }

    function launch(uint256 talentId, LaunchParams calldata p) external onlyRole(DEFAULT_ADMIN_ROLE) returns (address) {
        Talent storage t = talents[talentId];
        if (t.status != Status.Verified) revert WrongStatus();
        if (!t.identityChecked || !t.consented || !compliance.isAllowed(t.wallet)) revert NotReady();
        require(address(vault) != address(0), "vault not set");

        address[] memory to = new address[](4);
        uint256[] memory amt = new uint256[](4);
        (to[0], amt[0]) = (t.wallet, p.talentAmount);
        (to[1], amt[1]) = (address(vault), p.vaultAmount);
        (to[2], amt[2]) = (p.nodePool, p.nodePoolAmount);
        (to[3], amt[3]) = (p.communityTreasury, p.communityAmount);

        TalentToken token = new TalentToken(p.tokenName, p.tokenSymbol, talentId, compliance, to, amt);
        t.token = address(token);
        t.status = Status.Launched;
        vault.registerTalent(talentId, address(token), t.wallet, p.tokensPerUnit);
        emit Launched(talentId, address(token));
        return address(token);
    }

    function delist(uint256 talentId, string calldata reason) external onlyRole(DEFAULT_ADMIN_ROLE) {
        talents[talentId].status = Status.Delisted;
        emit Delisted(talentId, reason);
    }

    function statusOf(uint256 talentId) external view returns (Status) { return talents[talentId].status; }
    function walletOf(uint256 talentId) external view returns (address) { return talents[talentId].wallet; }
}
