# Talent Token — Launch Strategy

*"The kingdom of heaven suffereth violence, and the violent take it by force." — Matthew 11:12*

## The idea in one paragraph
Talent Token lets grassroots supporters back gifted people early: athletes, musicians,
students, entrepreneurs and ministries, at local, regional, national and international
levels. It starts with soccer and **King David André**. A capped set of **5,000 Node
Licenses** creates the founding community of "Talent Scouts". Scouts nominate talent, vote
to verify it, and vote on when supporter money is released to the talent.

## How the pieces fit

| Piece | What it does | Contract |
|---|---|---|
| Node License | 5,000 max, ever. Gives scouting votes, milestone votes, and early access. Sold in price tiers. Non-transferable at launch. | `NodeLicense.sol` |
| Compliance | One KYC allow-list for the whole ecosystem. Can block countries. KYC expires and must be renewed. | `ComplianceRegistry.sol` |
| Talent Registry | Nominate, then node vote, then ID/age check, then the talent's own consent, then launch. Minors can be listed but **never tokenized**. | `TalentRegistry.sol` |
| Talent Token | One supporter token per talent (e.g. `$KDA`). Fixed supply. Used for perks, fan votes and recognition. | `TalentToken.sol` |
| Support Vault | Supporters send USDC and receive supporter tokens. The money sits in escrow and is released in milestones that nodes approve. If a talent is frozen, supporters get a refund. | `SupportVault.sol` |

Example token split per talent: 20% talent, 60% supporters (Vault), 10% node early-access
pool, 10% community/ministry treasury. You can set this per launch.

Example node tiers: 1–1,000 at $250, 1,001–3,000 at $500, 3,001–5,000 at $1,000. That is
$3.25M gross if every node sells. These are placeholders, not a forecast.

## Two lines the code deliberately does not cross
1. **No share of the talent's earnings.** FIFA's transfer rules (RSTP Art. 18ter) ban
   anyone except clubs and the player from owning a player's economic rights, such as
   transfer fees. A token paying holders out of David's future contract would put his
   career at risk. NCAA/NIL and other federations have similar rules.
2. **No yield or revenue share for node holders.** If you sell nodes and supporter tokens
   as a way to profit from other people's work, they are very likely securities under US
   law (the Howey test). Crypto rules in the US are still changing. A securities lawyer has
   to sign off before any money is taken, on how it's marketed as much as on the code. If
   counsel approves a profit feature, add it later as a separate, reviewed module.

## Phased rollout
**Phase 0: Foundation (weeks 0–4)**
- Choose the entity that sells nodes and holds the treasury. It is probably a for-profit
  LLC kept separate from the 501(c)(3), with a written agreement for any ministry giving.
- Securities counsel reviews this repo and the marketing copy.
- Pick a KYC provider (e.g. Persona, Sumsub, Coinbase Verifications on Base).
- Set up a Safe multisig (2-of-3 or 3-of-5) as `ADMIN`.

**Phase 1: Testnet pilot (weeks 4–8)**
- Deploy to Base Sepolia. Run the full flow with David as the first talent, using test USDC.
- Get an outside smart-contract audit before mainnet.

**Phase 2: Founding Scouts (first 500–1,000 nodes)**
- Sell the lowest tier to the closest community: the academy, ministry and families.
- Launch `$KDA` with clear milestones, e.g. a European trial trip, training camp or video
  production. Every release is public on-chain.

**Phase 3: Expand sectors**
- Add music (the David André album), academics and entrepreneurship. Connect it to the
  overlooked-talent agency: the scouting pipeline becomes nominations.

## What supporters get (utility, not profit)
Early-supporter badges, fan votes (walk-out song, jersey design, content), meet-and-greets,
first access to tickets and merch, and a public on-chain record that they believed first.
