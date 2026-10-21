# Frontend validation and design review

Complete for the stated frontend delivery scope. This is worker evidence, not an independent certification. The contracts were already deployed; no contract source, root build setting, root document, library or CI file was modified. No site was published and no mainnet transaction was signed by this task.

## Scope and authoritative inputs

Implemented workflow site items 23–27 on the reviewed Vite/React/TypeScript site. The existing eight pages, dark/green palette, monospace voice, hive card design and source quotations remain. Live deployment configuration and the implementation-derived ABIs replace the earlier test deployment. One wallet control supplies the required extension, phone and Coinbase paths. Existing exact-output swap, approval, Registry action and receipt-recovery flows remain, with the deployed pool/registration signatures and burn events. A pool donation uses the same reviewed transaction flow.

The source commit is `832cc45f59acdda805b51799647be24c0cae9741`. The supplied handoff and network are retained in `web/deployment-handoff.json` and `web/network.json`. No `docs/abi/` files existed at that commit; they were obtained by compiling that unchanged source, with scratch-only compiler output and the original compiler settings. All three canonical ABI hashes match the handoff, and all three runtime bytecodes match mainnet exactly. The deployment block timestamp establishes 2026-10-20 for the required About note. Details: [deployment verification](../docs/deployment-verification.json), [preview/ABI provenance](../docs/preview.md).

The overriding write budget excludes a root `DESIGN.md` and the root README. The requested design document is therefore [docs/DESIGN.md](../docs/DESIGN.md), and install/preview/rebuild instructions are in [web/README.md](README.md). `web/.gitignore` was not changed; no extra ignore path budget was consumed.

## Commands and actual results

All paths below are relative to the repository root except npm commands, which run from `web/`.

| Check | Actual result |
| --- | --- |
| `npm ci --cache /tmp/sworn-npm-cache --no-audit --no-fund` | Passed. Default cache was read-only; using a temporary cache resolved it. |
| Pinned solc build with `--out test/scratch/solidity-out --cache-path test/scratch/solidity-cache --skip test --skip script --offline` | Passed. Root source/configuration unchanged. Existing compiler/lint warnings were not contract edits. |
| `npm test` | **51 passed, 0 failed**. Includes prior review regressions plus handoff/network equality, ABI tampering, pool boundaries, snapshot copy, exact selectors, donation intents and all five receipt-decoded burn reasons. |
| `npm run typecheck` | Passed, `tsc --noEmit`. |
| `npm run check:abi` | Passed for Renderer, Composer and Registry; canonical ABI and runtime fixture hashes match. |
| `SWORN_RPC=<operator transport> node scripts/render-assets.mjs` | Passed. All 27 sample/trait/empty SVGs redrawn with deployed Renderer calls; no token-id text. Output hashes in `docs/renderer-assets.json`. Existing logo/share branding retained. |
| `npm run build` | Passed. Relative Vite base; export written to root `dist/`; deployment manifest emitted **after** the export. Nonfatal wallet-dependency Rollup annotation and chunk-size warnings remain. |
| `npm run check:export` | Passed. Exact handoff fields/contract set/network, three canonical ABI hashes, **52** exported asset SHA-256 hashes, and relative entrypoint URLs. Asset bytes: **1,587,851**; complete `dist/`, including manifest: **1,597,335** bytes. Largest asset remains below 8 MiB; count below 128. |
| `node web/tests/browser.mjs` with external Playwright and axe tooling | **100 passed, 0 failed**, Chromium and WebKit. Eight routes at 320/390/780/1280px; first-screen actions, form validation, lookup failure, navigation, keyboard skip/focus, pre-wallet mint/ETH choices, reload recovery, wallet dismissal/focus return, local resources and console checks. |
| `node web/tests/live-browser.mjs` with external Playwright and operator read transport | **10 passed, 0 failed**; no script/console errors. Live Explorer and image decoding; unavailable reads/retry; EIP-6963 names/icons, rejected connection, wrong-chain guard and exact add-chain fallback; authorized reconnect/disconnect; four phone links and Coinbase Smart Wallet. A labelled mocked RPC fixture separately verified adjacent live-price/pool values, the eighth-of-pool warning and disabled pool claim. |
| `web/node_modules/.bin/tsx --import ./web/tests/setup.ts web/tests/fork.mts` with local fork transport | **10 passed**, local-only Anvil transactions: deployment code/getters; Explorer lookup before mint; exact-output Router swap and ETH refund; approval/mint and metadata lookup after mint; paid request; receipt-derived spec id; pool donation; unminted contributor preview; sponsored claim/burn event; daily-limit rejection. |
| `/path/to/solc-0.8.24 --base-path web/public/examples --bin web/public/examples/SwornGate.sol` | Passed for the shipped Solidity example with the live Registry's checksummed address. |
| `node .imd/reads/skills/design-critic/scripts/taste.mjs --out test/scratch/taste` with external Playwright | Ran successfully against the final export at 320/390/1440px plus reduced motion. **10/16 raw checks pass**; six inherited design exceptions are explained below. |

