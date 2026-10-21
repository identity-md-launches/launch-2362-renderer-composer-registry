# CONCEPT.md: what the registry is and how it works

The product is **Sworn** (collection symbol `SWORN`, named 2026-10-16). These pages say *the registry* and *the
card*; the per-wallet facts are *traits*. Family display names are the final names of `CATALOG.md` section 7:
Spawned, Zero-Shot, Hopper, Bullfrog, Benchmarked, Armed, Uptime, Holdout, Final Token, Hotfix, PID, Top Weights,
Pretrained.

## 1. In one paragraph

A registry of verifiable onchain feats, each backed by evidence anyone can rerun: a fact read straight from a
settled, immutable contract, or a chain-evidence verdict attested by the IMD swarm through the onchain Intake.
One transferable ERC-721 card per wallet; traits are facts about the wallet that minted the card, never about the
holder. The first catalog is built on THE LIST, the `WhitelistCurator` game on Ethereum mainnet (19,522 wallets
that paid real gas, hour after hour, in a quiet market; settled in hour 66). Any contract can read
`hasTrait(wallet, traitId)` with no card and no token; which traits a mint, an airdrop or a grant should trust is
the consumer's policy, not the registry's.

What it is not: not an eligibility list, not a sybil verdict, not a token.

## 2. Four evidence classes, printed on every card

| class | how the fact is established | cost to the claimant |
|---|---|---|
| **direct read** | the registry calls a view of the settled Curator (or IDMD `balanceOf`) when rendering or when asked | gas only; no transaction at all for `hasTrait` |
| **chain-proven** | an IMD oracle question with `evidence: chain`, one of the deployer's recipes, rerun by the deployer before it is signed; the attestation is verified in the registry's callback | the Intake's price (0.5 IMD on 2026-10-12) + gas |
| **panel-attested** | an IMD oracle question with `evidence: panel`: a pinned RPC read every member repeats | the same price + gas |
| **shared fact** | one chain-proven question whose answer serves many wallets (the Top Weights list, 1201) | paid once by whoever asks first |

## 3. One card per wallet: claimant and holder

Mirrors the THE LIST record NFT (`reference/list-record/`):

- `tokenOf(wallet)` is the wallet's card (0 = none). `claimantOf(tokenId)` is the wallet that minted it and never
  changes. `mintedAtBlock(tokenId)` is immutable. `ownerOf(tokenId)` is the holder and may differ after a sale.
- **Direct-read traits are computed live** in `tokenURI` and `hasTrait` from the Curator's views and IDMD
  `balanceOf`. No per-trait action, no storage, no oracle. Families 1 to 5 read the settled Curator and never change;
  the Armed trait (601, working name Operator) reads live IDMD ownership and changes when an IDMD moves. It is a live fact, not a
  historical one, and the card says so.
- **Oracle traits are stored per `(claimant, traitId)`** once an attestation is verified in the callback:
  `verified[claimant][traitId] = (bytes32 requestId, bytes32 oracleRequestId, uint64 fromBlock, uint64 toBlock)`
  (the README's `verified()` returns exactly this tuple; `requestId` is the Intake's id, `oracleRequestId` the plane's
  signed id, see `INTEGRATION.md` section 4). They never change and never move with the card.
- `hasTrait(wallet, traitId)` is the credential: the direct-read rule evaluated live, or a `verified` entry. **It
  needs no card.** The card is the display and the collectible; the registry is the credential.
- One card per claimant; no re-mint after a sale, so a sold card keeps its claimant and the facts stay queryable.
- `_update` emits ERC-4906 `MetadataUpdate` on transfers; every verified upgrade emits it too, so marketplaces
  refresh the card as traits arrive.
- First line of the integration guide: a card proves facts about the **claimant**, never about the holder.
  Allowlists read `hasTrait`, never `ownerOf`.

## 4. Flows

**Mint the card.** `mintCard()`: one transaction by the claimant, 0.1 IMD into the registry (the claimant has
approved the registry; IMD has no `permit`). The card appears with every direct-read trait the wallet qualifies for.

