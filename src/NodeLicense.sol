// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ComplianceRegistry} from "./ComplianceRegistry.sol";

/// @title Talent Token Node License
/// @notice A hard-capped set of no more than 5,000 node licenses. A node holder is a
///         "Talent Scout": they nominate and vote to verify new talent, vote on milestone
///         releases from the SupportVault, and get early-access supporter allocations.
/// @dev    No revenue share or yield is coded here on purpose. Adding one is a legal
///         decision (securities law), not a coding decision. See docs/STRATEGY.md.
contract NodeLicense is ERC721, AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant SALE_ADMIN_ROLE = keccak256("SALE_ADMIN_ROLE");

    /// @notice Hard ceiling. Cannot be raised by anyone, ever.
    uint256 public constant MAX_SUPPLY = 5_000;

    struct Tier {
        uint32 cap;      // cumulative supply at which this tier ends
        uint128 price;   // price per node in payment-token units (e.g. USDC, 6 decimals)
    }

    IERC20 public immutable paymentToken;
    ComplianceRegistry public immutable compliance;
    address public treasury;

    Tier[] public tiers;
    uint256 public totalMinted;
    uint256 public maxPerWallet = 10;
    bool public transfersLocked = true; // nodes are non-transferable until admin unlocks
    string private _baseTokenURI;

    mapping(address => uint256) public mintedBy;

    event NodesPurchased(address indexed buyer, uint256 quantity, uint256 totalPaid, uint256 firstTokenId);
    event TiersSet(uint256 count);
    event TransfersLocked(bool locked);
    event TreasuryChanged(address treasury);

    error NotCompliant(address wallet);
    error SoldOut();
    error ExceedsWalletCap();
    error BadTiers();
    error TransfersAreLocked();

    constructor(address admin, IERC20 paymentToken_, ComplianceRegistry compliance_, address treasury_)
        ERC721("Talent Token Node", "TTNODE")
    {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(SALE_ADMIN_ROLE, admin);
        paymentToken = paymentToken_;
        compliance = compliance_;
        treasury = treasury_;
        _pause(); // sale starts closed
    }

    // ---------------------------------------------------------------- sale setup

    /// @notice Tiers must have strictly increasing caps and the last cap must be exactly MAX_SUPPLY.
    function setTiers(Tier[] calldata newTiers) external onlyRole(SALE_ADMIN_ROLE) {
        if (newTiers.length == 0 || newTiers[newTiers.length - 1].cap != MAX_SUPPLY) revert BadTiers();
        delete tiers;
        uint32 prev;
        for (uint256 i; i < newTiers.length; ++i) {
            if (newTiers[i].cap <= prev) revert BadTiers();
            prev = newTiers[i].cap;
            tiers.push(newTiers[i]);
        }
        emit TiersSet(newTiers.length);
    }

    function setMaxPerWallet(uint256 cap) external onlyRole(SALE_ADMIN_ROLE) { maxPerWallet = cap; }
    function setTreasury(address t) external onlyRole(DEFAULT_ADMIN_ROLE) { treasury = t; emit TreasuryChanged(t); }
    function setBaseURI(string calldata uri) external onlyRole(SALE_ADMIN_ROLE) { _baseTokenURI = uri; }
    function setTransfersLocked(bool locked) external onlyRole(DEFAULT_ADMIN_ROLE) { transfersLocked = locked; emit TransfersLocked(locked); }
    function pause() external onlyRole(SALE_ADMIN_ROLE) { _pause(); }
    function unpause() external onlyRole(SALE_ADMIN_ROLE) { _unpause(); }

    // ---------------------------------------------------------------- pricing

    /// @notice Total cost of the next `quantity` nodes, walking across tier boundaries.
    function quote(uint256 quantity) public view returns (uint256 cost) {
        if (totalMinted + quantity > MAX_SUPPLY) revert SoldOut();
        uint256 cursor = totalMinted;
        uint256 remaining = quantity;
        for (uint256 i; i < tiers.length && remaining > 0; ++i) {
            uint256 cap = tiers[i].cap;
            if (cursor >= cap) continue;
            uint256 take = cap - cursor;
            if (take > remaining) take = remaining;
            cost += take * tiers[i].price;
            cursor += take;
            remaining -= take;
        }
        if (remaining != 0) revert BadTiers();
    }

    function currentPrice() external view returns (uint256) {
        for (uint256 i; i < tiers.length; ++i) {
            if (totalMinted < tiers[i].cap) return tiers[i].price;
        }
        revert SoldOut();
    }

    // ---------------------------------------------------------------- mint

    function purchase(uint256 quantity) external whenNotPaused nonReentrant {
        if (!compliance.isAllowed(msg.sender)) revert NotCompliant(msg.sender);
        if (mintedBy[msg.sender] + quantity > maxPerWallet) revert ExceedsWalletCap();
        uint256 cost = quote(quantity); // reverts if it would pass 5,000

        uint256 first = totalMinted + 1;
        totalMinted += quantity;
        mintedBy[msg.sender] += quantity;

        paymentToken.safeTransferFrom(msg.sender, treasury, cost);
        for (uint256 i; i < quantity; ++i) {
            _safeMint(msg.sender, first + i);
        }
        emit NodesPurchased(msg.sender, quantity, cost, first);
    }

    /// @notice Reserved grants (team, founding scouts, partners). Still counts toward the 5,000 cap.
    function grant(address to, uint256 quantity) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (totalMinted + quantity > MAX_SUPPLY) revert SoldOut();
        if (!compliance.isAllowed(to)) revert NotCompliant(to);
        uint256 first = totalMinted + 1;
        totalMinted += quantity;
        for (uint256 i; i < quantity; ++i) {
            _safeMint(to, first + i);
        }
    }

    // ---------------------------------------------------------------- transfer rules

    function _update(address to, uint256 tokenId, address auth) internal override returns (address from) {
        from = _ownerOf(tokenId);
        bool isMint = from == address(0);
        if (!isMint) {
            if (transfersLocked) revert TransfersAreLocked();
            if (to != address(0) && !compliance.isAllowed(to)) revert NotCompliant(to);
        }
        return super._update(to, tokenId, auth);
    }

    function _baseURI() internal view override returns (string memory) { return _baseTokenURI; }

    function supportsInterface(bytes4 id) public view override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(id);
    }
}
