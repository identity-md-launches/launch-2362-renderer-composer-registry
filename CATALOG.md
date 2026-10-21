# CATALOG.md: Sworn wallet facts

This file binds the code. Ids, rules, windows and acceptance rules do not change; the display names in section 7
were filled in by the owner on 2026-10-16 (product **Sworn**, symbol **SWORN**). Read `README.md` first, `TEMPLATES.md` for the question bodies and `INTEGRATION.md`
for the Intake and the attestation.

**Words.** *The registry* is the ERC-721 contract, *the card* is a wallet's token, a *trait* is one per-wallet fact
(`traitId`, `hasTrait`). *Claimant* is the wallet that minted the card and that every trait is about; *holder* is
`ownerOf`.

## 1. Measured anchors (Ethereum mainnet, read 2026-10-11)

The Curator computes `hour = (block.timestamp - launchTime) / hourDuration` with `launchTime` 1,786,910,327 and
`hourDuration` 3,600; `firstJudgedHour` is 24. The first block of hour h is the first block whose timestamp is at
least `launchTime + h * 3600`. The headers of the six boundary blocks (number, hash, parent, timestamp) are vendored
in `reference/anchors/headers.json`; their timestamps give hours 0, 3, 24, 64, 65 and 65 exactly as this table says.

| anchor | block | hex | note |
|---|---|---|---|
| Curator deploy block (`B_DEPLOY`) | 25,769,870 | `0x189378e` | block hash `0x43ac0aadac9b134a5e4555d28323431664fd77d74cd6a28cb4ca65e34ba72256`; also the launch block; timestamp = `launchTime` |
| first `Deposited` | 25,769,888 | `0x18937a0` | `FirstDeposit` index 1 |
| `FirstDeposit` index 999 | 25,770,891 | `0x1893b8b` | |
| `FirstDeposit` index 1000 (`B_FIRST1000`) | 25,770,897 | `0x1893b91` | block hash `0x8123c122611f3d121e0bd63123243aff8684a340f5f82344044018b855213633`; indices are 1-based: 1 to 19,522 |
| `FirstDeposit` index 10000 | 25,774,866 | `0x1894b12` | |
| hour 24 first block (`B_H24`) | 25,777,045 | `0x1895395` | block hash `0xe67985572955ccc9a8b50f21248d8bd99127eb379e2cb4af3dd466d208b302c9`; first judged hour; first hour-24 deposit at 25,777,046 |
| hour 64 first block | 25,789,008 | `0x1898250` | |
| `FirstDeposit` index 19522 | 25,789,040 | `0x1898270` | the last new contributor |
| hour 65 first block | 25,789,306 | `0x189837a` | |
| last `Deposited` (the hour-65 deposit) | 25,789,576 | `0x1898488` | |
| hour 65 last block (`B_END`) | 25,789,604 | `0x18984a4` | block hash `0x57852dbfd56daf8e7b4bf68c2e25f73dd583f99eac5b00c03a50603e4a2cef37`; hour 66 starts at 25,789,605 (`0x18984a5`); `isSettled()` is true from there |
| `Settled` event | 25,789,721 | | hour 66; not a window bound |

Populations, **externally measured** (an `eth_getLogs` census over the windows on 2026-10-11, not vendored; the
method is in `reference/PROVENANCE.md`): hours 24 to 65 hold 5,958 deposits by 3,936 distinct contributors (no hour
below 24 in that window); hour 24 alone 131 deposits by 51 contributors; hour 64 8 deposits by 7; hour 65 1 by 1;
`HourSaved` 41 events by 33 distinct saviors, one or more per hour from 24 to 64; 28,353 deposits in all. The IDMD
collection answers `balanceOf(address)` (a known holder: 1). The eligible counts in section 3 come from that census;
the registry never stores them.

### Canonical windows (constants in the registry; the claimant chooses nothing)

| window | fromBlock | toBlock | blocks | used by |
|---|---|---|---|---|
| `W_LIFE` | `0x189378e` | `0x18984a4` | 19,735 | 801, 901, 1001, 1101 to 1104, 1201 |
| `W_JUDGED` | `0x1895395` | `0x18984a4` | 12,560 | 701 |
| `W_FIRST1000` | `0x189378e` | `0x1893b91` | 1,028 | 1105 |
| `W_DEPLOY` | `0x189378e` | `0x189378e` | 1 | 1301 (single block, panel) |