**Upgrade with oracle traits.** `upgrade(uint16[] traitIds, uint256 maxPrice)`: one transaction, k Intake requests,
k x `priceOf` (reverts when `priceOf > maxPrice`). For each trait the registry composes the body from the trait's
template (`TEMPLATES.md`) with `msg.sender` as the claimant and itself as the `consumer` on the deployment
chain (`consumer.chainId = block.chainid`); the question's `chainId` remains 1, Ethereum mainnet. It computes the plane's
`questionHash` of that body (`INTEGRATION.md` section 4, check 7), stores
`pending[requestId] = (claimant, traitId, requestedAt, questionHash)` plus the reverse index
`pendingOf[claimant][traitId] = requestId`, and calls `Intake.requestWithFailure` with `onResult` and `onFailure` as
the two callbacks. Minutes later the writer calls `Intake.complete`, which calls `onResult` (a result) or `onFailure`
(a refusal or a panel without a verdict); the registry verifies (`INTEGRATION.md` section 4), writes
`verified[claimant][traitId]`, clears the pending pair, and emits `MetadataUpdate(tokenOf[claimant])` only if the
claimant has a card (id 0 is never emitted). Every other outcome clears the pending pair and stores nothing (the
transition table in `INTEGRATION.md` section 4b); the price is spent either way, and the claimant may request the
trait again. After `14 days` (`block.timestamp` since `requestedAt`) only the stored claimant may call
`abandon(requestId)` to clear a personal pair the plane never completed; a stranger gets `NotClaimant()`.
Anyone may abandon a shared fact, whose claimant is zero. Abandoning returns no price and restores no sponsored
allowance; a late valid answer can still settle a request left pending. At most one pending request per `(claimant, traitId)`; duplicate ids in one `upgrade`
call revert; an already verified trait cannot be requested again. A wallet without a card may upgrade too (the traits
attach to the claimant; the card renders them when minted). `composeBody(traitId, claimant)` is a public view that
returns the exact body and its `questionHash`, so a front end or a third party can preview and quote a request for
free before paying.

**Register a spec.** `registerSpec(Spec)` by anyone, 6.4 IMD into the registry; guards in `CATALOG.md` section 5; emits
`SpecRegistered(id, registrant)`. From then on `upgrade` accepts the new id for every wallet, paid by the claimant.
At the 0.5 IMD oracle price, registration plus the first claim costs 6.9 IMD, excluding gas.

**Shared facts.** `requestSharedFact(factId, maxPrice)` by anyone for any T3 id (1201 or a registered T3 spec), one
price, no claimant; at most one pending request per fact id, and refused once the fact is stored. The callback checks
the answer's canonical `address[]` envelope (`INTEGRATION.md` check 8) and stores only
`sharedFact[factId] = (requestId, keccak256(a.answer), n)`: thirty-two fresh storage slots would cost about 700,000
gas, far above the Intake's 200,000-gas stipend, and a malformed envelope must not poison the fact forever (it is a
miss; the fact can be requested again). `applySharedFact(factId, address[] calldata list)` recomputes
`keccak256(abi.encode(list))`, compares it with the stored hash, and marks
`verified[msg.sender][factId] = (sharedRequestId, oracleRequestId, window)` if `list[0..min(head, n))` contains
`msg.sender`; gas only; once per claimant and fact. The list is public: it is in the `complete` transaction's calldata
and in the attestation the plane serves at `/oracle/requests/<oracleRequestId>/attestation`, so anyone can supply it.

**Sponsor pool.** The pool is the registry's IMD balance (`pool()`), fed by mint fees, spec fees, `sponsor(amount)`
and any plain transfer. It is spent only on the **catalog's chain traits** (701, 801, 901, 1001, 1101 to 1105), only
for the caller's own wallet, and only once per `(wallet, traitId)` ever (`poolUsed`), whatever the outcome:

- `upgradeSponsored(idmdTokenId, traitIds[])`: the holder of IDMD `idmdTokenId` (checked by `ownerOf`) must also be
  a list member (`firstHourOf(msg.sender).hasJoined`). Exactly one catalog chain id per call; **nine requests per
  IDMD token over its lifetime**, tracked by `idmdSponsored` even across transfers; reverts if the pool cannot
  cover `priceOf`.
- `claimSponsored(traitId)`: from launch, with no 30-day wait, any Curator member (`firstHourOf(msg.sender)
  .hasJoined`) draws one pool-funded request for one catalog chain trait of their own; reverts when `poolUsed`, when
  the trait is verified or pending, or when the pool is below `priceOf`.

Both paths share **one pool-funded request per wallet per UTC day**, computed as `block.timestamp / 1 days` and
stored in the public `uint64 lastPoolDay(wallet)`. The zero default is unused on the launch chain in 2026. A request
for another trait on the same day reverts `PoolDailyLimit(wallet)`; switching paths or IDMD tokens cannot bypass it.
The once-per-pair rule across nine eligible ids means **nine per wallet over its lifetime**, across both paths.
Empty sponsored arrays revert `NoTraits`, arrays longer than one revert `TooManyTraits`, and the tenth IDMD-funded
request reverts `IdmdSponsorExhausted(tokenId)`. A transaction that reverts rolls back every allowance; an accepted
request consumes them even if the eventual callback fails or the request is abandoned. Paid `upgrade` and
`requestSharedFact` neither consume nor check these limits.

