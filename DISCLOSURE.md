# Disclosure

## Limits of this deployment

This section describes the new source release prepared on 2026-10-21; confirmed deployment addresses belong to the later service handoff. The records below remain the history of the two earlier deployments.

- Registry is ownerless and non-upgradeable. The single fixed oracle attester is trusted to sign correct evidence; panel agreement is not an independent cryptographic proof of truth. Key rotation, compromised signing or incompatible Intake changes cannot be repaired by a Registry administrator because none exists. The attester, the Intake, the IMD token and the action id `oracle.request@oracle-1` are fixed for the contract's life, and the oracle price is paid to the Intake when a request is made, before any answer is judged: if the plane rotates its signer, an answer signed by the new key is recorded as `Missed` (reason 2) with the fee spent and no refund path, and if the plane stops selling that action, every oracle trait is unreachable until a successor deployment. The site must not describe oracle traits as always claimable.
- Swarmed's living window relies on the IdentityMD collection, adapter `0xde152AfB7db5373F34876E1499fbD893A82dD336`, reputation registry `0x8004baa17c55a88189ae136b182e5fda19de9b63` and batcher `0xb6d0a187b050fa5bb0b87033a203f37becf4a775`. Archive logs and state must cover the full requested interval. The addresses are fixed recipe inputs; incomplete history means no answer. Any prior qualifying agent binding counts, and feedback entries, not distinct jobs, are counted inside each wallet's own holding intervals.
- Each personal or shared oracle request pays the current Intake price, observed as 0.5 IMD at block 26,237,654. Refusal, disagreement, false answers, missing callbacks and expiration spend that price. maxPrice bounds what the caller accepts, but offers no refund. Pending requests can be cleared strictly after 31 days. Accepted facts remain permanent.
- Mint (0.1 IMD) and registration (6.4 IMD) fees are forwarded to the BurnExecutor V2 for bridging and burning on Base. Registry guarantees the token forward, not an immediate burn. The executor owner can change its token, OFT, destination and options, and rescue funds. Bridging and the Base burn are separate, permissionless, asynchronous actions; anyone may or may not take them. LayerZero delivery, dust, OFT limits and receiver operation are external dependencies.
- Composer audit 1043 H-1's field-registration gap and M-2's prose injection path are closed by validation of real fields and a closed signature grammar (items 31 and 32). Its public views intentionally trust arguments, and composition is not a general-purpose validation API. Catalog anchors are exempt from community minimum windows; T4's fromBlock remains hashed; duplicate registrations cost their registrant. Off-mainnet height is a timestamp-derived upper bound, not an oracle of the actual mainnet head.
- Renderer audit 1044 M-1's offset bounds and L-3's oversized return copying are hardened in item 34, together with invalid-family handling, the 25-id catalog cap and quote escaping. A rendering is not a credential, and its output names no Registry (M-3). Verify `hasTrait` on the trusted Registry.
- The unbounded `verifiedSpecsOf` read precedes the 32-entry display cap (1044 M-2). The audit estimated unreadability around 124,000 verified specs, costing roughly 62,000 IMD at 0.5 IMD per request. That estimate exceeds this Registry's finite 55,534-spec namespace, but the whole-array read remains a gas-scaling limit and the cap does not bound its cost. No claim is made that arbitrary future RPC gas limits can render every claimant.
- All seven constructor values are nonzero and Renderer and Composer must always have code. The executor code check applies on every chain where Curator, IMD or Intake has code (mainnet, Sepolia) and is skipped only on the launch's empty-chain floor, where the protected probe creates the three application contracts and nothing else: docs/V3.md item 18 asked for it unconditionally, and the independent review showed that this parked the launch, so the check was moved inside the floor branch under the workflow's conflict rule (test/NOTES.md, point 1). The local floor rehearsal now runs with no executor code, as the probe does, and the real mainnet fork confirms the configuration against the live V2 executor. The separate manifest service must replace the historical eight-argument manifest with the seven approved values and the deployment service must simulate the actual dependencies.

The entrant's disclosed seats below remain a potential conflict of interest. Tests use synthetic wallets and do not grant those seats any exceptional rights. This source assignment performed local and fork tests, not an independent audit, live deployment, oracle lab rerun or launch announcement.