`W_LIFE` ends at the last block of hour 65, not at the `Settled` block. Free RPCs that served `eth_getLogs` for this
range on 2026-10-11: `rpc.mevblocker.io` in chunks of at most 1,500 blocks, `1.rpc.thirdweb.com` in chunks of 1,000;
drpc's free plan refuses `eth_getLogs`, publicnode calls it an archive request. The plane pinned every one of these
windows unchanged in the free quotes of 2026-10-12 (`reference/plane/quotes/`).

## 2. Ids and tiers

- `traitId` is a `uint16`: **id = family x 100 + tier**. 101 is family 1, tier 1. Community specs (section 5) take ids
  from **10001** upward in registration order.
- **Tiers are monotone.** `hasTrait(A, id)` is true for every tier at or below the wallet's level (a wallet with ten
  deposits has 301, 302 and 303; an hour-0 wallet has 201 and 202). The card shows only the highest tier per family.
  Allowlists may gate on any tier.
- Direct-read families (1 to 5) read the settled Curator for wallets without a card and are frozen at mint for card claimants.
- Oracle families (6 to 13) are stored per `(claimant, traitId)` after a verified attestation.

## 3. Trait table (25 slots)

| id | working name | class | source and rule (A = claimant) | window | eligible |
|---|---|---|---|---|---|
| 101 | Contributor | direct | `firstHourOf(A).hasJoined` | live | 19,522 |
| 201 | Early bird, hour <= 1 | direct | `hasJoined && hour <= 1` | live | 516 |
| 202 | Early bird, hour 0 | direct | `hasJoined && hour == 0` | live | 96 |
| 301 / 302 / 303 | Climber >= 3 / 5 / 10 | direct | `txCountOf(A) >= 3 / 5 / 10` | live | from the view; at most 2,037 wallets made more than one deposit |
| 401 / 402 / 403 / 404 | Capital >= 1 / 10 / 100 / 800 ETH | direct | `contributedBy(A) >= 1e18 / 1e19 / 1e20 / 8e20` (the view returns `contributors(A).highWater`, the largest single send in wei) | live | snapshot of 15,576 wallets: median 0.45 ETH, p90 14, p99 98.8, max 1,000 (the cap) |
| 501 / 502 / 503 | Scoreboard >= 1,000 / 3,162 / 10,000 | direct | `pointsOf(A) >= 1000 / 3162 / 10000` (points = 1000 x sqrt(weight in ETH)) | live | from the view |
| 601 | Swarmed | panel, T6 bool | operated an IdentityMD seat through at least 3 accepted Identity.md swarm jobs while holding it | living: 25,090,085 to the request block minus 64 | about 850 qualifying agents (847 measured on 2026-10-21) |
| 701 | Still here | chain, T1 log-count >= 1 | `Deposited` with `contributor` = A | `W_JUDGED` | 3,936 |
| 801 | Last stand | chain, T1 log-count >= 1 | `Deposited` with `contributor` = A and `hour` = 64 | `W_LIFE` | 7 |
| 901 | The last one in | chain, T1 log-count >= 1 | `Deposited` with `contributor` = A and `hour` = 65 | `W_LIFE` | 1 |
| 1001 | Hour savior | chain, T1 log-count >= 1 | `HourSaved` with `savior` = A | `W_LIFE` | 33 |
| 1101 / 1102 / 1103 / 1104 | Ordinal #1 / #1000 / #10000 / #19522 | chain, T1 log-count >= 1 | `FirstDeposit` with `contributor` = A and `index` = 1 / 1000 / 10000 / 19522 | `W_LIFE` | 1 each |
| 1105 | First thousand | chain, T1 log-count >= 1 | `FirstDeposit` with `contributor` = A | `W_FIRST1000` | exactly 1,000: block 25,770,897 holds only index 1000 (measured) |
| 1201 | Top 32 | shared, T3 log-rank head 32 | top 32 `contributor`s by summed `weightAdded` in `Deposited`; one attestation serves all 32 | `W_LIFE` | 32 |
| 1301 | Not born yesterday | panel, T5 bool | account nonce `eth_getTransactionCount(A, 0x189378e) >= 20` | `W_DEPLOY` | 4,765 contributors had nonce >= 20 at the launch block (sybil census) |

