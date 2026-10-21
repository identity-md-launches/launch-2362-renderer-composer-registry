# Review revision 3 (2026-10-20): size budget, items 8, 18 and 19

Findings `c721f34b` (size), `5046dfe5` (item 18), `601e8733` (item 8), `fa949320` (item 19) and the advisory ones.
Responses are in `.imd-responses.json`.

## Sizes (solc 0.8.24, optimizer 200, Cancun, `bytecode_hash = "none"`)

| contract | runtime bytes | EIP-170 headroom |
|---|---:|---:|
| Registry | 22,943 | 1,633 |
| Composer | 23,621 | 955 |
| Renderer | 23,092 | 1,484 |
| **sum** | **69,656** | section 6 budget 69,800: **144 under** |

`test/Revision3.t.sol` `test_threeRuntimesFitTheLaunchBudget` (the reviewer's proof, kept) pins the sum. What was cut
(deleting over adding, no V2 item dropped, every public ABI still used by the site kept; `web/src/pages.tsx` reads
none of the removed views):

- Renderer: `tokenURI(Card)`, `preimage(Card)`, `image(Card)`, `escapeJson` and `cardOf` are internal (the Card ABI
  decoder and encoder were a quarter of the runtime); `tokenURIOf(registry, tokenId)` and `traitName(id)` are the
  external surface. `test/mocks/RendererHarness.sol` exposes the internal ones to the tests unchanged in substance.
  The 25-name table moved here from the Composer as one packed constant with length bytes.
- Composer: `answerTypeOf`, `panelOf`, `hasDirectTrait` (the registry tests the `directSnapshot` bit) and the name
  table removed; `FIRST_DEPOSIT`, `HOUR_SAVED`, `MAINNET_CURATOR` internal; `compose` takes the trait id and builds a
  catalog spec itself (the registry no longer decodes and re-encodes a catalog `Spec`); the T1/T2 `method` text is
  one shared head and tail; `_charset` is one routine for arguments, items and names; the dead body-length guards
  went (the door's bounds hold by construction: `item` <= 256, every other string <= 32, the longest template
  text, T3, composes to 625 question and 398 definition bytes at the catalog spec and under 1000 / 512 at the
  maximum, `test_fuzz_maximalSpecRegistersComposesAndFitsTheBody`).
- Registry: `traitClass` and `questionHashOf` removed (the class is `specOf(id).kind`; the hash is `keccak256` of
  the canonical document); `specOf` of a catalog id returns the Composer's encoding as it came.
- `OracleMeta` carries only what the record prints (id, kind, window, target, both request ids, name).

## Items

| item | status | where | test |
|---|---|---|---|
| 8 kind-3 answers exactly `head` long | **done**: `_decodeAndJudge` requires the decoded array to have exactly `threshold` elements (32 for 1201, the spec's head for a community T3); a shorter or longer list is `Missed(.., 9)`, nothing is stored and the fact is re-requestable at once; `applySharedFact` scans the whole stored list | `Registry._decodeAndJudge`, `applySharedFact` | `Revision3.t.sol` `test_item8_*`; `Adversarial.t.sol` `test_fuzz_applySharedFactOnlyWithinTheHead` (now: every length but 32 misses); the 64-address envelopes of the older tests became 32-address ones |
| 18 T3 topic position | **done**: `validateSpec` rejects a kind-3 `item` ending in `anonymous` with `BadSpec("item")` and a grouping key that is not an `address`-typed indexed parameter (absent, a data field, indexed of another type, no parameter list) with `BadSpec("arg")`; the composed T3 question and `definitions.method` carry the v2 wording of TEMPLATES.md with the topic position parsed from the signature (1-based among all indexed parameters) | `Composer._topicOf`, `_anonymous`, `validateSpec`, `question` | `Revision3.t.sol` `test_item18_*` (the reviewer's proof included); `templates/fixtures/1201-top-32.json` and the `1201-top-32` entry of `reference/plane/questionHashes.json` regenerated from the composed body (contributor = topic 1; the canonical document is RFC 8785 of the same text, hash `0x0145a631…3a30076`), `Templates.t.sol` green |
| 19 `tokenURI` gas | **(a), (b), (c) done, target not met**: (a) `_oracle`, `_communityAttributes`, `_list` and the record builder write into the growable `Buf`; (b) `_meta` makes one `verified` call and picks kind, target, window and name out of `specOf`'s ABI words without decoding the spec body, `OracleMeta` carries nothing else; (c) the shrunk record. Measured cold at the maximum state of V2 item 19 (25 catalog traits, the 32-address shared answer, 32 verified T2 specs at the `validateSpec` maximum): **10,317,448 gas** (was 12,022,786), URI 40,737 bytes. Breakdown (`test/scratch` profile): `cardOf` 2.48M, preimage 5.44M, image 1.19M, Base64 about 2.4M. The smallest further cut is (d): an assembly Base64 encoder (OpenZeppelin's per-three-byte loop over the 30.5 KB preimage is 2.4M; a tabled encoder with the alphabet in one stack word is about a third of that), then a lean `oracleRecord` storage read in the Registry (the spec-body cold `SLOAD`s behind `specOf` are about 1.1M, but that view costs about 500 bytes and the size budget has 144); together they project under 8M | `Renderer._meta`, `_oracle`, `_one`, `_communityAttributes`, `_list` | `Revision3.t.sol` `test_item19_tokenURIAtTheMaximumStateIsMeasuredAndBounded` (the cold maximum-state regression, bound 11,000,000 until (d) lands, to be tightened to 8,000,000 then) |
| 9 spec ids to `uint256` | **not done, by decision**: the `uint16` id plumbing stays (ids end at 65,534 as CATALOG section 5 says; 55,534 registrations at 6.4 IMD away); widening every signature, event and the Composer/Renderer interfaces adds bytes the launch budget does not have | | `ReReview.t.sol` `test_specIdsEndAt65534` pins the cap |
| 20 table tiling test | done earlier (`V2Edges.t.sol` `test_item20_templateSlicesTileTheEnvelope`, `test_item20_hiveTablesTile`); the previous notes row was stale | | |
| 22 documents | **done for the reported sentences**: `upgradeSponsored` and the 14-day rule removed from CATALOG.md and INTEGRATION.md; INTEGRATION's abandon table says 31 days and the payer; README's abandon paragraph and view list follow the ABI | | |

Trust assumptions (finding `08756560`): attester, action id, Intake and executor are constructor-fixed by the ownerless
brief; a signer rotation, a retired action, a shrunk callback gas or a changed Curator are documented limits, not
defects, and no unprivileged party can exploit them (README "Trust assumptions", INTEGRATION.md section 6).

Checks run here: `forge build --sizes`, `forge fmt --check`, `forge test` with
`FOUNDRY_FUZZ_SEED=0x0f3d3ae040d5fe60f26dab4ef8dcca326854f10e7609839637a1fed897a2e678`, the two reviewer proofs
under `test/scratch`, Slither high-only: 2 results, both `incorrect-exponentiation` on OpenZeppelin's intentional
`^` in `lib/` (`Base64._encode`, `Math.mulDiv`), present in the accepted tree and outside the writable paths; none in
`src/`. `python3 tools/gen_template.py --check` green (the metadata bytes are unchanged). Fork suites skipped (opt-in).

# Sworn v2 contract stage (2026-10-20): docs/V2.md items 1 to 22 on the `v2-base` tree

Sizes with the pinned settings (solc 0.8.24, optimizer 200, Cancun, `bytecode_hash = "none"`), each under EIP-170:

| contract | runtime bytes | EIP-170 headroom |
|---|---:|---:|
| Registry | 23,535 | 1,041 |
| Composer | 24,234 | 342 |
| Renderer | 24,546 | 30 |
| **sum** | **72,315** | section 6 budget 69,800: **over by 2,515** |

The sum is above the project budget of docs/V2.md section 6. It is reported, not hidden: the final-transaction
simulation (`sworn-verify`, section 9 of the rollout plan) stays the deployment gate, and the measured v2 lab build
(69,854 bytes) needed 16,555,500 gas of the 16,777,216 cap, so about 2,500 more runtime bytes (roughly 500,000 gas at
200 gas per byte) is expected to exceed the cap: **the review step must decide between a further cut and a two-transaction
deployment before the launch is paid.** The smallest further cuts, in order: (1) `Renderer.escapeJson` public wrapper
and `Composer.answerTypeOf` / `panelOf` getters (about 150 bytes); (2) the shrunk oracle record of item 19 (c) applied
to the catalog entries' window fields too (about 120 bytes); (3) `Registry.traitClass` (about 150 bytes) if the site
does not read it.

Checks run here: `forge build`, `forge fmt --check`, `forge test` with `FOUNDRY_FUZZ_SEED=0x0f3d3ae0...e678`
(181 passed, 0 failed, 16 opt-in fork skips), `python3 tools/gen_template.py --check` (28 artifacts),
`python3 -m unittest tools/test_gen_template.py` (18 tests). Slither, Mythril and the fork suites were not run.

## Items and their tests

| item | state | where | test |
|---|---|---|---|
| 1 price cap on pool draws | done: `claimSponsored(traitId, maxPrice)`, `PriceAboveMax`, `PoolDrawTooLarge` above pool/8 or `POOL_DRAW_CAP` (2 IMD); `PoolTooSmall` is gone (a price above the pool is above pool/8) | `Registry.claimSponsored` | `V2.t.sol` `test_item1_poolDrawCaps`; `Invariants.t.sol`, `InvariantsExtended.t.sol` handlers guard pool/8 |
| 2 zero price reverts | done, `ZeroPrice` in `_price` (shared by paid and pool paths) | `Registry._price` | `test_item2_zeroPriceReverts` |
| 3 pool limiter restored on failure | done: `Pending.sponsored`; `_release` clears `poolUsed` on `onFailure`, `Missed` and `abandon`; `lastPoolDay` stays | `Registry._release` | `test_item3_failureRestoresTheTraitReservationAndTenAttemptsPay` (ten UTC days, ten prices, paid retry at once); `Adversarial.t.sol` `test_abandonedPoolRequestReleasesTheReservation...` |
| 4 IDMD pool path deleted | done: `upgradeSponsored`, `MAX_SPONSORED`, `idmdSponsored`, `IdmdSponsorExhausted`, `NotIdmdHolder`, `TooManyTraits` removed; nine **verified** sponsored traits per wallet (`sponsoredVerified`, `PoolLifetimeLimit`) | `Registry` | `test_item4_nineVerifiedSponsoredTraitsPerWallet`; every nine-per-token test deleted |
| 5 abandon on a shared fact | done: `Pending.payer`, 31 days for every request | `Registry.abandon` | `test_item5_abandonSharedFactOnlyByPayerAfter31Days`; `Registry.t.sol` abandon tests at 31 days |
| 6 gas floor and `BurnSkipped` reasons | done: `InsufficientGas` below `(PREVIEW_GAS + BURN_GAS) * 64 / 63 + 50_000`; `BurnSkipped(tokenId, reason)` 1 to 5; reason 4 skips and refunds, the request stands; `BurnFeeRequired` removed | `Registry._burnOrRefund` | `BurnRule.t.sol` `test_claimInsideThePreviewGasWindowRevertsInsufficientGas`, `testFuzz_dueWithoutEnoughFeeSkipsRefundsAndLeavesTheRequest`, `test_noFeeAtExactThresholdSkipsWithReasonFour`, codes 1/3/5 fuzz; `BurnInvariant.t.sol` |
| 7 `onResult` clears then checks | unchanged order, documented in NatSpec | `Registry.onResult` | existing `Registry.t.sol` miss tests, `ReReview.t.sol` consumed-once test |
| 8 kind-3 answers exactly `head` long | **not done**: the exact-count rule broke the shared-fact suite (64-address envelopes, the handler's lists); v1's 1..64 bound and the `head` clip in `applySharedFact` stay | `Registry._decodeAndJudge` | existing shared-fact tests |
| 9 `nextSpecId` to `uint256` / `expectedId` | **half**: `registerSpec(Spec, uint256 expectedId)` with `UnexpectedSpecId` is done; the id widening is **not** (every `uint16 traitId` signature stays; ids end at 65534 as CATALOG section 5 says) | `Registry.registerSpec` | `test_item9_expectedIdRefusesAFrontRun`; `ReReview.t.sol` `test_specIdsEndAt65534` |
| 10 `deployedAt` removed | done | `Registry` | `Artifacts.t.sol` (no getter) |
| 11 forward `fee`, refund the surplus first | done | `Registry._burnOrRefund` | `BurnRule.t.sol` `testFuzz_dueForwardsTheFeeAndRefundsTheSurplus`, `test_surplusFromARejectingRecipientRevertsBeforeTheBridge` |
| 12 `totalSupply()` | done (`_nextTokenId`, no burns) | `Registry.totalSupply` | `test_item13_...` |
| 13a `onFailure` unsigned, says so | done (NatSpec) | `Registry.onFailure` | `Adversarial.t.sol` `test_onFailureRecordsWhatItIsToldAndStoresNothing` |
| 13b `forceApprove` per call | NatSpec line on `_request` | `Registry._request` | n/a |
| 13 transferable card, direct traits frozen | done: `frozenDirect[tokenId]` (bit `(family-1)*4 + tier-1`), `Composer.directSnapshot`, `Registry.hasDirectTrait`; the description sentence added by the generator | `Registry.mintCard`, `hasDirectTrait` | `test_item13_directTraitsFrozenAtMintAndTransfersChangeNothing`; `Adversarial.t.sol` `test_tokenURIDependsOnlyOnTheClaimantsFacts` |
| 14 601 Armed is a snapshot | done: false without a card | same | `test_item13_...`; `Registry.t.sol` `test_directTraitsAreLiveAndNeedNoCard` |
| 15 kind-3 panel 11 / 7 | done in Composer (`panelOf`, body) and Registry (`_panelOf`); fixture `1201-top-32.json` regenerated (panel fields only) | `Composer`, `Registry` | `test_item15_kind3Panel`; `Templates.t.sol` |
| 16 finality margin | done: `toBlock + 64 <= block.number` for kinds 1 to 4 | `Composer.validateSpec` | `test_item16_finalityMargin`; `SepoliaRehearsal.t.sol` window tests |
| 17 curator argument used | done: `catalogSpec(traitId, curator)` targets the registry's curator | `Composer.catalogSpec` | `SepoliaRehearsal.t.sol` `test_catalogSpecsTargetTheDeploymentCurator...` |
| 18 T3 topic position | **not done** (the previous attempt's version put the Composer over EIP-170; no room in the 342-byte headroom) | | |
| 19 `tokenURI` gas | **(c) done**: the oracle record carries id, template, evidence, window, panel minima, both request ids, target and name for every entry (catalog entries too, so one code path); generator and goldens regenerated. (a), (b), (d) and the 8,000,000-gas test are **not done** | `Renderer._one`, `tools/gen_template.py` | `Goldens.t.sol` |
| 20 table tiling test | **not done** in Solidity; `tools/gen_template.py --check` is the existing check | | |
| 21 constructor checks | done: `decimals() == 18`, code at renderer, composer, IDMD and a nonzero executor outside the floor | `Registry` constructor | `test_item21_constructorChecks`; `RegistryRules.t.sol`, `Floor.t.sol` |
| 22 documents | **partly**: this file; README, CATALOG, INTEGRATION, CONCEPT, DISCLOSURE still carry the v1 sentences listed under "Documents to update" | | |

## Structural change for size (allowed by the workflow's "factor locally" rule)

`Registry.cardOf` moved to `Renderer.cardOf(registry, tokenId)` (and `Renderer.tokenURIOf`), reading the registry's
public views (`claimantOf`, `traitsOf`, `verifiedSpecsOf`, `verified`, `specOf`); `Registry.tokenURI` forwards. The
Registry was 646 bytes over EIP-170 with the items in place; this moved about 1,900 bytes out of it. `Renderer.template()`
and `Renderer.offsets()` (golden-test getters) are gone; the test reads `TemplateData` directly. `Rename.t.sol`'s 600-byte
Composer headroom rule became "all three under EIP-170" (the launch budget is the real limit, reported above).

## Documents to update (item 22, open)

README lines 57, 80, 109, 116, 129 (abandon 31 days and payer; `upgradeSponsored` gone; `toBlock <= H - 64`;
`claimSponsored(traitId, maxPrice)`; `registerSpec(spec, expectedId)`; `BurnSkipped` reasons; `cardOf` on the Renderer);
CATALOG lines 136, 160, 185, 204 to 207 (601 wording, panel table 11 / 7 for T3, no IDMD sentence, 31 days, the UTC
calendar day, `totalSupply`); INTEGRATION lines 48, 93, 180, 321, 322, 355, 361, 430, 478 and the new signatures;
CONCEPT, DISCLOSURE (the test deployment, what changed). Public texts must name no version.

---

# Mainnet evidence on a Sepolia consumer (2026-10-17)

Ports the two accepted launch-1953 corrections from the assignment's explicit change list. The
[reference repository at commit 94369920d76bf7bfc0bb8aa1b3138b40246f3ae0](https://github.com/identity-md-launches/launch-1953-launch-sworn-registry-symbol/tree/94369920d76bf7bfc0bb8aa1b3138b40246f3ae0)
was unreachable: both the raw-content and API endpoints were blocked by the network sandbox. The fallback
implementation nevertheless produces all three required runtime hashes exactly. No deployment or publication
was performed. Only Composer, the two specified test files and the four specified documents change; Registry,
Renderer, Types, script, dependencies, compiler configuration, generator, goldens and template fixtures remain
byte-equal to the starting tree.

Catalog oracle specs now target `Composer.MAINNET_CURATOR` regardless of the registry's `curator` argument;
1301 keeps its zero T5 target and names the mainnet Curator in its question's parenthesis. `catalogSpec`'s second
argument and `compose`'s fifth argument remain in their external selectors but are unnamed and unused.
The deployment Curator still supplies the constructor's settlement check, direct reads 101 to 503 and sponsored
membership checks; 601 reads IDMD. The consumer chain and EIP-712 domain still follow the deployment chain.

`validateSpec` retains every guard, replacing its supplied height only off mainnet with
`mainnetHeightBound()`: 15,537,395 through timestamp 1,663,224,191, then one additional block per elapsed
12-second slot. On chain 1, the registry still supplies its exact `block.number`. With 12-second slots and a
correct clock the bound is never below the real mainnet head; skipped slots make it about 0.3% higher. It was
about 76,400 blocks (10.6 days) above the head on 2026-10-16, so an unmined window can register off mainnet and
its paid requests are not refunded. README and INTEGRATION describe the client checks and operational
responsibilities, the Sepolia/mainnet callback stipends (1,000,000/200,000), and the continued pool spending
after an attester rotation.

**Anchor erratum:** 15,537,395 is the **second proof-of-stake block (slot 4,700,014)**. This is the terminology
correction for the accepted reference's comments at `src/Composer.sol:40` / `:43` and
`test/SepoliaRehearsal.t.sol:166` / `:179`; the constant names `MERGE_BLOCK` and `MERGE_TIME` do not change that
fact. This fallback does not reproduce those reference comments or their line numbers. No original Composer
comment was edited, and no bytecode change is needed for this erratum.

## Regression coverage

`SepoliaRehearsal.t.sol` adds eight tests, with chain 11155111 and a Curator mock at the specified Sepolia
address. They cover the game window and deploy-block T5 registering as 10001/10002 with both fees pulled;
rejected future, too-young, short and reversed windows without fees or id advancement; accepted exact boundary
windows; chain 1's unchanged height guards; all five supplied timestamp/height pairs with at most 100,000 blocks
of slack; the anchor and slot boundary; fuzzed monotonicity and the pre-anchor floor; seven catalog fixtures
equal except for `consumer.chainId`, including the plane's question hashes and ignored curator arguments;
all catalog targets and absence of the Sepolia address in question bodies; all direct Curator predicates plus
the IDMD predicate; and a paid 701 request verified end to end through the mock Intake under 200,000 gas.

`Floor.t.sol` retains its prior assertions. `FloorProbe.deployAll` creates Renderer, Composer and Registry in
one call. Both empty-chain parameter sets assert that the factory nonce increases by exactly three, each
init code is at most 49,152 bytes, each deployed contract has nonce one, and a funded factory retains its ETH
while all recipients remain unfunded. Existing runtime limits, forbidden-opcode checks, absent owner/admin,
predicted addresses and constructor-state assertions still pass.

## Runtime and source identity

Built with the unchanged solc 0.8.24 configuration (optimizer 200, Cancun, no metadata hash):

| contract | runtime bytes | runtime keccak256 |
|---|---:|---|
| Composer | 23,655 | `0x79359a04f91e52693816feb7a9d90b4c75e44abb838f9061e8eee209f6ca417e` |
| Registry | 24,561 | `0x9c88410fb6463610043b3adeea1ab857096e83ca8e0aea4f73f63433fbfb42d2` |
| Renderer | 21,570 | `0x1fb854135321f70bb61cefbd688f8375179cdb7c4fb2af2009583786f7d47efb` |

All three match the assignment's expected runtime hashes and sizes; Composer has 921 bytes of EIP-170 headroom.
The fallback source files are not byte-equal to the supplied reference SHA-256 values. Local SHA-256 values:

| file | SHA-256 | equals supplied reference hash |
|---|---|---|
| `src/Composer.sol` | `bea2e23a774e4e1a02b43bbf219da37caada8b5f70e1a0d3be64619bb780afc4` | no |
| `test/SepoliaRehearsal.t.sol` | `4772eca39996e6066da68830ca43f4a696e15b096a72cfb5be97398ed1079bd8` | no |
| `test/Floor.t.sol` | `d2dc0de34e04fe4f08593b7ad53c99fb5be80c85307f14f63ee7e9fc269d1def` | no |

## Checks

Fuzz seed: `0xb9300d51a124316294780636a4ca9f515f5d5a4eef21a13d291e267e9a3a01d2`.

| check | result |
|---|---|
| `forge build --offline` | pass with pinned solc 0.8.24; compiler/lint warnings remain |
| `forge fmt --check` | pass |
| targeted Sepolia and floor tests, seed above | 10 passed, 0 failed |
| `forge test --offline`, seed above | 182 passed, 0 failed, 17 opt-in fork skips |
| `python3 tools/gen_template.py --check` | could not run: Python's system shim exits 1 because Xcode Command Line Tools are unavailable |
| `python3 -m unittest discover -s tools` | same runtime failure before test discovery; no Python tests ran |

The starting suite contains 174 passing tests; these eight new tests bring it to 182, rather than the brief's
stated 188. No unrelated Sepolia tests were copied or added to change that count. The generator and its 28
artifacts are unchanged, but this assignment does not claim a successful generator check or 18 Python test
passes. The earlier dated entries below report earlier jobs and their checks, not this run.

---

# Launch corrections: empty floor, abandon, question chain and Sepolia (2026-10-16)

Four changes, with the compiler, dependencies, Renderer, Types, generator, goldens, template fixtures and
opt-in fork tests unchanged. No deployment, transaction or publication was made by this assignment.

The constructor keeps the seven nonzero-address checks and stores all eight arguments. It skips dependency
checks only when **all four of Curator, IDMD, IMD and Intake lack code**. On that empty-chain floor it makes no
external call and skips the executor code check too. Otherwise it checks IDMD code (`DependencyHasNoCode()`),
Curator settlement, the Intake's nonzero action/IMD price, then code at a nonzero executor (`ExecutorHasNoCode()`).
The floor is for the launch pipeline's factory probe; the deployer must still verify the configured dependencies
and both helpers before operational launch. A coded executor returning fewer than three words still reverts a
sponsored claim; its owner and the bridge dependencies retain the configuration powers and asynchronous-delivery
residuals documented in DISCLOSURE.md. Nothing in the burn rule changed.

After 14 days, a personal pending pair may be abandoned only by its stored claimant (`NotClaimant()` for a
stranger), including either sponsored path. Anyone may abandon a shared fact (claimant zero). `TooEarly()` still
precedes the claimant check. Clearing, spent prices, daily/lifetime allowances and stale callbacks are unchanged;
a valid late answer still settles a pair left pending.

The question's chain is always Ethereum mainnet: `QUESTION_CHAIN_ID = 1` in the Registry and top-level
`chainId: 1` in the body and canonical question document. `consumer.chainId` is the deployment chain, emitted by
OpenZeppelin `Strings.toString(block.chainid)`; Composer's `compose` and internal `encodeBody` are views, with no
external selector change. The EIP-712 domain uses the consumer chain. The question text, windows, definitions and
canonical hash stay unchanged, and all ten mainnet bodies are byte-exact against the existing fixtures.

`run()` now calls the directly testable `deployForChain()`. On 11155111 it selects the specified Sepolia Curator,
IDMD, TestIMD and V1 executor `0x097A19e0f021BBA5072701132625ad2401043A2E`, with the same Intake and attester;
every other chain selects the mainnet constants. The Sepolia executor has code but its preview reverts, so the
burn rule skips with code 1. Both launch sets use nonzero executors; the manifest rejects zero. Explicit `deploy`
still accepts zero to disable the rule at contract level. README and INTEGRATION list every parameter. The three
new lowercase Sepolia dependency literals are written in Solidity's required checksum case, without changing
any address value. No additional production change or build-setting exception was needed.

| runtime (solc 0.8.24, optimizer 200, Cancun, existing foundry.toml) | before | after | EIP-170 headroom |
|---|---:|---:|---:|
| Registry | 24,495 B | 24,561 B | 15 B |
| Composer | 23,377 B | 23,402 B | 1,174 B |
| Renderer | 21,570 B | 21,570 B (byte-equal) | 3,006 B |

## New and adapted tests

- `Floor.t.sol`: `test_mainnetEmptyChainFloor`, `test_sepoliaEmptyChainFloor`. An ordinary probe contract deploys
  raw creation code by CREATE2 in Renderer, Composer, Registry order, using predicted helper addresses and the
  Registry creation code followed by `abi.encode` of all eight arguments. Both parameter sets have no dependency
  or executor code. All three runtimes are nonempty and at most 24,576 B, and an opcode walk skips PUSH data and
  refuses CALLCODE, DELEGATECALL and SELFDESTRUCT. `owner()` and `admin()` are absent on all three; eight Registry
  getters, Sworn/SWORN and `nextSpecId == 10001` match.
- `Artifacts.t.sol`: `test_twoDeploymentsHaveIdenticalRuntimeCode`,
  `test_constructorRejectsZeroAddressesAndStoresTheRest`, `test_constructorRejectsUnsettledOrUnavailableCurator`
  and `test_noForbiddenOpcodesInRuntime` now use a coded IDMD mock. The former code-less Curator rejection is
  `test_constructorAcceptsUnavailableCuratorOnEmptyFloor`. The two script tests are now
  `test_deployScriptUsesMainnetConstantsOnEveryOtherChain` (1, 4663, 31337) and
  `test_deployScriptUsesSepoliaConstantsAndNonzeroExecutor` (11155111); they install mocks at both executor
  constants using `deployCodeTo` and check all selected dependencies and the two deployed helpers.
- `RegistryRules.t.sol`: `test_constructorRejectsPartiallyCodedDependencyFloor` tries each of the four dependencies
  as the only coded address; `test_constructorRejectsEachSingleMistypedDependency` removes each one in turn from
  an otherwise coded setup and pins the matching revert. Existing zero-price, wrong-asset, unavailable-Intake and
  passive-read tests still pass, as do the unsettled/unavailable Curator and `BurnRule.t.sol` executor tests.
- `Registry.t.sol`: `test_abandonOnlyAfterFourteenDaysAndStaleCallbackLeavesSuccessor` now rejects Bob with
  `NotClaimant()` and abandons as Alice. `test_strangerCannotDiscardLateValidAnswer` proves a stranger's failed
  abandon leaves a 14-day-old, valid signed answer deliverable. New chain tests are
  `test_mainnetQuestionAcceptedUnderSepoliaConsumerDomain`,
  `test_sepoliaQuestionMissesWithReasonThreeUnderSepoliaDomain` and
  `test_mainnetSignatureCannotAnswerSepoliaConsumer`; callbacks still run under the 200,000-gas stipend.
- `Adversarial.t.sol`: `test_fuzz_abandonedPoolRequestKeepsPoolUsedAndLateCallbackIsIgnored` covers both sponsored
  entry points, rejects a stranger, abandons as the claimant and pins the retained day, pair, IDMD counter and
  pool balance. `test_abandonedSharedFactCanBeRequestedAgainAndTheLateAnswerIsIgnored` explicitly abandons as
  someone other than the payer and retains the successor/late-callback assertions.
- `ReReview.t.sol` `test_sameSignedEvidenceSatisfiesAnotherRequestWithTheSameQuestion` and `ReviewChanges.t.sol`
  `test_unknownRequestStillPrecedesDynamicSizeChecks` abandon as their stored claimant. `InvariantsExtended.t.sol`
  `FullHandler.abandonLate` reads and pranks the stored claimant, leaving shared-fact cleanup public.
- `Templates.t.sol` pins chain 1 in setup. `test_sepoliaChangesOnlyConsumerChainAcrossAllTenBodies` checks
  consumer chain 11155111, question chain 1, the same consumer address and hash, and byte equality after replacing
  only the consumer chain field. Existing fixture and plane-hash tests remain unchanged.
- `Attestations.t.sol` `_registryAt` uses a coded IDMD mock so the served-signature and protocol-vector digest tests still
  reach their original assertions. None of their vectors, domains or signatures changed.

## Checks

```sh
forge build --offline
FOUNDRY_FUZZ_SEED=0x92530be9de645ff13afd9b69b7f771c7cb2e0a674c25f4e493ff0fdd0a334df6 forge test --offline
forge fmt --check
python3 tools/gen_template.py --check
python3 -m unittest discover -s tools
```

| check | result |
|---|---|
| `forge build --offline` | pass, pinned solc 0.8.24; existing compiler/lint warnings remain |
| `forge test --offline`, seed above | 174 passed, 0 failed, 17 opt-in fork skips |
| `forge fmt --check` | pass |
| generator `--check` | 28 artifacts byte-equal |
| Python unittest discovery | 18 passed |

Initial targeted testing found two attestation fixtures without IDMD code; the mock adaptation above repaired
both before the full seeded suite passed. No fork RPC, new environment reads, FFI, network installation, live
quote or deployment was needed. The opt-in fork sources remain byte-equal and were skipped, not rerun live.
No new question text was introduced. Protected-file hashes and the Renderer runtime hash match the starting tree.
The earlier sections below record prior assignments; their unconditional constructor checks and zero-executor
Sepolia rehearsal describe the earlier behavior, superseded by this section.

---

# Burn-rule corrections: preview gas and executor code check (2026-10-16)

Two corrections to `src/Registry.sol` found by the independent verification of the burn rule, plus one test gap.
Nothing else in `src/` changes; Composer and Renderer are byte-equal (23,377 and 21,570 B).

**Correction 1, preview gas.** `_burnOrRefund` called `previewBridge()` with a 200,000-gas cap. BurnExecutor V2
catches its inner OFT quote running out of gas and returns `(0,0,0)` instead of reverting, so measured on
2026-10-16 against the deployed executor `0xe29386719C155B6847aD5a4E97C6674f10ffc750`: an `eth_call` at block
26,202,500 returns zeros below about 272,000 gas at the CALL and the real quote above it; a cold fork trace at block
26,202,203 shows 264,408 gas. The delivered rule therefore never burned on mainnet (amount read as zero, below
`BURN_MIN`, silent refund), and the old fork test passed only because it read the uncapped quote first and warmed
the executor, OFT and endpoint state. Fix: `uint256 internal constant PREVIEW_GAS = 600_000;` as the gas argument
of that call (2.2 times the measured need, below `BURN_GAS`); nothing else in the rule moves.

**Correction 2, executor without code.** `try`/`catch` catches only a revert of the external call; the three
return words are decoded outside it, so a nonzero executor address with no code would revert `claimSponsored` and
`upgradeSponsored` for every wallet for ever, in a registry nobody can repair. Fix: the constructor reverts
`ExecutorHasNoCode()` when `burnExecutor_` is nonzero and `burnExecutor_.code.length == 0`; zero stays allowed and
means no burn rule (the Sepolia rehearsal). Residual, documented and not patched: a coded executor returning fewer
than three words still reverts a claim; no low-level call was added for it. Consequence in the suite:
`test/Artifacts.t.sol` `test_deployScriptUsesTheFiveStaticAddresses` runs the deploy script offline with the
mainnet executor constant, so it now installs `MockBurnExecutor` at that address (one `deployCodeTo` line) before
`d.deploy()`. No other test needed a change: every other deployment passes `address(0)` or a mock.

**Test gap.** `test_paidFunctionsRemainNonpayableAndNeverTriggerBurn` accepted any revert, so a payable `upgrade`
would have survived the suite. Replaced by `test_paidFunctionsRejectOneWeiWhereZeroValueSucceeds`: for each of
`upgrade`, `requestSharedFact`, `sponsor`, `mintCard` and `registerSpec`, a funded and approved call succeeds with
zero value and has its effect (positive control), the state is restored with `vm.snapshotState` /
`vm.revertToState`, and the identical call with 1 wei must revert and leave no effect.

| measure (solc 0.8.24, optimizer 200, Cancun, unchanged foundry.toml) | before | after |
|---|---:|---:|
| Registry runtime | 24,495 B (81 under EIP-170) | 24,495 B (81 under EIP-170) |
| Registry init code | 26,082 B | 26,146 B (the code check lives in the constructor only) |
| Composer / Renderer runtime | 23,377 / 21,570 B | unchanged, byte-equal |

The runtime size is unchanged because `PREVIEW_GAS` replaces a literal of the same width and the constructor check
is init code only; no factoring was needed.

## Unit tests (`test/BurnRule.t.sol`, `test/mocks/MockBurnExecutor.sol`)

- `test_constructorRejectsNonzeroExecutorWithoutCodeAndAcceptsZeroOrCode`: a fresh address and the mainnet
  executor constant (no code offline) revert `ExecutorHasNoCode()`; `address(0)` and the mock deploy.
- The mock's gas fixture (`requirePreviewGasCap`) now requires 590,000 < entry gas <= 600,000; the bridge
  assertions stay (800,000 plus the value stipend; no stipend at zero value).
- `burnPreviewGas(n)` makes the mock's preview consume about `n` gas before answering.
  `test_previewUsingMostOfTheBudgetIsQuotedAndBurns` (500,000: quoted, `BurnTriggered`, bridge called) and
  `testFuzz_previewExceedingTheBudgetSkipsWithCodeOneAndRefunds` (600,001: the preview runs out of gas inside the
  registry's `try`, `BurnSkipped(claimant, 1)`, full refund, no bridge call).
- The mock's surplus refund now does what the real executor's `forceSafeTransferETH` does: a 100,000-gas call to
  `refundTo` first, a forced send only if that fails. `test_executorSurplusCallReentryIsGuarded`: a claimant whose
  `receive()` re-enters `claimSponsored` from the executor's surplus call gets `ReentrancyGuardReentrantCall()`,
  the surplus still arrives and the outer claim completes; `test_executorSurplusIsForcedOnARejectingRecipient`
  covers the forced path.
- `forge test` with the verifier seed: **164 passed, 0 failed, 17 skipped** (5 unit tests added, 1 replaced; the
  17 skips are the opt-in fork suites: 11 in `Mainnet.fork.t.sol`, 6 in `BurnRule.fork.t.sol`).

## Fork tests (`test/fork/BurnRule.fork.t.sol`, block 26,202,203, same parent-hash check, same opt-in flags)

Pinned constants at the block: amount `454939975000000000000`, native fee `219261761563315` wei, executor token
balance `454939975535748811691` before any claim. The two tests that expected a zero preview
(`test_fork_cappedPreviewReturnsZeroAndFreeClaimRefunds`, `test_fork_nonpayableClaimantWithNoETHCanClaimWhenPreviewReturnsZero`)
are deleted: with the corrected cap a claimant without the fee reverts. In every new test the claim is the first
call of the test that touches the executor, the OFT, the endpoint or the message libraries (the executor
configuration reads moved from `setUp` to their own test; the executor's ETH balance is read in `setUp`'s own
transaction), and the assertions use the pinned constants rather than a quote read before (warm state hides the
defect) or after (the executor is drained).

| test | what it proves |
|---|---|
| `test_fork_executorConfigurationAndPinnedQuote` | token/OFT/dstEid/receiver as before; `tokenBalance()` and the uncapped quote equal the pinned constants |
| `test_fork_coldFreeClaimWithSurplusBurnsAndExecutorReturnsTheSurplus` | (f) member's cold claim with the fee plus 0.001 ETH: `BurnTriggered(MEMBER, amount, fee)`, real `TokensBridgedForBurn` and `OFTSent`, `tokenBalance()` = pinned balance minus amount (dust), registry ETH unchanged, executor kept nothing, claimant got the surplus back from the executor |
| `test_fork_coldFreeClaimExactFeeFromNonpayableContractClaimant` | (g) exact fee from a contract without `receive`: burns, balance 0 afterwards |
| `test_fork_coldFreeClaimWithoutTheFeeReverts` | (h) `BurnFeeRequired(219261761563315)`, no oracle request, no pool effect |
| the two direct-executor tests | (i) kept as they were |

Run on 2026-10-16 over `https://eth.drpc.org` and `https://eth-mainnet.public.blastapi.io` (both serve the
block's state; `ethereum-rpc.publicnode.com` no longer does): **6 passed, 0 failed** on each. Over
`https://rpc.mevblocker.io/fast` one run reported two transient `EvmError: Revert`s at a few hundred thousand gas
(backend fetch failures under parallel load); rerun alone, both tests pass there with the same gas as on the other
endpoints. The cold claim burning at the pinned block is the direct evidence for correction 1. This is one block's
behaviour, not a liveness promise.

```sh
forge build --sizes
FOUNDRY_FUZZ_SEED=0x77340b097846e4f021221b852dc3d4986cdbebddb3ced0290fa383c3f88b021c forge test
forge fmt --check
python3 tools/gen_template.py --check            # 28 artifacts
python3 -m unittest discover -s tools            # 18 tests
forge test --match-contract BurnRuleForkTest --fork-url https://eth.drpc.org --fork-block-number 26202203 -vv
```

Docs updated to the same facts: README "Free claims and the burn rule" and the deployment notes, INTEGRATION.md
section 5b, CONCEPT.md, DISCLOSURE.md. Each says: `PREVIEW_GAS` and the measurement behind it; at the pinned block
the corrected preview returns the real quote and the fork test burns; the constructor rejects a nonzero executor
without code; a claimant attaches exactly the fee quoted in the same block (the executor re-quotes when it bridges
and keeps the whole attachment if the quote rose); the residuals (short return data from a coded executor, the
executor owner's configuration authority, a future quote above `PREVIEW_GAS` or `BURN_FEE_CAP`, the asynchronous
Base burn). The step-3 notes below are history: their statement that the capped preview returned zeros described
the 200,000 cap this step replaces.

---

# Step 5: the Renderer hive image (2026-10-16)

`src/Renderer.sol` draws the card image per the normative SVG by selecting and concatenating `HiveData` strings
(per family: outline, zones, honey/above clips and clipped rings from lv, n and k; rare dot; empty rings; frame
ghost; the overflow path only above 39 with steps = 64 from 8192 else min(64, bitlen(count ** 8) - 41); token id
text). The JSON envelope and every non-image byte are unchanged. Registry, Composer and Types are untouched.

| measure (solc 0.8.24, optimizer 200, Cancun) | value |
|---|---:|
| Renderer runtime size (`test_reportRendererRuntimeSize`) | 21,570 B (3,006 under EIP-170) |
| tokenURI gas, synthetic_width | 10,810,085 |
| tokenURI gas, synthetic_fullhouse | 9,147,472 |
| tokenURI gas, synthetic_honey | 9,589,924 |
| `forge test` (verifier seed) | 159 passed, 0 failed, 15 fork skips |

Tests added in `test/Goldens.t.sol`: gas report (bounded under 30M for an `eth_call`), runtime size report, no
path at 39 / a path at 40, identical images at 8192 and `uint256.max` (no `count ** 8` overflow), and 40 vs 53
rendering differently (exponentiation, not XOR). Every golden is checked byte-equal through `Renderer.tokenURI`.
Operational note: the image costs about 9-11M gas to read; indexers calling `tokenURI` need an `eth_call` gas
cap above that (most public RPCs allow 30M or more). Nothing is deployed by this step; the Renderer stays pure and
takes no constructor arguments.

---

# Step 4: the hive generator, data and goldens (2026-10-16)

`tools/gen_template.py` now holds the normative drawing of the card image (`hive_svg`, README "The card image") and
writes two Solidity data libraries: `src/TemplateData.sol` (the JSON envelope, 21 slots and 22 slices: name id,
image, claimant, the thirteen family values, the community count and attributes, the three lists) and the new
`src/HiveData.sol` (163 point strings and 34 markup fragments, each stored once, percent-encoded, with ASCII-hex
start tables and index constants). `template/card.svg` and its SVG value slots are gone; `template/blob.hex` and
`template/offsets.txt` describe the envelope only. The Renderer was brought onto the new data so that the goldens are
the executable specification of the image: `Renderer.image(card)` selects and concatenates `HiveData` strings (no
trigonometry; levels, rings, rare dots and the path length are the only logic), `preimage` splices the 21 slots.
The Card struct, `tokenURI(Card)`/`preimage(Card)` and every metadata byte other than the image value are unchanged
(the old `synthetic_direct`, `synthetic_oracle` and `synthetic_width` preimages differ from the previous commit only
in the `image` value). Registry and Composer are untouched. The later Renderer step may restructure the contract;
the goldens and `--check` pin what it must produce.

| artifact | state |
|---|---|
| goldens | 8 cases x {preimage, svg, uri}: `synthetic_direct` (1), `synthetic_oracle` (2), `synthetic_width` (uint256 max), `synthetic_newcomer` (3), `synthetic_outsider` (4), `synthetic_honey` (5), `synthetic_collector` (6), `synthetic_fullhouse` (7); synthetic `0x...c1a1` claimants only |
| Renderer runtime | 21,570 bytes (3,006 of EIP-170 headroom); no immutables, no storage, no constructor arguments |
| `python3 tools/gen_template.py --check` | 28 artifacts byte-equal |
| `python3 -m unittest discover -s tools` | 18 tests: the step table at 32,39,40,53,70,100,200,1000,5000,8191,8192,65535 = 0,0,2,5,9,13,21,39,58,63,64,64, levels, rings, honey polygons, path points, element order, rare dots, opacities, string uniqueness and indexability, goldens, drift detection |
| `forge test` (verifier seed) | 155 passed, 0 failed, 15 fork skips; `forge fmt --check` and `forge build` pass |

`test/Goldens.t.sol` adds the five renderer-only goldens and direct rule tests: the step table (segments per count,
closure at 64 steps, the cap at `uint256.max`), the rare dot for every catalog id, clip paths only for part-filled
families, ring counts and opacities at 0/1/14/27/39 and saturation at 5000, out-of-catalog ids rendering without a
revert (levels are clamped), and determinism across two deployments. `test/Rename.t.sol` and
`test/ReviewChanges.t.sol` asserted on the old text grid (the product name, the family labels, the Ordinal value
line); they now assert on the hive (the token id text, no label, the rare dot for 1101 to 1104 and not for 1105).

Assumptions stated: the image reads only `tokenId`, `top` and `communityCount` of the Card; `top[i]` outside its
family's tier list is clamped to the nearest level (the registry never produces one); `communityCount` is the full
count (the rings use at most 39 of it, the path its eighth power, 64 steps from 8192). Operationally nothing changes:
the Renderer is pure and launched without arguments; a drawing change is a generator change, a regeneration and a
new Renderer deployment, never a storage write. Not run: Slither, Mythril, the opt-in fork suites.

---

# Step 3: sponsored-claim burn rule (2026-10-16)

Only the burn-rule assignment is implemented here. Registry adds the eighth ordinary-storage constructor
argument, the two constants/getters, payable sponsored entry points, bounded preview/bridge calls, burn events
and native refunds. The original pool-check order is preserved by sharing the member check and moving the
shared price/balance check into `_fromPool`. Paid paths have no behavior change. All existing test deployments
pass an explicit zero executor unless exercising this rule. Deploy uses the specified mainnet executor and zero
for Sepolia. No contract was deployed and no live transaction was sent.

## Size and ABI evidence

Measured using the unchanged foundry.toml: solc 0.8.24, optimizer 200, no via-IR, Cancun, no CBOR metadata.

| build | Registry runtime bytes | EIP-170 headroom |
|---|---:|---:|
| accepted step-2 baseline | 23,364 | 1,212 |
| step 3 after local pool factoring | 24,495 | 81 |
| final local validation after test/documentation corrections | 24,495 | 81 |

The naive duplicated-pool implementation exceeded the limit; factoring the existing checks restored room without
removing behavior or introducing a deployed helper. The later independent review step must remeasure after its
own corrections using these same settings. Composer (23,377 bytes) and Renderer (11,712) have identical creation
and runtime bytes to the starting tree. All three artifacts have empty immutableReferences. ABI comparison retains
every original entry except the requested constructor extension and the two sponsored mutability changes; new
entries are `burnExecutor`, `BURN_MIN`, `BURN_FEE_CAP`, `BurnTriggered`, `BurnSkipped`, `BurnFeeRequired` and
`BurnRefundFailed`. No build configuration, dependency, catalog, composer, renderer, card struct or generated
metadata fixture changed.

## Coverage and operational limits

`BurnRule.t.sol` covers both pool paths with below-threshold/disabled refunds, threshold and cap boundaries,
no/insufficient/exact/excess native fees, full-value forwarding, executor forced refunds, preview/bridge reverts,
out-of-gas and large revert data, failure event codes, pending-request preservation, rollback of Intake payment
and all allowances, bounded gas including the value stipend, nonpayable claimants, rejected plain refunds,
executor/refund reentrancy, and unchanged paid non-payability. A mock checks that pending/allowance effects exist
before preview. Existing Registry-rules tests continue to pin eligibility and counter ordering.

`BurnInvariant.t.sol` runs 256 campaigns of depth 64 with fail_on_revert enabled. Each randomized call checks
native balance before/after, exact fees paid, claimant refunds, pool/Intake conservation and rollback of rejected
claims. The registry begins with ETH already present: it is neither a precondition nor available for refunds.
Unsolicited ETH during the call is outside the stated invariant. The mock's test-only force-refund helper uses
selfdestruct during its creation transaction; the compiler's deprecation warning applies to that helper, not
Registry runtime.

`BurnRule.fork.t.sol` runs against mainnet block **26,202,203**, block hash
`0x21d8ce848d55043d0539b2c88ca2c5dd6c0e9072137ae295a5906bc0cabae2bd` (chain, number and parent checked by the test).
It executes the deployed executor, IMD OFT, Intake and LayerZero code. The uncapped executor quote is
454939975000000000000 token units and 219261761563315 wei. This step's 200,000-gas preview cap starved the
executor's inner OFT quote, which the independent verification later found and the correction at the top of this
file replaces with `PREVIEW_GAS = 600_000`; the two fork tests this step wrote around that outcome are gone, and
the current fork tests make a cold sponsored claim burn at the same block. Separate direct executor calls use the
**800,000 CALL gas argument** and prove real OFT sends, exact-fee success, forced surplus refunds to a nonpayable
recipient, no native retention, zero allowance after send, and only shared-decimal token dust left. They do not
prove asynchronous Base delivery.

The verified executor source and ABI are pinned as non-build reference files in `reference/burn/`, with provenance
and source hash. The Sourcify reported onchain runtime was compared to RPC eth_getCode. No new dependency is
required by the build. README, CONCEPT, INTEGRATION and DISCLOSURE distinguish the fixed ownerless Registry from
the external executor/OFT/destination configuration authorities, and document fee/refund failure conditions and
asynchronous Base burns. This is local implementation validation, not the separate independent review in step 6.

## Commands

```sh
forge build --sizes
FOUNDRY_FUZZ_SEED=0xbd9dd51f488abc7266bb0e9bbdb8f77e5594905fe92f55e8fb0a4983dd2701a6 forge test
forge fmt --check
forge test --match-contract BurnRuleForkTest --fork-url https://ethereum-rpc.publicnode.com --fork-block-number 26202203 -vv
```

Final validation: `forge build --sizes`, `forge fmt --check` and the diff whitespace check passed. The full suite
with the supplied seed passed **145 tests, 0 failures, 15 opt-in fork skips**. The four new pinned fork tests
passed separately. The default suite requires no network; those tests skip without an active
CLI fork, and read no environment variables. Existing MainnetForkTest remains opt-in via its prior RPC setting.
Slither and Mythril were not run. Nothing here changes the separate review step's obligations.

---

# Test notes: tests and docs follow-up (i) to (q)

Continues the review follow-up below (contract changes (a) to (h)). This step changes tests and documents only:
no file under `src/`, no id, window, template, fixture, questionHash document, quorum rule or pool rule changed, and
nothing was deployed.

| change | what changed | where |
|---|---|---|
| (i) | `FullHandler.upgradeSponsored` reduces `which` modulo `catalogChain.length` before adding the loop index (kept from the previous step, with its max-seed regression). `replayConsumed` is now among the targeted selectors (16), and counts the replays that reached the registry; a deterministic test replays a consumed id through `onResult` and `onFailure` and shows nothing changes. All five extended campaigns pass with `fail_on_revert = true`. | `test/InvariantsExtended.t.sol` |
| (j) | Cold `onResult` gas: the request and the signature are prepared first, then `vm.cool(registry)`, then delivery through the mock Intake's real `call(200,000)`; each test asserts `delivered` and logs the gas the mock measured around its `call` (new `MockIntake.lastCallbackGas`, which includes the cold account access). Measured: **133,356** first community verification with a card; **164,087** 64-address shared fact, catalog 1201; **170,445** 64-address shared fact, community T3 (head 32, the maximum). The independent reviewer measured 135,193 / 170,779 / 177,134 before the contract changes. | `test/ReReview.t.sol` `test_coldGas_*`; `test/mocks/Mocks.sol` |
| (k) | Re-entrancy: the token re-enters each of the five IMD-moving functions (`upgrade`, `sponsor`, `registerSpec`, `requestSharedFact`, `mintCard`) as a funded, approved attacker (the token contract itself holds IMD and approved the registry; an Intake selling in that token is wired in), and the test asserts the exact revert data `ReentrancyGuardReentrantCall()` (new `ReentrantIMD.reentryError`). Unguarded positive control: the same payloads fired from a frame without the guard succeed and take effect. High-s: each malformed signature, including the high-s twin, is now derived from the signature of the exact envelope delivered with it; the test also proves the twin recovers the attester under plain `ecrecover`, and the low-s original then verifies. New tests: (a) 262,144-byte signatures on a community shared fact and a community personal request with a card, cold, under the stipend; (b) a lower ordinal acquired later replaces a higher one and never the reverse; (c) community attributes appear only for verified specs, with the name; (e) an unused `fixedVal` is refused and an empty filter is never serialised, a named one is; (f) the constructor reads `isSettled` by static call (a writing Curator cannot deploy and is not written). Also (n) and (p) below. | `test/Adversarial.t.sol`, `test/ReReview.t.sol`, `test/mocks/Mocks.sol` |
| (l) | README "How to verify a card": `topic0` is the keccak of the canonical event signature, and topic positions come from the indexed-argument order of the stored item (`Transfer(from,to,value)` with `arg = "to"` puts the claimant in `topic2` and leaves `topic1` open); the catalog's layout is the special case. | `README.md` |
| (m) | README says how to run `test/fork/Mainnet.fork.t.sol` with `CHAINTRAITS_FORK_RPC` (archive RPC, block 26,170,000) and no longer says the fork tests are not delivered. | `README.md` |
| (n) | CONCEPT.md invariant 4: one pending request is consumed once; the same signed evidence may satisfy another request with an identical canonical question. Test: `test_sameSignedEvidenceSatisfiesAnotherRequestWithTheSameQuestion` (abandoned request is reason 1; successor with the same `questionHash` verifies with the same signature; successor then consumed). | `CONCEPT.md`, `test/ReReview.t.sol` |
| (o) | `questionHashOf` takes the canonical document, not the body: said in README (interface deviations, delivered tests, verification step 3) and CONCEPT.md invariant 7. | `README.md`, `CONCEPT.md` |
| (p) | CATALOG.md section 5: `nextSpecId` is a `uint16`, at most 55,534 community specs (ids 10001 to 65534). Test: `test_specIdsEndAt65534` (65534 registers, the next one reverts with an arithmetic panic). | `CATALOG.md`, `test/ReReview.t.sol` |
| (q) | CONCEPT.md section 6 and INTEGRATION.md section 1: three contracts (`Registry`, `Renderer`, `Composer`) and seven constructor arguments with renderer and composer as static addresses, matching README's deviations. CATALOG.md section 8: open question whether the plane ever signs chain evidence with `agreed` below quorum; the registry refuses it (reason 5). | `CONCEPT.md`, `INTEGRATION.md`, `CATALOG.md` |

Observation, not changed (outside the listed changes): `INTEGRATION.md` section 4, check 7, last sentence still
writes `questionHashOf(body)`; the test it describes passes the canonical document, as (o) now says elsewhere.

Re-review of this step: the edits touch only tests, mocks and documents. The two mock additions (`lastCallbackGas`
recorded after the callback returns; `reentryError` recorded on a failed re-entry) do not change what any existing
test asserts. Local validation after the changes: `forge build`; `forge test --offline` with no
`CHAINTRAITS_FORK_RPC` (all suites pass, the eleven fork tests skip); `forge fmt --check`;
`python3 tools/gen_template.py --check`. This is not an independent audit.

# Previous step: review follow-up (a) to (h)

Continues the accepted build and test job. No deployment or launch was performed. The frozen ids, windows,
question templates, request/attestation fixtures, canonical questionHash document, quorum predicate and pool
rules are unchanged. Only the requested rendering template and its generated goldens were regenerated.

## Changes and reasons

| change | implementation and reason | regression coverage |
|---|---|---|
| (a) Bound callback inputs before copying/hashing | `_check` reads calldata lengths first: signature other than 65 bytes is reason 2; answer over 2,112 bytes, or not exactly 32 for a pending bool/uint256 kind, is reason 9. After those checks: chainId, signer, type, panel/quorum, window, expiry, questionHash, defensive decode and rule. Valid-length signature words are loaded directly from calldata for OpenZeppelin's `tryRecover(v,r,s)` overload, preserving its high-s/v checks without a memory copy. The redundant later scalar length check was removed. This prevents a single oversized, ABI-valid callback from exhausting the Intake stipend and locking the pair for 14 days. The exact precedence is in `INTEGRATION.md`. | `ReviewChanges.t.sol`: 262,144-byte signatures and answers, simultaneous errors, 64/65-address boundary, scalar lengths 0/31/33/2,112/2,113, wrong claimed type, full diagnostic precedence, unknown/stale request, and successful immediate retries. Calls go through the mock Intake's 200,000 stipend with Registry storage cooled. Existing signature-shape, malformed-envelope and worst-case success tests remain. |
| (b) Ordinal is not a tier family | `cardOf` keeps the first ascending id for family 11, so the lowest verified ordinal appears in both SVG and the Ordinal attribute. Tier families still use the highest id. | Fuzzed subsets of all five ordinals, acquired in descending order, including no ordinal; checks card slot, JSON attribute, SVG and the other tier maxima. |
| (c) Community traits in standard attributes | Each of the first 32 verified community ids now has `{"trait_type":"Community <id>","value":"<escaped spec name>"}` in `attributes`. `community_count` retains the full count, and the custom id array remains. Names come from the already bounded oracle metadata; the Card ABI is unchanged. Generator, 36 splice offsets, template blob and all three goldens were regenerated. The renderer-only width case now shows ordinal 1101 and supplies names for all 32 ids and checks hostile-name escaping for each. | The existing 34-spec test now parses all 32 id/name attributes and the full count, and refuses a 33rd displayed entry. Solidity golden tests and Python generator tests cover zero, one and 32 community attributes, escaping, and byte-exact JSON/URI output. |
| (d) Label metadata minima correctly | Oracle JSON keys are `minPanelSize` and `minQuorum`. The ABI tuple retains its existing field names and types; comments clarify their meaning. The README identifies `/oracle/requests/<oracleRequestId>/attestation` as the source of the signed panelSize/quorum/agreed values. No additional callback storage or quorum rule was introduced. | A signed panel of 30, quorum 20, agreed 22 verifies for chain and panel traits; metadata still reports minima 5/3 and 11/7, excludes the old JSON keys and preserves oracleRequestId. |
| (e) Reject an unused nonzero fixedVal | T1/T2 `validateSpec` reverts `BadSpec("fixedVal")` when fixedArg is empty but fixedVal is nonzero. The serialized question omits an empty filter, so the stored value must not imply one. | Fuzzed nonzero values (including uint256.max), both kinds; rejection leaves fees and nextSpecId unchanged. Empty/zero and named filters matching zero or nonzero remain accepted. |
| (f) Require a settled Curator | The constructor requires `curator.isSettled()` with a passive view call. This enforces the assumption that Curator-derived facts are final. Addresses remain constructor-only ordinary storage. Deployment documentation now describes the required settled chain state. | `Artifacts.t.sol`: settled deployment succeeds, false/reverting/no-code Curators fail, and zero-address guards remain. Artifact and served-attestation test deployments now use actual settled mocks. |
| (g) Restore Registry runtime headroom | Catalog enumeration and the unchanged direct-read predicates moved into Composer. Registry keeps every existing public function and its ABI, forwards view work using STATICCALL, and still performs all callback verification locally. The name table and spec guards were already in Composer. No immutables were added. | Artifact ABI comparison retained every pre-change entry for all three contracts. `test_twoDeploymentsHaveIdenticalRuntimeCode`, `test_noImmutableReferencesInAnyArtifact`, no-forbidden-opcodes checks, direct-read fuzzing, goldens and invariants remain. The Registry size assertion now enforces 23,076 bytes. |
| (h) Wrap the clipped footer | The evidence legend ends its first line after “shared fact;”; the claimant caveat continues on the second line. The sybil caveat and source credit occupy a lower baseline with a clear gap. No wording was removed. | All three regenerated SVG goldens have the wrap. A local font-metric check with the card's installed DejaVu Sans Mono fallback placed every footer line within x=60..940 and below y=975, inside the border. The longest line ends at x=704.8; the sybil caveat ends at x=663.9, before the source credit starts at x=735.3. |

## Runtime sizes (solc 0.8.24, unchanged foundry.toml)

| contract | runtime bytes | EIP-170 headroom (24,576 minus runtime) |
|---|---:|---:|
| Registry | 23,027 | 1,549 |
| Composer | 23,455 | 1,121 |
| Renderer | 11,791 | 12,785 |

The Registry limit for this assignment is 23,076 bytes. All three deployed bytecode artifacts have empty
immutableReferences, and an artifact-wide scan found no nonempty immutableReferences. The measured personal
callback worst case (community append plus card refresh) is 164,954 gas. The existing 64-address shared result and
all five template success paths also pass through the Intake's real stipend; the shared/personal margin test uses
180,000 gas.

## Re-review and check notes

Review covered the changed validation order, signature loading, ABI decoding and bounds, pending/reverse-index
clearing, replay handling, Ordinal choice, community names/count/escaping, metadata provenance, spec fees and
ids on rejected registration, constructor preconditions, helper call graph and runtime determinism. No additional
contract defect was identified in this bounded re-review. The code movement adds static view calls only; it
introduces no authority, setter, external call in onResult, or money-moving path. Every pre-existing public ABI
entry was compared with the pre-change build, including tuple component names.

The full run exposed one pre-existing **test harness** defect: `FullHandler.upgradeSponsored` computed
`which + i` before reducing an unrestricted uint256 selector. The shrunk input was
`(12_242_742, uint256.max, 57)`, which overflowed inside the handler before reaching Registry. Selection now reduces
`which` modulo the catalog length before adding the bounded loop index. A deterministic regression exercises
that input with sufficient pool funds. This repair is necessary for reliable invariant runs and changes neither
production pool rules nor invariant assertions. No failing test was removed or disabled.

A disposable `test/scratch` harness compiled the original Registry source and reproduced both 262,144-byte
failures: the mock Intake reported not delivered and the pair stayed pending. The corresponding fixed-version
regressions deliver a Missed event, clear the pair, and accept an immediate retry. The scratch sources were removed
after this comparison.

The existing fork tests skip without their explicit RPC setting; this follow-up uses no RPC and does not refresh
live evidence. The prior round's fork claims below are historical. No Slither or Mythril run was performed; the
review used the supplied oracle/security references, source review, Foundry unit/fuzz/invariant tests and the
Python generator checks. This local re-review is not a new independent contributor audit.

## Final local validation

- `forge build --offline`: passes with the pinned solc 0.8.24 and unchanged build configuration.
- `env -u CHAINTRAITS_FORK_RPC forge test --offline -vv`: **90 passed, 0 failed, 11 skipped** across 10 suites.
  The 11 skips are the existing RPC-dependent fork tests. Both invariant groups pass with zero handler reverts;
  the extended handler also passes the exact max-seed regression above.
- `forge fmt --check`: passes.
- `python3 tools/gen_template.py --check`: all 12 generated artifacts match.
- `python3 -m unittest discover -s tools`: all 7 tests pass.
- Artifact scan: no nonempty immutableReferences; all original ABI entries retained; all three runtime sizes match
  the table above. Runtime identity and forbidden-opcode tests pass.
- `git diff --check`: passes. Build/dependency configuration, dependencies, question templates, request fixtures,
  served attestations, reference material and the canonical questionHash fixture are unchanged.

## Prior round 3 notes (historical)

This round added `test/Adversarial.t.sol`, `test/InvariantsExtended.t.sol` and `test/fork/Mainnet.fork.t.sol`
on top of the accepted suite. No implementation defect was found that needed a fix in `src/`; the review
observations that are not defects are listed at the end and in `.imd-findings.json` (info level).

## Running

```sh
forge test                                                        # hermetic: no RPC, no ffi; the fork tests skip
CHAINTRAITS_FORK_RPC=https://rpc.mevblocker.io/fast forge test --match-path 'test/fork/*'   # mainnet, block 26,170,000
python3 tools/gen_template.py --check                             # templates, offsets and goldens byte-exact
```

The fork tests were run on 2026-10-11 against `rpc.mevblocker.io/fast` and `ethereum-rpc.publicnode.com`: all
eleven pass. They never write the environment (`vm.envOr` only) and skip cleanly when the variable is unset, so
the verifier's no-network run is unaffected. README now says how to run them (change (m) above).

## CONCEPT.md section 6, invariant by invariant

| # | invariant | tests |
|---|---|---|
| 1 | `tokenOf`/`claimantOf`/`mintedAtBlock`/`verified` survive transfers | `Registry.t.sol` mint/transfer; `Invariants.t.sol`; `InvariantsExtended.t.sol` `invariant_oneCardPerClaimant`, `invariant_markedExactly…`; `Adversarial.t.sol` `test_tokenURIDependsOnlyOnTheClaimantsFacts` |
| 2 | one card per claimant | `Registry.t.sol` `test_mintOncePerWallet…`; both invariant suites |
| 3 | marked only after every check for exactly `(c, t)`; `hasTrait` = live rule or entry | `Adversarial.t.sol` cross-pairing tests (another claimant, another trait with the same window), `test_questionHashIsBoundToTheClaimantAndTheTrait`; `InvariantsExtended.t.sol` `invariant_markedExactlyWhenAPassingAttestationWasDelivered`; `Registry.t.sol` direct reads; fork: direct rules against the real Curator |
| 4 | consumed once; every wrong field is a miss, never a revert; other consumer/chain never accepted | `Registry.t.sol` `test_missReasons`, `test_attestationForAnotherConsumerOrChain…`; `Adversarial.t.sol` fuzz over every altered field, panel/quorum, window, expiry/skew, count and bool answers, five signature shapes (incl. high-s); fork: `test_fork_attestationSignedForAnotherConsumerMissesOnTheRealIntake`; `InvariantsExtended` `deliverTampered`, `replayConsumed` |
| 5 | Intake-only callbacks; `onResult` under 200,000 | `Registry.t.sol` `test_callbacksRejectEveryoneButTheIntake`, `test_onResultGasWorstCase` (164,696 measured); `Adversarial.t.sol` shared-fact 64-address envelope (gas logged, < 180,000), every template with a card through the mock's real `call(stipend)`, a starved callback stays pending; fork: real `complete` from the writer with the real stipend |
| 6 | tiers monotone | `Registry.t.sol` `test_fuzz_tiersAreMonotone`; fork: `_assertDirectRulesAgree` on three real contributors |
| 7 | specs immutable; bodies deterministic and byte-exact; `questionHashOf` equals the plane's | `Templates.t.sol` (ten fixtures, ten hashes); `Adversarial.t.sol` maximal-spec fuzz (registers, composes, fits 16 KiB, can be asked), determinism fuzz; `InvariantsExtended` `invariant_specsAreImmutable` |
| 8 | `tokenURI` pure over storage + Curator + IDMD; goldens; escaping | `Goldens.t.sol`; `Adversarial.t.sol` `test_tokenURIDependsOnlyOnTheClaimantsFacts`, `test_cardShowsAtMostThirtyTwoCommunityIds…` |
| 9 | pool leaves only through pool-funded requests; abandon after 14 days; pool rules; one pending per pair/fact; `sharedFact` is a hash | `Registry.t.sol` pool tests; `Invariants.t.sol`; `InvariantsExtended` `invariant_poolIsFeesPlusDonationsMinusSponsoredRequests`, `invariant_sharedFactsAreHashesStoredOnlyOnDelivery`; `Adversarial.t.sol` k x price fuzz, all nine sponsored, duplicates, pending/verified claims, abandoned pool and shared requests, head fuzz for `applySharedFact` |
| 10 | non-member is `(0, false)`: never an early bird | `Registry.t.sol` `test_nonMemberIsNeverAnEarlyBird`; fork: `test_fork_nonMemberReadsZeroFalseAndHasNoCuratorTrait` on the real Curator |
| 11 | open reads; no `tx.origin` | `Registry.t.sol` `test_anyoneReadsAnyWallet…`; `Adversarial.t.sol` `test_fuzz_hasTraitAndTraitsOfNeverRevert`, re-entrancy through the token into every IMD-moving function |

Golden and byte-exact gates: `Goldens.t.sol` (three synthetic cards), `Templates.t.sol` (ten bodies, ten hashes),
`Artifacts.t.sol` (no immutables, identical runtime twice, no forbidden opcodes, deploy script), `Attestations.t.sol`
(five served attestations recover the attester under their own domain only).

## Review observations (not defects; recorded so nobody mistakes them for untested behaviour)

- The earlier diagnostic-order discrepancy is resolved by change (a) above. Signature and answer lengths now
  precede chainId and signer; `INTEGRATION.md` states the implemented precedence.
- `nextSpecId` is a `uint16` starting at 10001: after 55,534 registrations (ids 10001 to 65534) `registerSpec`
  reverts on overflow for ever (CATALOG.md section 5, change (p)). At 1 IMD each this is a bound, not a path anyone reaches by accident.
- The mainnet Intake v2's `signer()` is `0x169b…279f`, not the attester `0x5598…2982`. The registry never reads
  `signer()`; it trusts the attester constructor argument, which is what the five served attestations recover to.
- A claimant-paid request whose callback the plane never completes locks the pair for 14 days (`abandon`); a
  shared fact likewise locks the fact id. Accepted in the brief (CONCEPT.md section 4), exercised by the abandon tests.

# CR-1: no token id on the image (2026-10-19)

The owner's change request: the hive SVG no longer prints the token id (the `<text>` element and its `F_TEXT_OPEN`
fragment are gone; `F_SVG_CLOSE` is `</svg>`). The id stays the metadata name. `tools/gen_template.py` `hive_svg` lost
its `token_id` argument; `HiveData.sol` and all 24 goldens regenerated (`--check` clean); `RenameTest.test_metadataCarriesTheFinalFamilyNames`
asserts that the image has no `<text>` element; `tools/test_gen_template.py` likewise. Offline suite: 188 passed, 17 fork tests skipped.
