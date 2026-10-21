# Sworn implementation check record — 2026-10-21

## Additional test contribution — 2026-10-21

This contribution changes tests only. It preserves the accepted implementations, ABIs, manifest and compiler settings. The implementation contributor's earlier record follows this section.

- Final checks: `forge build` passed; `FOUNDRY_FUZZ_SEED=0x7c957293ff75a8e7a5429abda6a1cb5d2219e70049d12b296b29a269a719cba4 forge test` passed with **209 passed, 0 failed, 12 opt-in fork tests skipped**, across 22 suites. All three new invariants passed 16,384 calls with zero unexpected reverts. `forge fmt --check` on the changed Solidity tests and `git diff --check` passed. The default suite requires no network.
- `WorkflowAccountingInvariant.t.sol`: four actors receive fixed initial budgets, with no further token creation during the campaign. Thirteen explicitly selected actions cover minting, current-owner and approved transfers, changed live reads, spec registration, changing oracle prices, requests, rejected duplicate batches, successful/negative/malformed deliveries, failures, deadlines, late callbacks and shared-fact applications. Three invariants reconcile each actor's spending with fee receipts, preserve card claimants and snapshots, preserve accepted facts and the operator window, and reconcile pending records with their reverse indices. The campaign uses 256 sequences of 64 calls and fails on unexpected reverts. A deterministic handler exercise checks successful calls, failures, retry and late-callback counters. The mock Intake balance is a receipt ledger for its token pulls; this is not a claim that the live Intake retains fees.
- `WorkflowFailurePaths.t.sol`: payment faults at later positions of a batch roll back earlier payments, allowances, pending entries and the Intake nonce, then allow a complete retry. Additional cases cover duplicate traits at the end of a batch, a dependency failure after the mint fee transfer, false-returning fee transfers, validation before charging, cross-namespace request-ID collisions, and both delivery/abandon orderings for shared facts at their time boundaries.
- `WorkflowInputProperties.t.sol`: 1,000 examples per property exercise generated field names, indexed-address requirements, exact signature boundaries, question/consumer separation, body and definition size limits, actual mainnet finality, and malformed Renderer offsets. Renderer failures must carry `UnknownTrait(601)` within the capped call, rather than panic or exhaust gas.
- `Adversarial.t.sol`: the required seed exposed the inherited oracle-ID classifier's omission of 601. The classifier now includes Swarmed as required by item 6. The property no longer filters valid IDs away: valid personal oracle IDs must create a paid pending request, while shared and unknown IDs must revert with the appropriate error.
- Item coverage added: 2 (fee conservation and atomicity), 3–4 (shared deadlines and late callbacks), 5 (collisions across personal/shared indices), 6 and 8 (stored operator windows, claimant identity and irreversible accepted facts), 31–33 (generated fields, grammar and finality), and 34 (random hostile metadata offsets). Existing fixtures, protocol signature vectors, size gates and remaining item tests are retained.
- No dependencies were added; the suites use the repository's existing vendored libraries and local fixtures. No new test uses a fork, FFI or environment mutation. Live integration remains covered by the existing opt-in fork suite; this contribution does not claim a new live fork run.
- Runtime sizes are unchanged: Registry **20,465**, Composer **24,068**, Renderer **23,553** bytes; total **68,086** bytes.
- One concrete requirement/check conflict is reported in `.imd-findings.json`: the approved unconditional executor-code check prevents the supplied empty-chain deployment rehearsal. A self-contained same-transaction factory proof was run separately and failed with `ExecutorHasNoCode()`. Its full source is embedded in the finding; the deliberately failing proof is kept out of the submitted default test suite. This is not a claimed failure against the live mainnet executor, and the approved source check was not weakened.

Scope: docs/V3.md items 1–22 and 31–34 on base commit `092cc28447d29a5f96ecd35b866e470513ca06f8`. One source contributor; no independent review or live deployment is asserted. The prior test record is preserved in docs/history/test-notes-2026-10-20.md. The project's build settings and dependencies are unchanged.