External browser packages, browser binaries, temporary runtime libraries and npm cache were installed under `/tmp`, outside the submission. WebKit's initial missing-library failure was repaired with temporary extracted runtime libraries; the final browser run includes both engines. The rapid offline-navigation test waits for RPC failures to settle before changing pages, avoiding cancellation noise; the final result reports no console, script or local-resource errors in either engine.

## Requirement coverage

| Requirement | Evidence |
| --- | --- |
| Site item 23: live addresses, launch record, ABI regeneration, examples and previews | Runtime fetches `dist/imd-deployment.json` and its ABI paths; generated compatibility downloads and both code samples use the live Registry. A search for `39bec764` under `web/src` and `web/public` finds only the mandated About note. `check:abi`, `check:export`, SVG hash tests and live/fork lookup checks pass. |
| Site item 24: frozen direct traits, Armed, pool rules, shared panel, 31 days, signatures and burn reasons | `Claim.tsx`, `catalog.ts`, `components.tsx`, `pages.tsx`, `eligibility.ts`, `flow.ts`; ABI/unit/local-fork and browser checks. No IDMD-seat sponsored path remains. |
| Site item 25: Intake price and pool above pool claim; eighth warning | `Claim.tsx:204`; screenshot `docs/evidence/pool-warning.png` and live-browser mocked-price fixture. Zero-price and 2 IMD cap are also explained/guarded. |
| Site item 26: exact About note | `pages.tsx:164`, dated from the actual deployment block, pinned by a site test. |
| Site item 27: tests, responsive export, en-US live Explorer before/after mint | 51 unit tests, both-browser route checks, live lookup/image decode and local-fork pre/post-mint lookup. No attestation API fetch is made by the browser. |
| First phone screen | At 390×844 in both engines: Explore wallet button bottom **720.36px**; Mint card bottom **755.5px**. Product and actions visible; screenshots retained. |
| Share metadata | Title, favicon, description, `og:title`, `og:image` and local share asset are present; probe share check passes. |
| Static export and delivery instructions | Root `dist/index.html`, relative asset URLs, lockfile/source, manifest generation/check scripts and `web/README.md`. |
| Better Interface review and final design record | All six domains below; implemented tokens/components/breakpoints in `docs/DESIGN.md`. |

## Better Interface review: six domains

Applied the pinned guide's contents/workflow and the core principles of accessibility, layout, writing, typography, colors and UI while adapting the existing system. Supporting focus/modal/form and responsive rules were used for the added wallet/pool controls. The one visual idea remains a terminal-style registry carried by green hive art and compact on-chain source references.

| Domain | Coverage and evidence | Unperformed or not applicable |
| --- | --- | --- |
| Accessibility — Checked | Native labelled form controls and dialog; keyboard skip link, invalid-input focus, Escape, modal containment/focus return; named provider rows; worded states; axe WCAG A/AA/2.1/2.2 scans on all eight routes in both engines. | No screen-reader session, physical touch device or full accessibility certification. Decorative source line numbers are a retained contrast exception, described below. |
| Layout — Checked | Actual export at a `/preview/` subpath; all pages at 320/390/780/1280; probe at 1440; no body overflow or missing local image. First-screen product/action measurements and inspected screenshots. Labelled wide tables scroll independently. | Browser-native 200% zoom not exercised; narrow-width reflow is not claimed as native zoom. |
| Writing — Checked | New snapshot/pool/shared/burn copy, exact dated About note, verb-first controls, explicit unclaimed/pending/error/retry states, accurate community lookup guidance, synthetic/live labels. | Supplied quoted source text and intentional existing voice retained. No translations requested. |
| Typography — Checked | Existing source tokens/weights/scale reviewed; rendered headings, mobile 16px form text, wrapped addresses and exact en-US amount formatting checked. | Monospace prose, tracked labels and the inherited scale remain per the no-redesign instruction. No additional font families introduced. |
| Colors — Checked | Existing semantic colors preserved; probe measured resolved solid text/background pairs with no ordinary-text failure on the entry page. Axe scan covers other routes. Focus screenshots inspected. | SVG art and every possible composited pixel were not contrast-certified. Source gutter numbers at `#5f6861` on `#0a0a0a` measure **3.43:1** at 12px and are retained under the explicit no-colour-change requirement; numbers are `aria-hidden` and code remains readable. |
| UI — Checked | Square structural surfaces, consistent native control states, row pending/rejected feedback, restrained overlay, live pool warning, exact transaction stages, known-receipt recovery. Probe confirms no border+shadow collision, nested cards, gradient text, `transition: all` or endless reduced-motion animation. | No alternate theme or animation system exists; adding one is outside scope. Coinbase passkey creation/native phone app launches require a visitor's account/device and were not completed. |