## Historical disclosures: the earlier deployments

- The entrant operates three IMD worker seats (IDMD #420, #3 and #7). They may be assigned any swarm job on this
  repository; the entry says so, and the seats are not excluded onchain, because an onchain list would name wallets.
- The entrant's seats and wallets abstain from the sponsor pool's upgrades and never appear in a showcase, a
  screenshot or a demo. Sample cards use synthetic addresses (the convention `0x…c1a1`) or public figures.
- The registry is Sworn (collection symbol SWORN). It has no owner, no upgrade path, no pause and no fee switch.
  There is no token.
- Every oracle question the registry sends is paid by the claimant (or the sponsor pool) through the Intake; the
  entrant earns nothing from it.
- Sponsor-pool money (mint fees, spec fees, `sponsor`, plain transfers) is an irrevocable donation: no one, the
  entrant included, can withdraw it; it is spent only on members' own catalog traits through the Intake, and a remainder
  below the Intake's price stays in the contract.
- IDMD holders who are list members may draw one catalog chain request per UTC day, nine per token and nine per
  wallet over a lifetime. Every list member likewise has one per day from launch, with no 30-day wait. The two
  paths share the wallet's daily allowance and once-per-trait lifetime usage; token transfers do not reset a
  token's nine-request counter. Each accepted request spends its allowance regardless of the oracle outcome.
  Paid upgrades and shared-fact requests have no pool daily or lifetime limit.
- Spec registration costs 6.4 IMD into the pool; at the 0.5 IMD oracle price, a spec plus its first claim costs
  6.9 IMD, excluding gas. Construction checks IDMD code, the Curator's settlement and the Intake's nonzero
  action/IMD quote by passive view reads, and code at a nonzero executor. Those dependency checks are skipped
  only when all four of Curator, IDMD, IMD and Intake lack code: the pipeline's empty-chain floor. The seven
  nonzero-address checks still apply. A successful floor probe does not establish operational readiness.
  The deployer must verify the configured addresses and helper code; these checks do not guarantee future
  Intake availability or prices, and the Registry has no administrator to repair dependencies.
- After 14 days, a personal pending request may be abandoned only by its stored claimant, including sponsored
  requests; a shared fact may be abandoned by anyone. The price and sponsored allowances are never returned.
  Every oracle question remains about Ethereum mainnet (chainId 1); the consumer domain uses the deployment chain.

- Free claims also attempt the IMD burn rule through BurnExecutor V2
  (`0xe29386719C155B6847aD5a4E97C6674f10ffc750`), using its own waiting IMD. At least 69 IMD and a quote no greater
  than 0.005 ETH requires the claimant to provide the native fee. The executor pays LayerZero and force-refunds
  surplus; paid upgrades are unchanged. A failing executor never blocks a claim solely because a preview or
  bridge reverted: the registry skips it and returns attached ETH. Insufficient fee and a claimant rejecting a
  nonzero registry refund still revert the claimant's transaction, including its oracle request and allowances.
- The preview runs with `PREVIEW_GAS` = 600,000 gas: the executor answers zeros, not a revert, when its inner OFT
  quote runs out of gas, which a measurement on 2026-10-16 placed below about 272,000 gas at the CALL (block
  26,202,500; a cold trace at block 26,202,203 needs 264,408). The earlier 200,000 cap read zeros on mainnet and
  never burned. At the pinned block 26,202,203 the corrected preview returns the real quote and the fork test's
  cold sponsored claim burns through the real executor and OFT. The rule stays best effort: a future quote
  needing more than 600,000 gas or above the 0.005 ETH cap is a skip, and there is no guarantee that every free
  claim burns tokens.
- A claimant should attach exactly the fee quoted by `previewBridge()` in the same block: the executor re-quotes
  when it bridges and keeps the whole attachment if its quote rose; only the part above its own quote comes back.
- Outside the floor (Curator, IMD and Intake all without code), the constructor rejects a nonzero executor address without code
  (`ExecutorHasNoCode()`): the preview's three
  return words are decoded outside the registry's `try`/`catch`, and an executor returning nothing would revert
  every sponsored claim for ever in a registry nobody can repair. A coded executor that returns fewer than three
  words still reverts a claim; that residual is accepted rather than adding a low-level call.
- The registry's eighth argument is fixed ordinary storage; zero still disables the burn rule at contract level,
  but both launch sets use nonzero executors. Sepolia uses V1 `0x097A19e0f021BBA5072701132625ad2401043A2E`, whose
  reverting preview skips with code 1; the launch manifest rejects zero. The executor's owner can change its token, OFT, destination, options and minimum, and can rescue funds. The OFT and
  LayerZero have configuration authorities too. These are owner-configurable external dependencies, not registry
  administration. They may call the claimant; the registry retains its reentrancy guard and makes no promise
  that all dependency callbacks are impossible.
- A successful `BurnTriggered` records an Ethereum bridge submission. **The Base burn is asynchronous** and still
  depends on message delivery and the configured receiver. Operators must monitor dependency configuration and
  eventual delivery/burns. The fork tests exercise the source-chain send and refunds, not Base execution.

## Limits of this deployment (from the One Dollar Audit of 2026-10-21)

**2026-10-21: the registry deployed on 2026-10-20 (launch #2341, `DEPLOYMENTS.md`) stays as it is.** It has no owner, no
setter and no upgrade path. The One Dollar Audit of its Registry (job 1042: 3 high, 3 medium, 7 low, 5 informational;
report and the disposition of every finding in `audits/2026-10-21-onedollaraudit-1042.md`) found no way for a third party
to take funds or to write a false fact. Its three highs are limits the entrant chose and wrote down before the launch;
in plain words:

- **"Armed" (601) means held an IDMD seat at the mint block, borrowed or not (F-1).** The seat snapshot is taken once,
  in `mintCard`; the IDMD collection keeps no holding history, so a seat passed from wallet to wallet lights 601 on each
  card it visits (one card per wallet, 0.1 IMD plus gas each). A contract that gates on 601 gates on "had access to a
  seat when minting", nothing more.
- **A Curator member can spend the pool on a fact that is false, once a day (F-2, F-4).** A sponsored request that ends
  without a verified trait gives its trait reservation back, and only verified traits count toward the lifetime limit of
  nine; one draw per wallet per UTC day, at most an eighth of the pool and 2 IMD each, bounds it. The pool is made of
  mint fees, registrations and donations, never of user deposits; it holds 0.1 IMD on 2026-10-21, below the size at
  which any draw is possible at the 0.5 IMD price. Donate to the pool knowing that members, not the donor, decide what
  it pays for.
- **A shared fact's pending request can be released only by the wallet that paid for it, 31 days later (F-3).** If the
  Intake never completed a request, the fact id would stay blocked until that payer calls `abandon`. The Intake
  completes every request (a verdict or a failure, both clear the pair), and the entrant requested the catalog's one
  shared fact (1201) from its own wallet on 2026-10-21 (stored at block 26,237,440: 32 addresses), so the stored answer
  closes the request path for good. A community
  T3 spec keeps this limit for its own fact.

Also from this audit: one fixed attester key signs every oracle fact and the panel numbers are its own (F-6; the
registry checks the quorum it was built with, issue #20); an attestation issued long after its request can still be
valid after an `abandon`, in which case it lands as `Missed` and the fee is spent (F-7). The next-cut list is at the end
of the disposition file; no next cut is planned.

**From the One Dollar Audit of the Composer (job 1043, 2026-10-21; `audits/2026-10-21-onedollaraudit-1043.md`):** the
registration guard does not check that a community spec's `arg` (kinds 1 and 2), `fixedArg` or `sumArg` names a real,
indexed parameter of its event (H-1). A spec that names a data field or a non-existent one registers for 6.4 IMD and
can never be answered: every request about it is paid to the Intake and ends without a verdict. Before registering a
community trait on this deployment, check that `arg` and `fixedArg` are `indexed` parameters of the event and `sumArg`
one of its parameters; no community spec is registered on 2026-10-21. The same guard admits prose inside an event
signature, which the composed question repeats to the oracle's panel (M-2); the next deployment refuses both. The
Composer's views trust the addresses they are given (M-3) and `compose` trusts its spec (M-1): the registry passes only
its pinned addresses and stored, validated specs; a direct caller of the Composer harms only its own call.

**From the One Dollar Audit of the Renderer (job 1044, 2026-10-21; `audits/2026-10-21-onedollaraudit-1044.md`):** the
Renderer holds no funds and no state. Its `tokenURIOf(registry, tokenId)` renders whatever registry the caller names:
called with a registry of someone's own making it returns a well-formed card with "verified" language for invented
facts (M-3). A card image or metadata is a rendering, never a credential; the credential is `hasTrait(wallet, id)` on
the Registry at `0xdd0017e4…5edb`, and a metadata document proves nothing unless it was read through that Registry's
own `tokenURI`. A registry that does not encode `specOf` as this one does can make a direct `tokenURIOf` call run out of
gas or print bytes from the renderer's own memory (M-1), which harms only that call. A claimant's `tokenURI` would
become unreadable after about 124,000 verified community specs (M-2), which would cost that claimant about 62,000 IMD
in oracle fees at today's price. The next deployment adds bounds checks, a family check and the single quote to the
escaped set.

## Known issues of the test deployment (2026-10-18, from the One Dollar Audit of 2026-10-19)

**This section describes the test deployment of 2026-10-18 (Registry `0x39bec7648259d5a128c29b24951eabcd4d1f95a6`, swarm
launch #2147, never announced), replaced on 2026-10-20.** The items below were fixed in the live registry (`docs/V2.md`
items 1 to 27, `audits/2026-10-18-swarm-launch-audit-c3792acf.md`) and stay facts of the test registry, which has no
owner, setter or upgrade path. Addresses and provenance: `DEPLOYMENTS.md`; the full report, the swarm's launch audit and
the disposition of every finding: `audits/`.

- **A sponsor-pool claim pays whatever the Intake quotes, with no cap (H-1, issue #6).** `claimSponsored` and
  `upgradeSponsored` take no `maxPrice`; if the Intake's price rose to the pool's size, one routine claim would spend
  the whole sponsor pool. Before a pool claim, compare `priceOf` with `pool()`; the site shows both and warns when the
  price exceeds an eighth of the pool.
- **Trait 601 "Armed" is a live read, not a fact at mint (M-2, issue #8).** It reflects whether the minting wallet
  holds an IDMD seat at the moment of reading; every other direct trait reads the settled Curator. Selling the seat
  turns 601 off without a `MetadataUpdate`, and one seat can light it on any number of wallets in turn.
- **The card transfers, its facts do not (M-3, issue #9).** Traits are facts about the wallet that minted the card
  (`claimantOf`); a buyer receives the picture, never the facts, and only the minting wallet can add traits to it.
  The rendered card does not say so yet.
- **A shared-fact request can be abandoned by anyone after 14 days (M-4, issue #10)** while the oracle may deliver for
  30. A late but valid answer is then lost and nothing is refunded.
- **`tokenURI` of a fully decorated card can cost about 19M gas (M-5, issue #11)**, above the `eth_call` gas cap of
  several public RPCs. Read it over an RPC with a high call-gas limit, or use the site's build-time render.
- **`NoVerdict` is Intake-attributed (L-5, issue #15).** The failure callback carries a signature the registry never
  verifies, so a failure status says what the Intake relayed, not what the attester signed.

Also known: a claim whose caller forwards too little gas skips the IMD burn silently, without an event (M-1, issue #7);
community spec ids are sequential and end for good after 55,534 registrations (L-7 and the launch audit, issue #16);
read a new spec's id from `SpecRegistered` and check `specOf` before paying for it.

## Audits

The reviews of this code and the disposition of every finding are in `audits/README.md`. The One Dollar Audit of the
live Registry (2026-10-21, job 1042: 3 high, 3 medium, 7 low) is `audits/2026-10-21-onedollaraudit-1042.md`; the one of
the test deployment's Registry (2026-10-19, job 1033: 1 high, 5 medium, 7 low) is `audits/2026-10-19-onedollaraudit-1033.md`,
whose accepted fixes are in the live registry (`docs/V2.md`). The audits of the Composer and the Renderer (jobs 1043,
1044) follow when they complete.
