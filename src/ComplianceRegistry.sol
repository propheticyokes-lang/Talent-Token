// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title ComplianceRegistry
/// @notice Single source of truth for which wallets have passed KYC / eligibility checks.
///         Every Talent Token contract asks this registry before allowing a mint or transfer,
///         so one compliance decision applies across the whole ecosystem.
contract ComplianceRegistry is AccessControl {
    bytes32 public constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE");

    struct Status {
        bool verified;       // passed KYC with the off-chain provider
        bool accredited;     // accredited-investor flag (only used if counsel requires it)
        uint16 countryCode;  // ISO 3166-1 numeric
        uint64 expiresAt;    // KYC re-check date (unix seconds)
    }

    mapping(address => Status) private _status;
    mapping(uint16 => bool) public blockedCountry;

    event WalletUpdated(address indexed wallet, bool verified, bool accredited, uint16 countryCode, uint64 expiresAt);
    event CountryBlocked(uint16 indexed countryCode, bool blocked);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(COMPLIANCE_ROLE, admin);
    }

    function setWallet(address wallet, bool verified, bool accredited, uint16 countryCode, uint64 expiresAt)
        public
        onlyRole(COMPLIANCE_ROLE)
    {
        _status[wallet] = Status(verified, accredited, countryCode, expiresAt);
        emit WalletUpdated(wallet, verified, accredited, countryCode, expiresAt);
    }

    function setWallets(address[] calldata wallets, bool verified, bool accredited, uint16 countryCode, uint64 expiresAt)
        external
        onlyRole(COMPLIANCE_ROLE)
    {
        for (uint256 i; i < wallets.length; ++i) {
            setWallet(wallets[i], verified, accredited, countryCode, expiresAt);
        }
    }

    function setCountryBlocked(uint16 countryCode, bool blocked) external onlyRole(COMPLIANCE_ROLE) {
        blockedCountry[countryCode] = blocked;
        emit CountryBlocked(countryCode, blocked);
    }

    /// @notice True when the wallet may hold or receive ecosystem assets right now.
    function isAllowed(address wallet) public view returns (bool) {
        Status memory s = _status[wallet];
        return s.verified && !blockedCountry[s.countryCode] && s.expiresAt >= block.timestamp;
    }

    function isAccredited(address wallet) external view returns (bool) {
        return isAllowed(wallet) && _status[wallet].accredited;
    }

    function statusOf(address wallet) external view returns (Status memory) {
        return _status[wallet];
    }
}