**Burn on a free claim.** Both pool entry points are payable. After the existing checks and oracle request,
`previewBridge()` reads BurnExecutor V2's whole bridgeable balance with a 600,000-gas cap (`PREVIEW_GAS`: the
executor answers zeros instead of reverting when its inner OFT quote runs out of gas, which happens below about
272,000 gas at the CALL on 2026-10-16, block 26,202,500; a cold trace at block 26,202,203 needs 264,408; the cap is
2.2 times that). At least 69 IMD and a quote at most 0.005 ETH requires the caller to attach the quote
(`BurnFeeRequired(nativeFee)` otherwise). The registry calls `bridgeToBaseBurnReceiver(amount, msg.sender)` with
all attached ETH and an 800,000 CALL gas argument (2,300 stipend on top for nonzero value). The executor re-quotes,
pays the fee and returns the surplus over its own quote (a call first, a forced send if the claimant rejects it);
a claimant should attach exactly the fee quoted in the same block, since the executor keeps the whole attachment if
its quote rose. This uses IMD already held by the executor, not an extra charge against the pool or claimant.

Reverting preview (skip code 1), reverting bridge (2), quote above cap (3), amount below 69 IMD, or an unset
executor all let the oracle request proceed. The registry returns `msg.value` on a skip, with a plain call only
for a nonzero amount and with success required; it never returns it a second time after executor success.
Insufficient fee or a rejected nonzero registry refund rolls the transaction back. A nonpayable contract claimant
can therefore send nothing when no burn is due or the exact fee when it is, and can receive a forced surplus
refund from a successful executor. Its rejection of a registry refund still reverts its own claim.

At the pinned mainnet block 26,202,203 the corrected preview returns the executor's real quote and the fork test's
cold sponsored claim burns through the real executor and OFT. The rule stays best effort and promises no future
liveness: a quote needing more than `PREVIEW_GAS` or above the fee cap, or an executor/bridge revert, is a skip
that does not block the oracle request. Outside the all-four-empty dependency floor, the constructor rejects a nonzero executor without code
(`ExecutorHasNoCode()`), because a preview that returns nothing cannot be decoded and would revert every sponsored
claim for ever; a coded executor returning fewer than three words still reverts a claim (residual).
`BurnTriggered` records a bridge submission; the Base burn is asynchronous. The registry's executor address is
fixed, but the executor, OFT and destination configuration remain dependencies controlled by their respective
owners; those dependencies may call the claimant. `INTEGRATION.md` section 5b describes operation and monitoring.

Community specs, panel traits and shared facts are never paid by the pool; a claimant pays for those. **This is the
economic policy, stated:** the pool is an irrevocable donation that any member may draw once per catalog trait for
themselves. Draining it needs member wallets and mainnet gas for every 0.5 IMD burnt (at most nine requests per
member), there is no recipient other than the Intake, and a remainder below the price stays in the contract. Nothing
in the registry can withdraw or migrate pool money; a successor contract starts its own pool.

## 5. Rendering

- One card image, the **hive symbol** (2026-10-16; README "The card image"): thirteen hexagonal cells, one per
  family, lit in the family's class colour, part-filled with honey up to the tier reached, ringed by the first 39
  community specs, dotted white at a rare top tier, framed by a ring that a path circles as the community count
  grows. Polygons, clip paths, one circle per rare tier, one path and one text element only; the whole renderer
  inside the EIP-170 limit; a second renderer only if it ever needs it.
- The JSON envelope and every coordinate string of the image are **compile-time constants** in the renderer's
  bytecode (`bytes constant`; solc emits a `codecopy`),
  not a constructor argument and not a deploy-dependent immutable. **Do not copy the vendored renderer's mechanism:**
  `ListRecordRenderer` takes the blob as a constructor argument, writes it to an SSTORE2 pointer and keeps that
  address in an immutable, which is exactly what the launch check forbids; mirror only its splice loop and its
  golden-test method. Reason: the launch pipeline accepts only static constructor arguments, and
  the deployed runtime code must equal a clean rebuild of the reviewed source (`foundry.toml` sets
  `bytecode_hash = "none"`). Constants and ordinary storage only.
