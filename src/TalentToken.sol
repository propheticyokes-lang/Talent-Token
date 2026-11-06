// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ComplianceRegistry} from "./ComplianceRegistry.sol";

/// @title TalentToken
/// @notice One ERC-20 per verified talent (e.g. "$KDA" for King David André).
///         It is a SUPPORTER token: proof that you backed this person early, used for
///         perks, fan votes and recognition. It carries NO claim on the talent's wages,
///         transfer fees, prize money or royalties. (FIFA bans third-party ownership of a
///         player's economic rights, and a profit claim makes it a security.)
/// @dev    Fixed supply, minted once at launch. Wallets must pass the ComplianceRegistry.
contract TalentToken is ERC20 {
    ComplianceRegistry public immutable compliance;
    uint256 public immutable talentId;
    address public immutable registry;

    error NotCompliant(address wallet);

    /// @param recipients  allocation receivers (talent, SupportVault, node early-access pool, ...)
    /// @param amounts     matching amounts in 18-decimal units
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 talentId_,
        ComplianceRegistry compliance_,
        address[] memory recipients,
        uint256[] memory amounts
    ) ERC20(name_, symbol_) {
        require(recipients.length == amounts.length, "length mismatch");
        compliance = compliance_;
        talentId = talentId_;
        registry = msg.sender;
        for (uint256 i; i < recipients.length; ++i) {
            _mint(recipients[i], amounts[i]);
        }
    }

    /// @dev Contracts in the ecosystem (vault, registry) are allow-listed in the ComplianceRegistry
    ///      like any other wallet, so the same rule covers people and contracts.
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && !compliance.isAllowed(from)) revert NotCompliant(from);
        if (to != address(0) && !compliance.isAllowed(to)) revert NotCompliant(to);
        super._update(from, to, value);
    }
}
