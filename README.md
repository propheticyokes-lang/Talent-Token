# Talent Token

Smart contracts for a 5,000-node Talent Scout network and per-talent supporter tokens on Base.
It starts with soccer and King David André.

- `src/` — contracts: `NodeLicense`, `ComplianceRegistry`, `TalentRegistry`, `TalentToken`, `SupportVault`
- `test/` — Foundry tests covering the full flow
- `script/Deploy.s.sol` — testnet/mainnet deploy
- `model/` — Python reference model of the sale and refund math
- `docs/STRATEGY.md` — the business and launch plan
- `CLAUDE.md` — brief for the AI engineering agent (Claude Code reads it automatically)

**Status:** first draft. Not yet compiled in CI, not audited. Testnet only.