- System monospace font stack, no web fonts, no `<image>`, no external URLs (marketplace sandboxes block them).
- The card draws the 13 families, not the 25 ids: the tier reached shows as the honey level and the rare top tiers
  as a dot. Community traits (ids 10001 and up) are drawn only as a count (rings up to 39, the path beyond) and are
  never named in the image; the JSON `attributes` list the claimant's verified community ids from
  `verifiedSpecsOf(claimant)`, **at most the
  first 32**, each with its spec name, plus a `community_count` attribute with the full count, so metadata stays bounded whatever a claimant
  buys; `verifiedSpecsOf` returns every id. Only the claimant can add to that index (`upgrade` and `applySharedFact`
  act for `msg.sender`; the pool never funds community traits), and an id is appended once (a second verification of
  the same pair is impossible: a verified trait cannot be requested or applied again).
- `tokenURI` returns `data:application/json;base64,...` with the SVG percent-encoded inside, built from the
  envelope by splicing per-card values at fixed offsets; the image value is assembled from precomputed,
  pre-encoded strings selected by index (no trigonometry onchain). The generator in `tools/` is the normative
  drawing and produces the envelope blob, the offsets, the hive data and the goldens, and the golden tests prove
  the Solidity output byte-exact (see the vendored `Renderer.t.sol` and `Template.t.sol` for the method).
- Every oracle trait's metadata carries its template, parameters, pinned window, `minPanelSize`, `minQuorum` (acceptance minima; signed values are in the served attestation), the Intake
  `requestId` and the plane's `oracleRequestId`, so a third party can rerun the recipe against public RPCs or fetch the
  served attestation without trusting the registry or the swarm.
- The card prints the Curator author's caveat: "this list is not sybil-resistant by design; filter offchain".

## 6. Contracts

Three contracts: `Registry`, `Renderer` and `Composer`; the registry's constructor takes eight arguments.

| contract | role | constructor |
|---|---|---|
| `Registry` (`ERC721("Sworn", "SWORN")`) | ERC-721 + IERC4906; catalog table; `mintCard`, `upgrade`, `hasTrait`; Intake consumer (`onResult`, `onFailure`); specs; shared facts; sponsor pool | eight static addresses `(curator, idmd, imd, intake, attester, renderer, composer, burnExecutor)` stored in storage (no `immutable`); the renderer and the composer are deployed first and passed in as static addresses (the registry creates no contract: with both helpers embedded its init code exceeded EIP-3860, see README "What was built, and where it deviates from the brief"); records `deployedAt = block.timestamp`; zero `burnExecutor` disables the rule and is exempt from the zero-address check; outside the all-four-empty dependency floor, requires IDMD code, `curator.isSettled()` true, `intake.priceOf(ACTION, imd)` nonzero and code at a nonzero executor |
| `Renderer` | template `bytes constant` + offsets as constants + splice + Base64 | none |
| `Composer` | the five templates, body and canonical-document serialisers, catalog specs, spec guards, name table, catalog enumeration and direct-read predicates; views only, never called inside `onResult` | none |
| interfaces | `IWhitelistCurator` (in `src/interfaces/`), `IIntake` (v2: `requestWithFailure`), `IOracleConsumer` (`onResult`, `onFailure`), `IBurnExecutor` (`tokenBalance`, `previewBridge`, `bridgeToBaseBurnReceiver`) | |

The constructor skips dependency checks only when **all four of Curator, IDMD, IMD and Intake lack code**.
This is the pipeline's empty-chain floor: no external constructor calls, including no executor call or code check.
If any of the four has code, all checks run; a missing IDMD reverts `DependencyHasNoCode()`. The seven nonzero-address
checks always apply. The factory probe deploys Renderer, Composer and Registry in order, but operational launch
still requires the deployer to verify every address and both helpers. `deployForChain()` uses the Sepolia set on
11155111 (including its nonzero V1 executor, whose preview reverts and skips with code 1); every other chain uses
the mainnet constants. The launch manifest rejects a zero executor. Parameters are in `INTEGRATION.md` section 1.

