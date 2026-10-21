# Deployments

## Ethereum mainnet replacement: source prepared 2026-10-21

This assignment implements the replacement described by docs/V3.md. It deploys no transaction and asserts no new address. The 2026-10-20 deployment is replaced by this release, was never announced, and stays on chain; its exact record follows as history. Confirmation of the new deployment is pending the separate manifest, independent review and deployment services.

The deployment order is Renderer (no arguments), Composer (no arguments), then Registry with seven addresses: Curator `0xcb0b0531e86a9ac36fa865ca8e3dbccf047fda91`, IMD `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`, Intake v2 `0xa43e6f75ee006411f79ac1c84120606c2330de82`, attester `0x5598aa9146215bc13eb26f2c692ad1461fd32982`, new Renderer, new Composer, executor `0xe29386719C155B6847aD5a4E97C6674f10ffc750`. No IDMD constructor argument, owner or ETH value exists.

README.md documents deployment checks and external responsibilities; test/NOTES.md records sizes and gas. The constructor's mandatory external executor-code check and the generic empty-chain probe must be resolved in launch review. No new `sworn-verify` gate, factory gas simulation, hosted URL, source attestation or independent audit is claimed by these source checks. The supplied 2026-10-21 oracle lab stands without a rerun. The historical manifest and signed artifacts are preserved for the service to replace, not relabeled as this build.

## Ethereum mainnet (chainId 1), 2026-10-20: the deployment of the docs/V2.md release, IMD swarm launch #2341

- **Status:** replaced in the source release below, never announced; remains on chain. Built, audited and deployed by the IMD swarm as one `workflow.open` (workflow `7e7dbd09-598a-41cf-8204-00b52caddb08`,
  contracts job `472763cf-7481-495d-950c-000db51d562f`, paid 2026-10-20 19:51 UTC by pawai.eth, 0.5 IMD, order `b621f047`).
- **Input:** this repository at tag `v2-base` = commit `007fbeb702613345389bc842a4005c07f3966ab1` (docs/V2.md, ninth cut).
- **Source as deployed:** commit `832cc45f59acdda805b51799647be24c0cae9741` in
  https://github.com/identity-md-launches/launch-2341-renderer-composer-registry (the swarm's commits on top of `v2-base`, PR #1).
  Judge-accepted after one revision round (2026-10-20 22:13:37 UTC); 222 tests; admission 7 of 7 checks passed.
- **One transaction, from the factory:** `0x079af9dac38001b9b6e6e5799fc5381c27fbb98debeff78af89fd7ab489e88d4`, block 26,236,719
  (2026-10-20 22:14:59 UTC), sent by the launch wallet `0xcECc29B037f5064fCdF45a5C318F132ef76aA551` to the factory
  `0xfF03410d0Fe5fa8f7F59F743de35E333D9857120`, 16,330,676 gas of the 16,777,216 per-transaction cap, fee 0.0026 ETH.

| Contract | Address | Runtime bytes | keccak256 of the runtime |
|---|---|---:|---|
| Renderer | `0x4c7fe2202b29c23b54bd45053a6c88061f1296ef` | 23,092 | `0xf17b2f216bb8308110f7b649c7c0acd8bfbd81c235fb4423569d2160d3756a6b` |
| Composer | `0x1d7da5353830248b042fc1396d5d12c31ac69824` | 23,621 | `0x19d1b889059013126fe03ef4b0a36e578f2eec64798f9da774d59d69fa012cce` |
| Registry (`Sworn`, `SWORN`) | `0xdd0017e40f1a5fe514d15d108ce01eb52f2a5edb` | 22,943 | `0x1c9210de6ffd1eda2ace94bc9459038c3a698701686997ef4704d20282be18ba` |

- **Toolchain:** solc 0.8.24, optimizer 200 runs, cancun, `bytecode_hash = "none"`, forge 1.8.3 (the swarm); the entrant's clean
  rebuild with forge 1.5.1 produced the same bytes.
- **Wiring (Registry getters):** `curator` `0xcb0b0531e86a9ac36fa865ca8e3dbccf047fda91`, `idmd` `0x0000ec93127baa929e58e97dd0095a2bfb38ec1d`,
  `imd` `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`, `intake` `0xa43e6f75ee006411f79ac1c84120606c2330de82` (Intake v2), `attester`
  `0x5598aa9146215bc13eb26f2c692ad1461fd32982`, `renderer` and `composer` as above, `burnExecutor`
  `0xe29386719C155B6847aD5a4E97C6674f10ffc750` (BurnExecutor V2). `deployedAt()` no longer exists (docs/V2.md item 10). `nextSpecId()` = 10001.
- **Launch-day gate (entrant, `sworn-verify`, 2026-10-20 22:27:56 UTC): PASS, 23 of 23 rows.** The runtime code and the creation code of all
  three contracts equal a clean build of `832cc45f`; the Registry's eight constructor arguments decode as above; all three were created in the
  transaction above by the factory. Record: aidude `data/surf/launch_verify/20261020T222756Z-1.json`.