## Findings, fixes and rechecks

Each source reference names the final implementation, not a generated bundle.

| Severity / source | Observation and correction | Recheck |
| --- | --- | --- |
| High — `web/src/config.ts:15`, `web/src/bootstrap.ts:1` | Earlier addresses/ABIs could disagree with an attested export. Load the actual manifest and referenced ABI files first; verify canonical hashes; generate compatibility files from the handoff. | ABI, manifest, runtime-bytecode checks; browser runtime loads manifest/ABI JSON. |
| High — `web/src/chain.ts:83` | Old preview called the now-internal `tokenURI(Card)` selector. Use deployed `tokenURIOf` with a temporary claimant storage override; leave wallet facts real and label unminted results as previews. | Actual metadata/image decode in live browser and local-fork lookup before and after mint. No dummy live image. |
| High — `web/src/Claim.tsx:91`, `web/src/Claim.tsx:117` | Old pool/registration calldata omitted required `maxPrice`/`expectedId`. Read both live, include them in intent, and check before payment/signing. | Selector/unit checks; real local-fork pool claim and registration with receipt-derived id. |
| High — `web/src/wallet.ts:20`, `web/src/ConnectSheet.tsx:1` | Earlier injected-only connection excluded phone/passkey visitors. Add the required discovery, four phone links and Coinbase paths within one control; reconnect only the last authorized connector; invalidate stale sessions. | Named/rejected connection, wrong chain/add-chain fallback, reload, disconnect, phone sheet and keyboard tests. No transaction automatically sent. |
| Medium — `web/src/Claim.tsx:204`, `web/src/eligibility.ts:35` | Pool price had no adjacent balance/cap explanation. Add side-by-side values and worded eighth/2 IMD/zero warnings; align guard reads with the latest prices. | Boundary unit tests and browser mocked-price fixture show warning and disabled action. |
| Medium — `web/src/flow.ts:108`, `web/src/flow.ts:138` | Earlier journal mapped burn codes incorrectly and consumed failed trait reservations in its copy. Decode the deployed `reason` argument and name all five meanings; explain day consumption/reservation release separately. | All five ABI-shaped receipt reasons tested, local sponsored receipt decoded. |
| High — `web/src/Claim.tsx:150` | The long explanatory flow pushed mint controls off the first phone screen. Keep it immediately after the mint panel, reusing existing layout and styling. | Both engines measured Mint card bottom at 755.5px in a 390×844 viewport; explanation and flow remain. |
| Medium — `web/src/catalog.ts:15`, `web/src/pages.tsx:67`, `web/src/Claim.tsx:152` | Earlier Armed/current-holder/direct-live copy described different behavior. Show mint snapshots, minter-bound facts and Armed's unfixed population. | Catalog/wording tests; Explorer distinguishes pre-mint and frozen state; required buyer note present. |
| Medium — `web/src/pages.tsx:38` | Static community empty row promised future automatic listings without a feed. Replace the promise with accurate `specOf` lookup and registration links, retaining the existing table/page. | Source test and both-browser navigation/render checks. |

No applicable primary-flow blocker remains. The following probe findings are **retained design constraints**, not silently called passes. The workflow explicitly says “do not change its design, colours or pages,” which takes precedence over generic preferences:

- **casing/tracking:** inherited uppercase `.section-label`, form/table labels and source captions at `.12em`; brand `.22em`. No new kicker system was added.
- **eyebrows:** inherited evidence-class marks above class headings, plus false-positive nav/source links adjacent to later headings. These identify evidence/source, not newly added marketing kickers.
- **type-sizes/type-faces:** seven repeated sizes/eight including one-offs, one monospace family and three weights. These are the established terminal design.
- **copy-budget:** 61 prose words on the 390 first screen and 228 at 1440 in the probe. The existing long product headline, description and reference explanations were retained; the primary form remains visible. The inherited headline also exceeds the generic six-word suggestion.

Raw probe result: **10/16** (render, layout, targets, contrast, glyphs, slogans, repetition, chrome, motion, share pass). Actual contrast or overflow failures on primary changed surfaces were not waived.

## Evidence and limits

Committed delivery evidence is under [docs/evidence/](../docs/evidence/): 100 browser results, 10 live-browser results, 10 local-fork results, raw taste results and screenshots of mobile/desktop entry, phone mint, live Explorer, phone wallet picker and the explicitly mocked pool warning. The scratch probe output is not relied on after submission.

Mainnet chain reads and deployed-runtime comparisons were performed; transaction validation stayed on a local fork. No production mint, spend or bridge delivery was attempted. Shared-fact application requires a genuine accepted list; no oracle verdict was fabricated to make that path appear successful. Coinbase native app/passkey completion, physical-device deep-link launches, a screen reader, native browser zoom and post-publication IPFS/ENS HTTP checks remain outside the performed checks. Hosting/CIDs are subsequent control-plane work and are not worker-completion prerequisites.