Ownerless, no upgrade, no pause, no fee switch, no `receive`, no `fallback`, no `immutable`, no `tx.origin`. Solidity
0.8.24, Foundry, OpenZeppelin from `lib/` (ERC721, ECDSA.tryRecover, MessageHashUtils, ReentrancyGuard; **not** the
`EIP712` base, which holds immutables: the domain separator is computed at verification time, `INTEGRATION.md`
section 4). `hasTrait(wallet, unknownId)` returns false, never reverts; `hasTrait(address(0), id)` returns false
(OpenZeppelin's `balanceOf(0)` reverts, so guard it). The registry's own events use names the Intake does not
(`TraitRequested`, not `Requested`).

### Invariants (every one gets a test: unit, fuzz or invariant; fork tests against the mainnet Curator)

1. `tokenOf(c) != 0` implies `claimantOf(tokenOf(c)) == c`; transfers never change `tokenOf`, `claimantOf`,
   `mintedAtBlock` or any `verified` entry.
2. At most one card per claimant. `mintCard` twice reverts.
3. A `verified[c][t]` entry exists only after an attestation that passed every check in `INTEGRATION.md` section 4
   and whose pending record named exactly `(c, t)` with the `questionHash` of the body the registry composed for
   `(c, t)`, or, for any T3 id, after `applySharedFact` matched the stored hash and found `c` within `head`.
   `hasTrait(c, t)` equals the live rule for direct-read traits and the `verified` entry for oracle traits, card or no
   card.
4. An attestation is consumed once: one pending request is consumed once (its first callback clears it, and any later
   callback for that request id is reason 1 and touches nothing). The same signed evidence is not tied to one request:
   it may satisfy another pending request whose canonical question is identical (same `questionHash`, which binds
   the claimant, the trait and the window), because the registry checks the question, not the attestation's identity.
   A wrong signer, wrong `verifyingContract`, wrong `chainId`, wrong `questionHash`,
   wrong answer type, malformed answer bytes, wrong window, insufficient quorum, expiry or a failing rule never marks
   a trait and never reverts the callback for an envelope that decodes (no unchecked `abi.decode`); each records a
   `Missed` event with its reason code. An attestation signed for another consumer or another chain is never
   accepted, whatever else it says.
5. `onResult` and `onFailure` from any sender but the Intake are rejected; `onResult` fits in the Intake's callback
   gas stipend (measured in a gas test at 200,000 with margin, worst case: cold storage, a community id appended, a
   card to refresh).
6. Tiers are monotone: `hasTrait(c, 303)` implies `hasTrait(c, 302)` and `hasTrait(c, 301)`; `hasTrait(c, 202)`
   implies `hasTrait(c, 201)`; likewise 4xx and 5xx. The PID family (11xx, working name Ordinal) is not a tier family.
7. A registered spec never changes; the body sent to the Intake is a deterministic function of the spec and the
   claimant (golden tests per template against `templates/fixtures/`), and the registry's
   `questionHashOf(canonicalDocument)`, which takes the canonical document of `INTEGRATION.md` section 4, check 7,
   not the body, equals the plane's value for every fixture (`reference/plane/questionHashes.json`); registration fees stay in the
   registry.
8. `tokenURI` is pure over the registry's storage, the Curator's views and IDMD `balanceOf`; the renderer output
   decodes to the golden bytes; a hostile spec name cannot break the JSON or the SVG (escaping tests).
9. The registry's IMD balance never decreases except through `requestWithFailure` on `claimSponsored` or
   `upgradeSponsored`; a claimant-paid request leaves the balance unchanged; `abandon` releases a pending pair only
   after 14 days, by its claimant for personal requests or anyone for a shared fact; both pool paths open at launch, only for list members, once per wallet per UTC day and once per
   pair ever (nine per wallet); `upgradeSponsored` requires IDMD ownership, exactly one trait per call and at most
   nine requests per IDMD token over its lifetime; the pool funds only the nine catalog chain traits, never a panel, shared or community
   trait; one pending request per pair and per fact id; `sharedFact` holds a hash and a length, never a list.
10. Curator-derived direct-read traits (families 1 to 5) for a non-member are all false (`firstHourOf` returns
    `(0, false)`): a non-member never renders as an hour-0 Zero-Shot. 601 is independent of membership.
11. Any address can call `hasTrait` and `tokenURI` for any wallet; no function depends on `tx.origin`.

12. After each accepted free claim the registry's ETH balance equals its balance before. Only `msg.value` can be
    forwarded or refunded; pre-existing ETH is not a precondition and cannot be spent. Unsolicited ETH during a
    call is outside this invariant. Failed bridge attempts preserve the oracle request and return all attached
    ETH if the caller accepts the refund; successful attempts leave refunds to the executor.

Harness discipline (not a product invariant): invariant handlers guard expected reverts (a second `mintCard`, a
duplicate pending pair), because `fail_on_revert = true` is kept.

## 7. Launch

Through the IMD launch pipeline, kind `evm_contracts`, Ethereum mainnet: one transaction, static constructor
arguments, no token. The pipeline runs audit, adapt, re-audit; the adapt step may change code, so the deployed
runtime code is compared with a clean rebuild of the reviewed commit before any address is published, and the
artifacts' `immutableReferences` are checked to be empty first (a non-empty table means the comparison can never
pass).
