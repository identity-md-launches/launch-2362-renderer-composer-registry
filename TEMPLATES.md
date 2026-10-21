# TEMPLATES.md: the six question templates

These are the templates of the Sworn registry. Community specs support T1 through T5; catalog oracle traits also use T6 for Swarmed (`CATALOG.md` section 3). Each question body comes from one template per recipe kind, so the stored parameters and the text can never disagree. The v4 market recipes (`v4-volume-rank`,
`univ4-spot`) are not wallet facts and are not offered; a fees-paid panel text was considered, never ran end to end, and is not offered. T2 shares T1's shape with a sum instead of a
count. **Checked and quoted 2026-10-12, 00:00 UTC (round 2):** all ten fixture bodies passed `POST /requests/check`
with no blockers (the two T5 bodies carry the plane's usual "reads as chain evidence" suggestion, ignored by design)
and were admitted by a free `POST /requests/quote`, each with its canonical window pinned unchanged and the hash of its
last block as `toBlockHash`. The ten check responses and the ten quote records are vendored under
`reference/plane/checks/` and `reference/plane/quotes/`; the plane's `questionHash` for each body is in
`reference/plane/questionHashes.json` with the canonical document it hashes (`INTEGRATION.md` section 4, check 7).
T5's wording changed in round 2 (account nonce only, see below); the previous wording was attested twice on mainnet on
2026-10-11 (true 7/11, false 7/11) and the new one has not been attested yet. The exact bodies are in
`templates/fixtures/*.json` (fixture key order, two-space indent); the registry's golden tests must reproduce them byte for
byte from the stored parameters, with the fixture's synthetic claimant `0x…c1a1` and the fixture's synthetic consumer
`0x000000000000000000000000000000000000c0de` (the test deploys the registry at that address with forge-std's
`deployCodeTo` and pins `vm.chainId(1)`; in production the consumer is `address(this)` on the deployment chain). A template that fails a later check is fixed in this
file first.

**Byte-exact rule.** The text below, with every placeholder replaced, must equal the fixture files under
`templates/fixtures/` byte for byte on chain 1 (minus the file's trailing newline, which is not part of the body).
On another deployment chain only `consumer.chainId` changes; the question text, definitions, windows and top-level
`chainId: 1` stay the same for the same spec and claimant. In the
texts, backticks around a placeholder are markdown and are NOT emitted, with ONE exception: the event or function
item (`<EVENT>`, `<FN>`) is wrapped in literal backticks in the body, exactly as the fixtures show
(`` count the `event HourSaved(...)` events ``). Nothing else carries backticks. The composer emits the fixture's
`definitions` keys exactly (T1: `method`, `window`; T2: `method`, `units`, `window`; T3: `method`; T4: `method`;
T5: `method`, `true`, `false`, `window`), and every body carries the `consumer` key of the request-body table.

Placeholders: `<A>` claimant address (lowercase hex), `<C>` target contract (lowercase), `<EVENT>` the human-readable
event item, `<ARG>` the indexed argument that must equal `<A>`, `<FARG>`/`<FVAL>` an optional second indexed
argument and its decimal value, `<SUMARG>` the argument to sum, `<N>` the threshold (decimal), `<NH>` the same threshold as lowercase `0x` hex (`20` -> `0x14`), `<FROM>`/`<TO>` the
window in hex, `<FN>` a `function name(address) view returns (uint256)` item, `<OP>` one of `>=`, `>`, `<=`, `<`,
`==`. Every text is ASCII; names from specs are restricted to `[A-Za-z0-9 .-]`.

### T1 log-count, personal (`evidence: chain`, `answerType: uint256`)

> question: "Within the request's pinned block window (fromBlock `<FROM>` to toBlock `<TO>`, both inclusive) on
> Ethereum mainnet, count the `<EVENT>` events emitted by the contract `<C>` whose indexed `<ARG>` argument equals
> `<A>`[ and whose indexed `<FARG>` argument equals `<FVAL>`]. Answer the count as one integer; answer 0 if no such
> event exists."
>
> definitions.method: "eth_getLogs on the contract with topic0 = the event's signature hash and the indexed argument(s)
> as topics, over exactly the pinned window; or the equivalent explorer log query. Count matching logs; do not
> deduplicate by transaction. Block numbers are hex."
> definitions.window: "The pinned window is the whole evidence; events outside it do not count."

Spec fields: `<C>`, `<EVENT>`, `<ARG>`, optional `<FARG>`+`<FVAL>`, `<N>`, window. v1 traits 701, 801, 901, 1001,
1101 to 1105 use it with the Curator's events above and `<N>` = 1.

### T2 log-sum, personal (`evidence: chain`, `answerType: uint256`)

> question: "Within the request's pinned block window (fromBlock `<FROM>` to toBlock `<TO>`, both inclusive) on
> Ethereum mainnet, sum the `<SUMARG>` argument of the `<EVENT>` events emitted by the contract `<C>` whose indexed
> `<ARG>` argument equals `<A>`[ and whose indexed `<FARG>` argument equals `<FVAL>`]. Answer the sum as one integer
> in the argument's raw units (no decimals applied); answer 0 if no such event exists."
>
> definitions.method: "eth_getLogs on the contract with topic0 = the event's signature hash and the indexed argument(s)
> as topics, over exactly the pinned window; or the equivalent explorer log query. Sum the named argument of matching
> logs; do not deduplicate by transaction. Block numbers are hex."
> definitions.units: "Raw integer units of the argument as emitted, e.g. wei for an ETH amount."
> definitions.window: as T1.
>
> Fixture: `templates/fixtures/T2-log-sum-composed.json` (composed from this template; checked and quoted 2026-10-12).

Spec fields: as T1 plus `<SUMARG>`. No v1 trait uses it; wave-two families (degen volume, whale receiver by sum) do.

### T3 log-rank, shared fact (`evidence: chain`, `answerType: address[]`, `head <= 32`)

> question: "Within the request's pinned block window (fromBlock `<FROM>` to toBlock `<TO>`, both inclusive) on
> Ethereum mainnet, sum the `<SUMARG>` argument of the `<EVENT>` events emitted by the contract `<C>` grouped by the
> indexed `<ARG>` argument. Return the `<N>` keys with the largest sums, descending by sum, ties by address ascending
> (lowercase hex)."
>
> definitions.method: "eth_getLogs over exactly the pinned window, group by the indexed argument, sum in raw units,
> sort as stated; include a few positions beyond `<N>`; agreement is on the first `<N>`."

Spec fields: `<C>`, `<EVENT>`, `<ARG>` (groupBy), `<SUMARG>`, `<N>` (head, at most 32), window. v1 trait 1201 uses it:
`Deposited`, groupBy `contributor`, sum `weightAdded`, head 32, `W_LIFE`.

**Measured on mainnet (2026-10-18, three paid attempts of the 1201 question at panel 5 / quorum 3) and the wording
for v2 and for community specs.** Attempts one and two (`cb72b826`, `4ee4290d`) ended with two right and two wrong
answers each: the wrong ones, byte-identical across two seats and both attempts, listed 32 *amount words*
(`0x…016345785d8a0000` = 0.1 ETH) instead of contributors, so the seats' `log-rank` recipe had grouped the logs by a
data field although its declared `groupBy` was `contributor`; a third wrong answer came from a truncated
`eth_getLogs`. The third attempt (`03ccc51e`), whose `definitions.method` spelled the sort and tie rule out, was
answered right by all four seats within 15 s. The negative case is kept in
`templates/fixtures/negative/1201-grouped-by-data-field.json`. The v1 text above is composed on-chain by
`Composer.canonical` and cannot change; **v2 and every community spec written by hand use this wording instead:**

> question: "… grouped by the **indexed `<ARG>` argument (topic `<K>` of the log), never by a data field** …"
>
> definitions.method: "eth_getLogs over exactly the pinned window; group by the indexed `<ARG>` argument (the log's
> topic `<K>`, an address: left-pad 12 zero bytes), never by a data word; sum `<SUMARG>` in raw units; sort descending
> by sum and break ties by lowercase address ascending; include positions beyond `<N>`, agreement is on the first
> `<N>`. An entry that is not an address (12 leading zero bytes) is a wrong answer."

`<K>` is the argument's position among the event's **indexed** parameters, 1-based, read from the `item` signature:
`contributor` in `Deposited(address indexed contributor, …)` is topic 1 (the 1201 text), `to` in
`Transfer(address indexed from, address indexed to, uint256 value)` is topic 2. v2's Composer derives it (V2.md item
18, after the cross audit of 2026-10-19 found a fixed "topic 1" wrong for a second indexed address); the grouping key
must be an `address`-typed indexed parameter, and the event must be **non-anonymous**: an anonymous event carries no
signature hash in topic 0, so its indexed arguments start at topic 0 and `<K>` would name the wrong one. v2's
`validateSpec` rejects a kind-3 `item` that ends in `anonymous` with `BadSpec("item")` (recheck 2026-10-20, R-M1);
`<K>` counts indexed parameters of every type, not only addresses.