## Checks

- `forge build`: pinned Solidity 0.8.24, optimizer 200, Cancun, no via-IR or metadata hash.
- `forge test --offline` with `FOUNDRY_FUZZ_SEED=0x7c957293ff75a8e7a5429abda6a1cb5d2219e70049d12b296b29a269a719cba4`: **195 passed, 0 failed, 12 opt-in fork tests skipped**, 19 suites. Existing invariants and fuzz tests are included. No tests read or write environment variables.
- Archive integration: `forge test --offline --match-contract MainnetForkTest --fork-url https://eth.drpc.org --fork-block-number 26237654 -vv`: **12 passed, 0 failed**, using the real Curator, token, Intake and executor at that pinned block. These are local fork transactions only.
- `forge fmt --check`, both generator `--check` commands and `tools/export_abis.py --check` **passed**. `python3 -m unittest discover -s tools -p 'test_*.py'`: **18 passed**, including hive tiling, rotations, exact corners, triangle subdivisions, valid SVG/JSON and fixture consistency.
- The protocol conformance vector digest and signature recovery pass, alongside five externally served attestation fixtures. Ten T1–T5 body/hash fixtures remain byte-identical; T6 has its own exact body and independently derived canonical hash.

## Size and gas

Measured from the final pinned build. All three runtime sizes satisfy EIP-170 individually; their sum is below the 69,800-byte gate.

| Contract | Runtime bytes |
|---|---:|
| Registry | 20,465 |
| Composer | 24,068 |
| Renderer | 23,553 |
| Total | **68,086** |

`Revision3Test.test_item19_tokenURIAtTheMaximumStateIsMeasuredAndBounded` measures **10,023,370 gas**, URI 41,181 bytes, below 10,317,448. State includes all 25 catalog facts, the full 32-address shared answer, and 32 verified community specs with maximal rendered fields. It also succeeds through a call capped at 10,317,448. The 8,000,000 target remains unmet and is not the acceptance gate.

`V3Test.test_coldCallbackGasForLargestStorageWrites` measures **150,178 gas** at the largest sampled callback (first community entry); Swarmed with a minted card measures **111,977 gas**. The shared 32-entry case, malformed large answers and signatures, invalid/expired answers, negative answers and later retries also complete under the 200,000-gas Intake stipend. Measurements use the mock's actual callback call bracket, with Registry cooled before delivery.

The size budget required lossless compression of static Composer text and a shared interpolation serializer. Readable source is `templates/composer-text.json`; `tools/gen_composer_text.py --check` verifies 25 ASCII strings, 5,809 expanded bytes, 3,729 packed bytes, a byte-exact round trip and every Solidity slice offset. Templates use ~A through ~P only for static interpolation; inserted values are not interpreted again. The decoder accepts no external packed input. Renderer decodes only generated ASCII hex with a compact assembly loop to meet the gas gate. All existing independent body/card goldens continue to check the resulting bytes. No grammar rule or renderer hardening was omitted for size.

## Item evidence

