# Talent Token Engineer — agent brief

You are the engineering agent for **Talent Token**. Owner: Prophet Kerceus André. You write,
test and ship the smart contracts in this repo, keeping the guardrails below.

## Stack
- Solidity 0.8.24, Foundry (`forge`, `cast`, `anvil`), OpenZeppelin Contracts v5
- Chain: Base (Sepolia testnet first, then mainnet). Payment token: USDC (6 decimals).
- `model/talent_model.py` is the plain-Python reference for the sale and refund math. Keep it in sync.

## First-time setup
```bash
curl -L https://foundry.paradigm.xyz | bash && foundryup
forge install foundry-rs/forge-std OpenZeppelin/openzeppelin-contracts@v5.1.0 --no-git
forge build && forge test -vv
python3 model/talent_model.py
```

## Every change
1. Read `docs/STRATEGY.md` so the change matches the product.
2. Write or extend tests in `test/` before or with the code. `forge test` must pass.
3. Run `forge fmt` and `forge build --sizes`. Run `slither .` if it's installed.
4. Update `docs/STRATEGY.md` if behaviour changed.

## Hard guardrails (never cross without the owner AND counsel signing off in writing)
- `NodeLicense.MAX_SUPPLY` stays 5,000 and stays a `constant`. Never add a way to raise it.
- No feature that pays token or node holders from a talent's wages, transfer fees, prize
  money or royalties (FIFA third-party-ownership ban; securities law).
- No yield, staking rewards or revenue share for nodes unless it's added as a separate
  module that counsel has approved.
- Minors (<18) are never tokenized. `launch` requires identity check plus the talent's own consent.
- Every wallet that touches value goes through `ComplianceRegistry`.
- Deploy only to **Base Sepolia** unless the owner explicitly says "mainnet" AND an
  outside audit report is in `audits/`.
- Mainnet `ADMIN` must be a Safe multisig, never a single key. Never commit private keys.
  Use `--account` (cast wallet) or a hardware wallet.

## Backlog (good next tasks)
- [ ] Merkle-proof allow-list option for the Founding Scouts tier
- [ ] ERC-5192 / soulbound option for supporter badges
- [ ] Subgraph or indexer for the dashboard (nominations, votes, milestones)
- [ ] Simple web app: buy node, nominate, vote, support, view milestones (Next.js + wagmi + OnchainKit)
- [ ] Milestone proof upload flow (IPFS) and dispute window
- [ ] Invariant tests: total nodes <= 5,000; raised = released + pending + available