Historically, 5 / 3 often needed multiple paid attempts; the current Composer uses the larger kind-3 panel of 11 / 7 (`INTEGRATION.md` section 4 says what the consumer checks).

### T4 call-compare (`evidence: chain`, `answerType: bool`)

> question: "At the last block of the request's pinned window (toBlock `<TO>`) on Ethereum mainnet, does the view
> function `<FN>` of the contract `<C>` return a value `<OP>` `<N>` for the address `<A>`? Answer true or false."
>
> definitions.method: "One eth_call of the function with `<A>` as the argument at block `<TO>` (hex, not 'latest') on an
> endpoint with historical state; compare the raw integer return value with `<N>` using `<OP>`. A null, pruned or
> 'latest' read is no evidence."
>
> Fixture: `templates/fixtures/T4-call-compare-reference.json` (`pointsOf`, `>=`, 1000, `W_LIFE`).

Spec fields: `<C>`, `<FN>` (one address argument, one uint256 return), `<OP>`, `<N>`, window (its last block is the
state read). No v1 trait uses it (the registry reads the Curator's views directly); wave-two bagholder and
diamond-hands facts do.

### T5 panel nonce (`evidence: panel`, `answerType: bool`, panel 11 / quorum 7)

A question about the **account nonce** in the chain state at one block, read with `eth_getTransactionCount`; the
parameters are `<A>`, the block `<B>` (decimal), its hex `<BH>`, its hash `<HASH>`, `<N>` and `<NH>`; the window is
the single block `<B>`. Round 2 removed the explorer transaction-list alternative and the "sent at least N
transactions" paraphrase: a contract's nonce counts its own `CREATE`s, so the two methods can answer differently for
the same claimant, and a panel that mixes them disagrees. The predicate is the nonce, nothing else.

> question: "At Ethereum mainnet block `<B>` (hex `<BH>`, block hash `<HASH>`; the block in which the WhitelistCurator
> contract 0xcb0b0531e86a9ac36fa865ca8e3dbccf047fda91 was deployed), was the account nonce of address `<A>`, as
> returned by eth_getTransactionCount at that block, at least `<N>`? This asks about the account's nonce in the chain
> state at that block, not about its transaction history."
>
> definitions.method: "Call eth_getTransactionCount(`<A>`, `<BH>`) (hex block, not 'latest') on an endpoint with
> historical state, e.g. https://rpc.mevblocker.io or https://eth.drpc.org; cite endpoint and call. Pruned or
> unavailable state, errors or null (flashbots, 1rpc, cloudflare, publicnode) are no evidence: use another endpoint
> with historical state. Explorer transaction lists are not the nonce and are not evidence."
> definitions.true: "true only if an endpoint with historical state returns a transaction count at block `<BH>` of at
> least `<N>` (`<NH>`)."
> definitions.false: "false only if an endpoint with historical state returns a count at block `<BH>` below `<N>`
> (`<NH>`). If you could not read the historical count, write no answer; never answer false from a pruned, null or
> 'latest' read."
> definitions.window: "The window is the single block `<B>`; it fixes which chain state to read. It is not a time
> range, and the current (latest) nonce is not the answer."