- **Known deviations from docs/V2.md, recorded by the builder and accepted by the judge:** item 19's gas target is not met (`tokenURI` at the
  maximum state measures 10,317,448 gas against the 8,000,000 target; parts (a), (b), (c) are done and the regression test exists; the next
  cut is named in `test/NOTES.md`); item 9 keeps 16-bit community ids (registration ends at id 65,534, pinned by a test).
- **Earlier deployment:** the section below (launch #2147, 2026-10-18) was a test deployment, never announced. It stays on chain as it is.
- **Source verification (state 2026-10-21 00:10 UTC):** all three contracts carry a full Sourcify match (creation and runtime bytecode):
  Composer 2026-10-20 22:30:04 UTC, Renderer 22:30:19 UTC, Registry 2026-10-21 00:01:49 UTC (the Registry's match arrived about 1 h 45 min
  after the two others; `https://sourcify.dev/server/v2/contract/1/<address>`). Blockscout imports each match within seconds and shows the
  three as verified via Sourcify (`is_fully_verified: false` is Blockscout's own flag for an imported match, not a partial match). Etherscan not
  checked (its API needs a key). Before the matches landed, the swarm's verifier and the entrant's gate had compared the bytes directly.

## Test deployment on Ethereum mainnet (chainId 1), 2026-10-18 (launch #2147; never announced)

| Contract | Address | Runtime bytes | Runtime keccak256 |
|---|---|---|---|
| Registry (`Sworn`, `SWORN`) | `0x39bec7648259d5a128c29b24951eabcd4d1f95a6` | 24,561 | `0x9c88410fb6463610043b3adeea1ab857096e83ca8e0aea4f73f63433fbfb42d2` |
| Composer | `0x06bf2168dd115fa37bd1637fa1f50adb29a3029d` | 23,655 | `0x79359a04f91e52693816feb7a9d90b4c75e44abb838f9061e8eee209f6ca417e` |
| Renderer | `0xea9185cc6dffe42a8c059b099c50cb21021439ad` | 21,570 | `0x1fb854135321f70bb61cefbd688f8375179cdb7c4fb2af2009583786f7d47efb` |

- **Source:** commit `59e9bf04b359e523d5d3ba784d017dafc5ef32e1`, tag `v1-mainnet`, built by the IMD swarm on the
  `swarm/job-6` lineage and fast-forwarded onto `main` on 2026-10-19.
- **Launch:** IMD swarm launch #2147 (`evm_contracts`). All three contracts were created in one transaction,
  `0xe647fe252afa7fac3fbbf56e1c3ad64de2093337c29d199a2280c25dc4704c24`, block 26,217,644, from the plane's launch
  wallet `0xfF03410d0Fe5fa8f7F59F743de35E333D9857120`. `Registry.deployedAt()` = 1792304771 (2026-10-18 06:26:11 UTC).
- **Compiler:** solc 0.8.24+commit.e11b9ed9, optimizer on, 200 runs, EVM `cancun`, `bytecode_hash = "none"`,
  `cbor_metadata = false`; none of the three has immutables, so the runtime code equals the build byte for byte.
- **Gate:** aidude `sworn-verify` record `20261018T062734Z-1`, verdict `GATE: PASS`: the runtime code of the three
  contracts and the creation code in the transaction equal a clean build of the commit; the Registry's eight getters,
  name and symbol equal the expected mainnet values below.
- **Wiring (Registry getters):** `curator` `0xcb0b0531e86a9ac36fa865ca8e3dbccf047fda91` (the settled WhitelistCurator),
  `idmd` `0x0000ec93127baa929e58e97dd0095a2bfb38ec1d`, `imd` `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`,
  `intake` `0xa43e6f75ee006411f79ac1c84120606c2330de82` (Intake v2), `attester` `0x5598aa9146215bc13eb26f2c692ad1461fd32982`,
  `burnExecutor` `0xe29386719c155b6847ad5a4e97c6674f10ffc750`, `renderer` and `composer` as in the table.
  Constants: `SPEC_FEE` 6.4 IMD, `MINT_FEE` 0.1 IMD, `BURN_MIN` 69 IMD, `BURN_FEE_CAP` 0.005 ETH, `nextSpecId` 10001 at launch.
- **Explorer verification (state 2026-10-19 13:00 UTC):** all three contracts are verified on Sourcify with a full match of
  creation and runtime code: Registry 2026-10-18 16:32 UTC, Composer 2026-10-19 12:24 UTC, Renderer 2026-10-19 12:55 UTC
  (submitted by the entrant from a clean build of `v1-mainnet`, standard JSON input, solc 0.8.24+commit.e11b9ed9;
  https://sourcify.dev/server/v2/contract/1/<address>). Blockscout shows the Registry and the Composer verified and
  imports the Renderer's Sourcify match on its own schedule. Etherscan: the Registry is verified there (the One Dollar
  Audit of 2026-10-19 read its source from Etherscan's verified-source API); Composer and Renderer were not queried.
- **Name:** this repository was `banse/chaintraits` until 2026-10-19; the launch record cites that name and the commit
  above. The old URL redirects here.
- **Known issues of v1:** see `DISCLOSURE.md` and the repository's issues (the One Dollar Audit of 2026-10-19 and its
  disposition are published with issue #4). No contract has an owner, setter or upgrade path, so every fix is a v2 redeploy.