| Item | Implementation and check |
|---|---|
| 1 | Retired operation, state, events, ETH handling and browser paths removed; source/docs/web scan is clear except the protected dependency metadata noted below. Existing surviving tests adapted; invariants assert no retained action funds. |
| 2 | Exact caller-to-executor transfers; `V3Test.test_feesForwardExactlyAndFailureIsAtomic`; pinned `MainnetForkTest.test_fork_mintForwardsFeeAndPreviewIncludesItWithinLiveLimits`. |
| 3 | Shared abandon by anyone, personal by claimant; `test_sharedAbandonPermissionlessPersonalClaimantOnly`. |
| 4 | One-day issue bound, 30-day validity and strictly later abandon; bad-date, 23-hour issuance and both deadline-order tests in V3Test. |
| 5 | Live-id collision reverts transfers/approvals; late abandoned callback leaves successor index; two dedicated V3Test tests. |
| 6 | Swarmed paid kind 6, stored pending/accepted window, bit 20 unused; operator metadata/head-advance, false/window/panel misses and direct-negative fuzz tests. |
| 7 | Seven Registry constructor arguments/getters and two-argument directSnapshot; Deploy/Artifacts/Floor and ABI checks. |
| 8 | Existing uint16 exhaustion, clear-before-check, complete shared answer, transfer, supply and dependency-failure tests retained in ReReview, Registry, RegistryRules, Revision3 and invariant suites. |
| 9 | Current source NatSpec and integration documents describe only current operations. |
| 10 | Kind 6 unavailable to community registration; exact 11/7 bool panel in operator golden. |
| 11 | Exact operator question checked byte-for-byte against T6 fixture. |
| 12 | Eight definitions in approved body order; independent sorted canonical hash; each fixture value at most 512 bytes. |
| 13 | T6-operator-reference.json and T6-operator-hash.txt; approved 2026-10-21 lab evidence stands, no new lab request. |
| 14 | Ten inherited fixture bodies/hashes cover unchanged recipes, including 1201; shared completeness tests retained. |
| 15 | Swarmed name, panel colour, stored window, request ids and panel literals; goldens plus `test_allRendererPanelMinimaMatchComposerBodies` across all six kinds. |
| 16 | gen_template.py regenerates HiveData/TemplateData and card fixtures; 18 generator tests; hashes below. |
| 17 | Maximum-state gas gate tightened and passes at 10,023,370. |
| 18 | Seven zero-address guards and unconditional helper code checks; the executor code check applies on every chain where Curator, IMD or Intake has code and is skipped on the empty-chain floor only (deviation recorded in point 1 below); live checks cover settlement, decimals and price. `V3Test.test_allSevenDependenciesNonzeroAndThreeCodeChecksAlwaysApply` covers the off-floor revert, the floor construction with an absent executor and the single-coded-dependency case; `FloorTest` deploys both parameter sets with no executor code. |
| 19 | Mainnet and Sepolia parameter rehearsals, seven arguments; mainnet fork verifies live V2 executor, no dependency on a Sepolia launch outcome. |
| 20 | README, CATALOG, CONCEPT, INTEGRATION and TEMPLATES updated; field rules, grammar, trust boundaries, windows and fee path documented. |
| 21 | DISCLOSURE adds present limits while preserving historical records. |
| 22 | DEPLOYMENTS names the replacement source release and earlier unannounced on-chain deployment; confirmed new addresses remain the deployment service's output. |
| 31 | Real indexed address arg, real indexed fixedArg and existing sumArg; V3 field validation and inherited indexed-position tests. |
| 32 | Closed grammar, every permitted scalar/array type, prose/anonymous/invalid-name/type failures, maximal-spec fuzz with question <=1000, each definition <=512 and body <=16384. |
| 33 | Mainnet blockNumber spoof test and Sepolia window tests; public-view trust and other accepted design limits documented. |
| 34 | Hostile huge/negative offsets and 1 MB returndata revert cleanly under 5M; invalid families and 25-id cap; single-quote escaping and regenerated hostile-name golden; credential distinction documented. |

## Concrete review and stage boundaries