The ordinal family is not monotone (each id is a different wallet); 1105 is a window fact, not a tier of 1101 to
1104. The card slot and Ordinal attribute show the **lowest verified id** (1101 is rarest), not the highest.
The Early bird family is monotone in the direction of rarity: every hour-0 wallet (202) is also an hour <= 1
wallet (201), and the card shows 202 when both hold. 1301 is a statement about the account's nonce in the chain state
at the launch block; for a contract claimant that nonce counts its own `CREATE`s, which is the predicate, not a flaw.
Not in the catalog by decision: the wallet that called `settle()` (it belongs to the entrant; no back door).

Event signatures as the recipes need them (human-readable ABI items, exactly these strings):

- `event Deposited(address indexed contributor, uint256 indexed hour, uint256 amount, uint256 creditedDelta, uint256 weightAdded, uint256 newWeight, uint256 txCount, uint256 hourTotal, uint256 earlyBps)`
- `event FirstDeposit(address indexed contributor, uint256 indexed index, uint256 timestamp)`
- `event HourSaved(address indexed savior, uint256 indexed hour, uint256 hourTotal)`

Curator: `0xcb0b0531e86a9ac36fa865ca8e3dbccf047fda91` (lowercase in every question; the plane compares strings).

**Trap in the Curator's raw getter:** `contributors(address)` returns `(uint96 highWater, uint96 weight, uint32 txCount,
uint32 firstHour)` where `firstHour` is stored **plus one** (0 = never deposited). Read hours only through
`firstHourOf(address) returns (uint256 hour, bool hasJoined)` and check `hasJoined`; a non-member read naively looks
like an hour-0 founder. Capital reads `contributedBy(A)`, never the struct.

## 4. What the callback accepts, per class

The registry stores `pending[requestId] = (claimant, traitId, requestedAt, questionHash, fromBlock, toBlock)` when it sends a question
and, in `onResult(requestId, attestation, signature)`, verifies in this order: `msg.sender` is the Intake and
`requestId` is pending; signature length == 65 (reason 2); answer length <= 2112 and exactly 32 for bool/uint256
kinds (reason 9), before any dynamic copy or hash; `chainId` == 1; signer == attester
(`0x5598aa9146215bc13eb26f2c692ad1461fd32982`, constructor argument) under the domain with
`verifyingContract` == the registry and domain `chainId` == the deployment chain; `answerType` (uint8) == the template's code;
`agreed >= quorum >= the template's quorum` and `panelSize >= the template's`; window == the pending request's window;
bounded dates (issued between request time and request time plus one day, validity at most 30 days); **`questionHash` == the hash the registry computed when it composed the body**; and the answer against the
rule below (decoded defensively: `INTEGRATION.md` section 4). The attestation's `requestId` is the plane's own id and
is stored, not compared. A miss is recorded (`Missed(requestId, traitId, reason)` with the reason codes of
`INTEGRATION.md` section 4), clears the pending pair and never reverts; a refusal or a panel without a verdict arrives
through `onFailure` and is recorded as `NoVerdict`.

| template | answerType | rule that marks the trait |
|---|---|---|
| T1 log-count | `uint256` (code 3) | `value >= threshold` (1 for every v1 trait) |
| T2 log-sum | `uint256` (code 3) | `value >= threshold` |
| T3 log-rank (shared fact) | `address[]` (code 4) | canonical `abi.encode(address[])`, exactly `head` entries (1 to 32), clean address words; store its hash and count. `applySharedFact` checks the exact hash and membership. A truncated list is a miss. |
| T4 call-compare | `bool` (code 0) | `value == true` |
| T5 panel nonce | `bool` (code 0) | `value == true` |
| T6 operator (catalog 601 only) | `bool` (code 0) | `value == true`; accepted window stored permanently |

Oracle defaults: kinds 1, 2 and 4 use `panelSize` 5, `quorum` 3 (the deployer reruns the recipe before signing, so the
panel only has to agree on a recipe); kinds 3, 5 and 6 use `panelSize` 11, `quorum` 7 (as in both pilots);
`validForSeconds` 2,592,000 (30 days); `chainId` 1; T1–T5 use hex block tags where their recipe requires them; T6 uses decimal block numbers; `head` 32 for T3. A `disagreed`,
`not_answerable` or refused request reaches `onFailure` (Intake v2) and is "no verdict", never false; a request the
plane never completes is released by `abandon(requestId)` after 31 days (`block.timestamp`, from the request's
stored `requestedAt`): strictly later than `requestedAt + 31 days`, a personal request by its claimant only and a shared fact by anyone. The price paid is spent either way. At equality, a last-second valid delivery remains possible and abandonment is too early. The callback clears pending state before checking the answer; misses release the pair for a paid retry.

## Templates

The six question templates, their placeholders and the checked example bodies are in `TEMPLATES.md`; every oracle
trait in section 3 names its template there (T1, T3, T5, T6).

## 5. Spec registration (community traits)

`registerSpec(Spec, expectedId)` by anyone, 6.4 IMD, returns the new id (10001 upward), emits
`SpecRegistered(id, registrant)`. The spec is immutable. Use expectedId = 0 for no ordering assertion, or the observed next id to reject a race. Fees are forwarded to the BurnExecutor V2 for bridging and burning on Base. Fields:

| field | type | guard |
|---|---|---|
| `kind` | uint8: 1 T1, 2 T2, 3 T3, 4 T4, 5 T5 | one of the five |
| `target` | address | nonzero for T1 to T4; must be zero for T5 (`validateSpec` reverts `BadSpec("target")` otherwise, as the struct comment says) |
| `item` | string | at most 256 bytes; closed event/function grammar below |
| `arg` | string | must name an actual indexed address field of `item` (T1, T2 claimant; T3 grouping); identifier at most 32 bytes |
| `fixedArg`, `fixedVal` | string, uint256 | optional second filter that must name an actual indexed field of `item` (T1, T2); empty string = none and requires `fixedVal == 0` (`BadSpec` otherwise) |
| `sumArg` | string | T2 and T3 only; must name a real field of `item` |
| `op` | uint8 | T4 only: 1 `>=`, 2 `>`, 3 `<=`, 4 `<`, 5 `==` |
| `threshold` | uint256 | T1, T2, T4, T5: `>= 1`; T3: head, 1 to 32 |
| `fromBlock`, `toBlock` | uint64 | `fromBlock <= toBlock`, `toBlock - fromBlock + 1 >= 7200` and `toBlock <= H - 64` at registration (T5: `fromBlock == toBlock`, and `toBlock + 7200 <= H`); mainnet height `H` is `block.number` on chain 1, otherwise `Composer.mainnetHeightBound()` (the timestamp-derived upper bound and its caveat are documented in README and INTEGRATION) |
| `name` | string | ASCII `[A-Za-z0-9 .-]`, 1 to 32 bytes; escaped by the renderer like every other spec string |
| `evidence` | derived | chain for kinds 1 to 4, panel for 5 |

The Solidity shape (field order is the ABI; there is no `evidence` field, it is derived from `kind`):

```solidity
struct Spec {
    uint8   kind;        // 1 T1 log-count, 2 T2 log-sum, 3 T3 log-rank (shared), 4 T4 call-compare, 5 T5 panel nonce
    address target;      // T1 to T4; zero for T5
    string  item;        // event or function item; closed grammar below; <= 256 bytes
    string  arg;         // [A-Za-z0-9_], 1..32 bytes; T1/T2 the claimant argument, T3 the groupBy key; empty for T4/T5
    string  fixedArg;    // [A-Za-z0-9_], 0..32 bytes; empty = no second filter (T1/T2 only)
    uint256 fixedVal;
    string  sumArg;      // [A-Za-z0-9_], T2/T3 only, else empty
    uint8   op;          // T4 only: 1 >=, 2 >, 3 <=, 4 <, 5 ==; else 0
    uint256 threshold;   // T1/T2/T4/T5 >= 1; T3: head 1..32
    uint64  fromBlock;
    uint64  toBlock;
    string  name;        // [A-Za-z0-9 .-], 1..32 bytes
}
```

The class of a spec follows its kind: kinds 1, 2 and 4 are chain, kind 3 is shared, kind 5 is panel (the former
`traitClass` view was removed for the launch size budget; `specOf(id).kind` says it).
`upgrade` rejects T3 spec ids (shared facts go through `requestSharedFact`/`applySharedFact`, which accept any T3 id).
The Renderer escapes display names. The Composer accepts no prose outside the following signature grammar:

- Event: `event Name(type name, type indexed name, …)` with exactly single spaces and comma-space separators, nothing before `event ` or after `)`. No `anonymous`.
- Function: exactly `function name(address) view returns (uint256)`.
- Names are `[A-Za-z_][A-Za-z0-9_]*`, at most 32 bytes.
- Types: `address`, `bool`, `string`, `bytes`, `bytes1` through `bytes32`, `uint8` through `uint256` and `int8` through `int256` in steps of eight, each optionally followed by `[]`. No tuples, arbitrary type names or fixed arrays.

On chain 1 `validateSpec` ignores its `blockNumber` argument and reads `block.number`. Off mainnet the timestamp-derived `mainnetHeightBound()` applies; it can exceed the actual mainnet head after skipped slots, so clients must check mainnet before spending. Frozen catalog anchors are exempt from the 7,200-block community minimum. Kind 6 cannot be registered by the community.

The composed body is a deterministic function of the spec and the claimant (golden tests per kind, fixtures in
`templates/fixtures/`); the validated spec grammar and fixed templates bound every `definitions` entry to at most 512 characters and the question to at most 1,000; maximal-spec tests verify these limits. A spec whose body is refused by the plane keeps its fee, and its registrant or claimants pay
every request about it: junk specs burden only whoever pays for junk. Sequential ids are a public ordering, not a
reservation: a client reads the id from `SpecRegistered` or the return value, never predicts it.

`nextSpecId` is a `uint16` starting at 10001, so at most 55,534 community specs (ids 10001 to 65534) can ever be
registered; once the counter is exhausted `registerSpec` reverts for ever. Catalog ids and existing specs are
unaffected.

## 6. Sharing and fees

`mintCard()` costs 0.1 IMD, once per wallet. `registerSpec` costs 6.4 IMD. Fees are forwarded to the BurnExecutor V2 for bridging and burning on Base.
`upgrade(traitIds, maxPrice)` pays the Intake once per requested personal fact. `requestSharedFact(factId, maxPrice)` pays once for the whole shared answer, while `applySharedFact(factId, list)` costs gas only. An Intake price above maxPrice reverts atomically. Shared facts have one pending request and one accepted answer each. Personal pairs have one pending request and one permanent accepted fact each. No ETH is accepted by these functions; no owner, pause or upgrade exists.

## 7. Name table

| id | working name | final name |
|---|---|---|
| 101 | Contributor | Spawned |
| 201, 202 | Early bird | Zero-Shot (`Zero-Shot, hour <= 1`, `Zero-Shot, hour 0`) |
| 301 to 303 | Climber | Hopper (`Hopper >= 3 / 5 / 10`) |
| 401 to 404 | Capital | Bullfrog (`Bullfrog >= 1 / 10 / 100 / 800 ETH`) |
| 501 to 503 | Scoreboard | Benchmarked (`Benchmarked >= 1000 / 3162 / 10000`) |
| 601 | Operator | Swarmed |
| 701 | Still here | Uptime |
| 801 | Last stand | Holdout |
| 901 | The last one in | Final Token |
| 1001 | Hour savior | Hotfix |
| 1101 to 1105 | Ordinal | PID (`PID #1 / #1000 / #10000 / #19522`; 1105 keeps `First thousand`) |
| 1201 | Top 32 | Top Weights |
| 1301 | Not born yesterday | Pretrained |
| product, symbol, X handle | the registry | Sworn, SWORN, (handle not given) |

The final names are the `traitName` table of `Composer`, the `name` of every catalog `Spec` (`catalogSpec`), the
`FAMILIES` of `tools/gen_template.py` (the thirteen family `trait_type`s of the metadata and the card's labels) and
the collection strings `ERC721("Sworn", "SWORN")` with metadata names `Sworn #<tokenId>`. The rename (2026-10-16)
replaced this table and the collection strings; it touched no rule, id or window. Section 3 keeps the working names
in its first column as the historical key; the id is the identity.

## 8. Operational assumptions

Facts attest the claimant, never the current card holder. An oracle answer is permanent once accepted. Its expiry bounds admission, not the stored fact's lifetime. Swarmed attributes entries to the wallet's own seat-holding intervals; former holders and later holders can each qualify independently. Missing archive evidence means no answer, never false. The single fixed attester, Intake and archive recipe dependencies are detailed in DISCLOSURE.md. A request that misses or never arrives receives no refund.
