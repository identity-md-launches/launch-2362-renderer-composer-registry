# Sworn

Sworn is an ownerless ERC-721 registry of facts about wallets on Ethereum mainnet. Each wallet can mint one transferable card. Its facts belong to the wallet that minted it, regardless of who holds the card later. Thirteen Curator traits freeze at mint; oracle facts are permanent once verified. Swarmed (601) proves that a wallet operated an IdentityMD seat through at least three accepted swarm entries during its own holding intervals.

The application consists of `Registry`, `Composer` and `Renderer`. There is no administrator, pause, setter, proxy, upgrade path or new ERC-20. Existing IMD pays for actions. Minting costs 0.1 IMD and community registration costs 6.4 IMD. Fees are forwarded to the BurnExecutor V2 for bridging and burning on Base. Oracle requests pay the Intake's current price, bounded by the caller's maxPrice; the observed price at the integration block is 0.5 IMD. The Registry accepts no ETH and retains none of the funds from these action flows.

## Build and check

Use the repository's existing Foundry dependencies and pinned compiler configuration: Solidity 0.8.24, optimizer 200 runs, Cancun, no metadata hash, no via-IR. No installation, network, environment variables, filesystem writes from tests or FFI are needed for the default suite.

```sh
forge build --offline
FOUNDRY_FUZZ_SEED=0x7c957293ff75a8e7a5429abda6a1cb5d2219e70049d12b296b29a269a719cba4 forge test --offline
forge fmt --check
python3 tools/gen_template.py --check
python3 tools/gen_composer_text.py --check
python3 -m unittest discover -s tools -p 'test_*.py'
```

Optional integration checks use an archive RPC, with the fork supplied by the command line. They perform no real transactions and skip in the offline suite:

```sh
forge test --offline --match-contract MainnetForkTest --fork-url https://eth.drpc.org --fork-block-number 26237654 -vv
```

The mainnet tests cover the actual Curator, Intake failure and success delivery, exact fee forwarding and the executor's post-mint bridge quote. `test/NOTES.md` records results, runtime sizes, gas and generated-file hashes. Tests are evidence, not an independent security audit.

## Deployment parameters

Deploy on Ethereum (chain id 1), in this order: Renderer with no arguments; Composer with no arguments; Registry with these seven address arguments. Deployment sends zero ETH.

| Position | Parameter | Value |
|---|---|---|
| 1 | curator | `0xcb0b0531e86a9ac36fa865ca8e3dbccf047fda91` |
| 2 | imd | `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7` |
| 3 | intake | `0xa43e6f75ee006411f79ac1c84120606c2330de82` |
| 4 | attester | `0x5598aa9146215bc13eb26f2c692ad1461fd32982` |
| 5 | renderer | the new Renderer (`$contract:Renderer`) |
| 6 | composer | the new Composer (`$contract:Composer`) |
| 7 | burnExecutor | `0xe29386719C155B6847aD5a4E97C6674f10ffc750` |

All seven must be nonzero. Renderer, Composer and executor must have code, including during a floor rehearsal. A floor where Curator, IMD and Intake all lack code skips their three passive reads only; otherwise Curator must be settled, token decimals must be 18 and Intake must sell the action. Attester is an EOA. No ownership argument is required: nobody receives administrative powers. The factory is never made an owner.

The script's `deploy` function takes explicit dependencies; tests invoke it directly. No broadcast was performed for this assignment. The separate manifest and deployment services must replace the historical manifest with the seven-argument constructor, review it, simulate deployment and publish confirmed addresses. Historical deployments are recorded in DEPLOYMENTS.md. Source completion does not assert a new address or a successful launch gate. The unconditional executor code check conflicts with a completely empty-chain constructor probe; the deployment service must account for the real dependency code, as described in `test/NOTES.md`.

## Using the contracts

Approve Registry to spend the exact IMD amount before an action. `mintCard()` mints once per claimant; transferring the card does not reset mint eligibility. `upgrade(ids, maxPrice)` requests personal oracle facts, including 601. `requestSharedFact(id, maxPrice)` purchases one shared answer; `applySharedFact(id, list)` checks its hash and the caller's membership without another oracle payment. `registerSpec(spec, expectedId)` stores a validated immutable community specification and returns its id. An expectedId of zero opts out of an ordering guard; otherwise a changed next id reverts. Community ids run from 10001 through 65534.

Pending requests bind both the question hash and exact block window. Only Intake can deliver, and the single configured attester must sign the canonical 15-field EIP-712 attestation in this Registry's domain. The signature is not a proof that the answer is true: trust still rests on the oracle's evidence and signer. A miss or no-verdict releases the pair and spends the price. A personal claimant or anyone for a shared fact can abandon strictly after 31 days. The latest admitted issuance is one day after the request, with at most 30 days of validity, so valid delivery and abandonment never overlap. An accepted fact never expires.

Swarmed uses an absolute window from block 25,090,085 to the request's block minus 64. Its signed answer requires an 11-member panel and quorum seven. The accepted window is stored forever and remains unchanged when the head advances. A negative answer permits another paid request after more work. The other catalog recipes and historical windows are unchanged; T6 is unavailable to community registration.

## How to verify a card

Resolve the intended Registry from the confirmed deployment handoff and verify its code and seven dependency getters. Call `hasTrait(claimant, traitId)` on that Registry for the credential. A card's `claimantOf(tokenId)` identifies the subject; `ownerOf` identifies only its holder. Check `verified` and its stored request ids and block window when provenance is needed.

A rendering is not a credential. Renderer accepts a caller-supplied registry, and its output names no registry. A convincing SVG, tokenURI or preview alone does not identify the contract that vouched for it. Renderer bounds hostile spec replies, ignores invalid catalog families and reads at most 25 catalog ids. Its community display cap is 32 but the preceding `verifiedSpecsOf` read remains unbounded; DISCLOSURE.md explains the accepted limit.

## After launch

No initialization calls or owner settings exist. The deployment service publishes source, ABI and confirmed addresses, simulates the complete factory transaction, and performs independent review. The later site assignment consumes that handoff, rebuilds the website and runs its browser and launch verification gates before hosting or announcement.

Operators monitor Intake availability, price, callback gas, attester continuity and archive evidence availability. The fixed dependencies cannot be repaired here; a protocol change may require a successor Registry. Anyone may separately pay to bridge the executor balance; its owner controls external configuration and rescue powers. Bridge delivery and the Base burn are asynchronous and are not guaranteed by Registry. No failure entitles a claimant to an oracle-fee refund.

Read `CATALOG.md` for ids and predicates, `TEMPLATES.md` for all six recipes, `INTEGRATION.md` for callbacks and hashing, `DISCLOSURE.md` for trust limits, and `docs/abi/README.md` for ABI exports. Generated text is reproducible from `templates/composer-text.json`; generated card data and independent SVG/JSON goldens come from `tools/gen_template.py`.