1. **Required constructor check versus the launch floor (deviation from item 18, resolved 2026-10-21 under the workflow's DECIDE rule):** item 18 asks for the executor code check "always and outside any floor branch". The launch's protected deployment probe (`.imd/reads/protected/evm_contracts/Contracts.protected.t.sol`) CREATE2-deploys only the three application init codes on an otherwise empty chain, so the BurnExecutor V2 has no code there and the unconditional check reverted `ExecutorHasNoCode()`, failing the probe with "application 2 constructor failed" and parking the launch (independent review finding 8119cd99, with proof). The workflow rule for a conflict between an item and a required check is to make the smallest change that satisfies the check and record it here: `if (burnExecutor_.code.length == 0) revert ExecutorHasNoCode();` moved inside `if (!floor)`, where `floor` is unchanged (Curator, IMD and Intake all without code). Everything else of item 18 stands: seven `ZeroAddress` guards, unconditional `DependencyHasNoCode` at the renderer and composer, no attester code check, and on mainnet, where the three read dependencies have code, a codeless executor still reverts. `FloorTest` no longer etches a byte onto the executor and asserts it is absent; `V3Test.test_allSevenDependenciesNonzeroAndThreeCodeChecksAlwaysApply` expects the off-floor revert, the floor construction with an absent executor, and the revert as soon as one read dependency has code. The pinned mainnet fork test still constructs against the live V2 executor. docs/V3.md item 18 is left as approved; this entry is its record.
2. **Manifest:** the existing launch.json is historical and still has eight Registry arguments. It was not edited because this assignment is source-producing. The separate manifest assignment must replace it with the seven arguments in README, then independent review checks source and arguments. No signed artifact linkage, policy admission or factory simulation is asserted by source tests.
3. **Removal scan and protected files:** all current application paths in the requested scan are clear. The protected web/package-lock.json still includes third-party GitHub funding URLs that match the first literal scan pattern. Changing that lockfile is forbidden by the assignment's overriding rule. No exception was taken for application copy, code, config or browser tests. Historical text is kept only in the permitted history documents.
4. **Site/export:** the old executable dist export and old active handoff copies were removed because they contained retired selectors and described previous contracts. The signed old handoff is preserved under docs/history. Web source and ABI copies are cleaned; no new deployment or ABI hash was invented to make the old handoff appear current. The later site assignment supplies the new handoff and runtime evidence, rebuilds previews/export, runs npm/browser checks and completes site rows 23–26. Those checks were not claimed here. Dependencies and lockfiles remain untouched.
5. **Review/deployment:** this work performs no live transaction, key access, source publication, attestation, announcement or independent adversarial review. Those belong to later workflow stages. No requester-only value is missing.

## Generator build record

Generator base commit: `092cc28447d29a5f96ecd35b866e470513ca06f8`. The generator edits in this submission update family 6, metadata description and the hostile quote fixture. The SHA-256 of the generator itself and every required generated artifact follows. This is reproducibility evidence, not a claim about authorship. Hive tiling tests passed. Re-run `python3 tools/gen_template.py --check` and compare these bytes.

| File | SHA-256 |
|---|---|
| `tools/gen_template.py` | `13ca8ab3976994d03fa12d85fcbd9e6084677fce0dc5ff82a554a2b25bcc570a` |
| `tools/test_gen_template.py` | `34b454be0d657d20be96a653db178f1b2fd6fcfb08136a5250e295d9df0e891d` |
| `src/HiveData.sol` | `1eaeb0d60da322f400208d6d94f38f519510bbda55f82bb818b39906ae9d397c` |
| `src/TemplateData.sol` | `830934f045ae0a9dba8913b12475a7bce034db41222388c9763dc8b032f14174` |
| `template/blob.hex` | `11670c0cc6bcaa334528934f6588ba400c40e327119875225096b7c97ccb497d` |
| `template/offsets.txt` | `78f304d5153c1cba469cc268f5cf8b8bd14fd4e93ea8e908c357a5395bdb3c27` |
| `test/fixtures/golden_synthetic_collector_preimage.txt` | `6b36147a7b521082878143ea281f050c755e67dfcbd5cf9e76542f7d774bb8f1` |
| `test/fixtures/golden_synthetic_collector_svg.txt` | `4c60e3baeab86175964eb2d50ce00212231fb6cff42e5e90437546a65ecb81a6` |
| `test/fixtures/golden_synthetic_collector_uri.txt` | `afabc087af5c8f5b1deed1cd899c87e86634037573500a5cb0f9b56a7cc5bb97` |
| `test/fixtures/golden_synthetic_direct_preimage.txt` | `f2d6ddf98d7d2f8394930e14165446670fd6f1195d52a5d6fea9c71449e138d8` |
| `test/fixtures/golden_synthetic_direct_svg.txt` | `a4120a75ad18f8b81528e211c448e4edb12cdf9c97849d538afb0554030e568b` |
| `test/fixtures/golden_synthetic_direct_uri.txt` | `c0de1b14ddc310502e2b2671651ec32a4b2af6437183f1e14a2dd678b7d99ce4` |
| `test/fixtures/golden_synthetic_fullhouse_preimage.txt` | `01fadad0f0b67ad1edf76ab063233eb80de8f7772599984df0a1c04fdd45d53e` |
| `test/fixtures/golden_synthetic_fullhouse_svg.txt` | `8c95040b53b013ce3f62bd44c91f5fba8129f19f84e24b3fdc092cd9c0d8d7e3` |
| `test/fixtures/golden_synthetic_fullhouse_uri.txt` | `b51e53cf365b55ff0089659657ae40b258b578f3eb5256ef598298d557ee03e6` |
| `test/fixtures/golden_synthetic_honey_preimage.txt` | `9c0b6fad76260062228d4abaa1e8c5d34e12b88582e073d9e0b140f132556211` |
| `test/fixtures/golden_synthetic_honey_svg.txt` | `19f3a7a952557d60261d180513856cef92bf91b7e5d134d7176f1b6380821908` |
| `test/fixtures/golden_synthetic_honey_uri.txt` | `778c1eb5fe4a02ed2dfd4d75eb3bcc785c2edd9c7120be2adbd1f045c74b6abb` |
| `test/fixtures/golden_synthetic_newcomer_preimage.txt` | `5408f1390c07c5e734875b749598071eeccad2076b9ef8eb50e686b8ee06f44f` |
| `test/fixtures/golden_synthetic_newcomer_svg.txt` | `cd59241272474c69ff19a565ace7a9fc55f9f46aaa5227f8bb9782cdc0535074` |
| `test/fixtures/golden_synthetic_newcomer_uri.txt` | `af6df819f8aa3615d23a63e9ff40224012f0baa10682cb1a913c9253a535d37d` |
| `test/fixtures/golden_synthetic_oracle_preimage.txt` | `a7b90cd027af1aeba080ab870388578bdd562a39c10894caa2b5a28841b42a8a` |
| `test/fixtures/golden_synthetic_oracle_svg.txt` | `cb2441418bcfc21b247faf8afb414aaab3c020bdb1574043396ca6fddbd5f996` |
| `test/fixtures/golden_synthetic_oracle_uri.txt` | `5c35bc69726aea37e08af64cc89cf6636332ff4c6edf3553fc034d40b39f9fd4` |
| `test/fixtures/golden_synthetic_outsider_preimage.txt` | `ed692a013d03b1c2d89f7978dc14b14ebefd843b4e3d16c2121a9419adb8e959` |
| `test/fixtures/golden_synthetic_outsider_svg.txt` | `e01fba00d2e003f8c8a6680722fede3dff11813fa27ad451ada71740aef23520` |
| `test/fixtures/golden_synthetic_outsider_uri.txt` | `41f7c5cad6e4526012af3eb5ad23e1c97fc80ad235f8c614f5cf3ae26d8a72f4` |
| `test/fixtures/golden_synthetic_width_preimage.txt` | `aba6b187b7d9b899e19e93753cb685bc56392e271cf985a0c8e4ea3d54168af7` |
| `test/fixtures/golden_synthetic_width_svg.txt` | `7bfe580f399c8332a3dfb67676cd663db36d7cdce4c2857d144b12bf7d4bbba6` |
| `test/fixtures/golden_synthetic_width_uri.txt` | `15633581243ba4b97b9bcaec9496bb24efb0884af8b625e2c336204db4177739` |