v1 trait 1301: `<B>` 25769870, `<BH>` 0x189378e, `<HASH>` as in `CATALOG.md` section 1, `<N>` 20, `<NH>` 0x14; fixture
`templates/fixtures/1301-not-born-yesterday.json`. **Community T5 specs** use the same text with one verbatim change in
the question's parenthesis: `(hex <BH>, block hash <HASH>; the block in which the WhitelistCurator contract
0xcb0b0531e86a9ac36fa865ca8e3dbccf047fda91 was deployed)` becomes `(hex <BH>; the last block of the spec's window)`;
`<B>` is the spec's `toBlock` (equal to its `fromBlock`); the definitions are unchanged. Fixture:
`templates/fixtures/T5-community-composed.json`. A contract cannot read the hash of a block older than 256 blocks; the
plane pins `toBlockHash` itself.

## The request body

Every question is one JSON object, UTF-8, sent as the `body` of `Intake.request` (`INTEGRATION.md`). Keys and
their fixed values:

| key | value |
|---|---|
| `v` | 1 |
| `question` | the composed text, at most 1,000 characters |
| `chainId` | 1 |
| `window` | `{"fromBlock": <int>, "toBlock": <int>}` (decimal integers in JSON; hex in the text) |
| `answerType` | `uint256`, `address[]` or `bool` as the template says |
| `evidence` | `chain` (T1 to T4) or `panel` (T5/T6) |
| `panelSize`, `quorum` | 5, 3 for T1/T2/T4; 11, 7 for T3/T5/T6 |
| `validForSeconds` | 2592000 |
| `head` | T3 only: the list length the registry reads, at most 32 |
| `definitions` | an object of ASCII strings, each at most 512 characters, keys as each template lists |
| `consumer` | `{"chainId": <deployment chainId>, "verifyingContract": "<the registry's address, lowercase hex>"}`: the EIP-712 domain the attester signs for (`INTEGRATION.md` section 4); `block.chainid`, emitted as decimal by `Strings.toString` (11155111 on Sepolia); fixtures retain chain 1 and `0x000000000000000000000000000000000000c0de` |

The plane pins `toBlockHash` itself when it admits the request; the registry never puts a block hash in a body
except the constant one in trait 1301. Serialisation for the golden tests: fixture key order, two-space indent, as in
the fixtures. (Body key order is fixed for byte comparisons; the canonical hash document always sorts keys separately.)

**The plane's `questionHash`** of a body is `keccak256` of the body reduced to `v`, `chainId`, `question`,
`definitions`, `answerType`, `window` (`fromBlock` and `toBlock` only), plus `head` when present and `evidence` only
when it is `panel`, serialised as RFC 8785 canonical JSON (sorted keys, no whitespace). The registry computes it when
it composes a body and the callback compares it with the attestation (`INTEGRATION.md` section 4, check 7);
`reference/plane/questionHashes.json` holds the plane's value and the canonical document for every fixture.
`consumer` is excluded, so changing its chain does not change the canonical question hash. Composer's `compose`
and internal `encodeBody` are views; the external selector of `compose` is unchanged.

## T6 operator (catalog 601, Swarmed)

Catalog-only, evidence `panel`, 11 members / quorum 7, bool, validity 30 days. The window starts at block 25,090,085 and ends at the request block minus 64. The Registry stores that exact window in the pending record and in the accepted fact. A false answer clears the pair for another paid request after more jobs.

The fixture in `templates/fixtures/T6-operator-reference.json` uses claimant `0x000000000000000000000000000000000000c1a1` and last block 26,237,654. Its independent canonical hash is in the adjacent `T6-operator-hash.txt`. Substitute the claimant in lowercase hex and the end block in decimal:

Up to block 26237654 on Ethereum mainnet, did the wallet 0x000000000000000000000000000000000000c1a1 operate an IdentityMD seat through at least 3 accepted Identity.md swarm jobs while it held that seat? Answer true or false.

**method**: Four steps, executed in order as one procedure: seats (step 1), agent (step 2), accepted (step 3), answer (step 4). Every read is of Ethereum mainnet archive logs and state up to block 26237654 inclusive. A pruned, null or partial log read, or an endpoint without the window, is no evidence: write no answer, never false.

**seats**: Step 1, seats. Every Transfer(from, to, tokenId; all indexed) log of the IdentityMD collection 0x0000eC93127BAA929E58E97dd0095A2BFb38ec1D from block 25090085 to 26237654 whose from or to is 0x000000000000000000000000000000000000c1a1. Per tokenId, a holding interval runs from the block of a transfer to the wallet (inclusive) to the block of the next transfer of that token away from it (exclusive); an interval still open at 26237654 ends at 26237654 inclusive. Same-block transfers are ordered by log index.

**agent**: Step 2, the agents of a seat. The AgentBound(uint256 indexed agentId, uint8 indexed standard, address indexed tokenContract, uint256 tokenId, address registeredBy) logs of the adapter 0xde152AfB7db5373F34876E1499fbD893A82dD336 with tokenContract equal to the collection and tokenId equal to the seat. An agent is bound to the seat from the block of its AgentBound log on. A seat without a binding has no agent and counts nothing.

**accepted**: Step 3, accepted jobs. The NewFeedback logs (topic 0 0x6a4a61743519c9d648a14e6493f47dbe3ff1aa29e7785c96c8326a205e58febc) of the reputation registry 0x8004baa17c55a88189ae136b182e5fda19de9b63 whose topic 2 is the batcher 0xb6d0a187b050fa5bb0b87033a203f37becf4a775, whose second data word (bytes 32 to 63) equals 1, whose block lies inside one of the wallet's holding intervals of a seat, and whose topic 1 is an agent bound to that seat at or before the log's block. Each such log is one entry.

**answer**: Step 4, the answer. true when the entries of step 3, summed over every seat the wallet held, number at least 3; false otherwise. Count entries, not distinct jobs; a log whose second data word is not 1 counts nothing.

**true**: true only if complete historical log reads establish at least 3 entries under the method.

**false**: false only if complete historical log reads establish fewer than 3 entries under the method. If a read is pruned, null, partial or unavailable, write no answer; never answer false from an incomplete read.

**window**: The window is blocks 25090085 to 26237654 inclusive on Ethereum mainnet; it fixes which logs and chain state count. The current head is not the window.

The fact belongs to each wallet's own holding intervals, not to a seat forever. Any agent binding at or before the entry counts; later bindings do not erase earlier work. Count feedback entries rather than distinct jobs. Pruned or incomplete historical reads produce no answer. The approved six-wallet lab run of 2026-10-21 is the acceptance evidence; no new lab request is part of this build.

### Composer boundaries

The public composition views trust their arguments and do not validate arbitrary specs; Registry passes only pinned dependencies and stored, validated specs. In T4, `fromBlock` remains in the canonical hash although the call occurs at `toBlock`; duplicate registrations cost only their registrant. T3's “positions beyond head” describes the panel's working; the accepted list has exactly head entries. Catalog windows are fixed historical anchors and do not undergo community registration's minimum-span guard.

The readable static text table is `templates/composer-text.json`; `python3 tools/gen_composer_text.py --check` verifies its lossless packed representation and every offset in Composer. T1–T5 fixtures stay byte-identical.
