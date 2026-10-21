# INTEGRATION.md: the Intake, the attestation, the external contracts

The registry is Sworn (`ERC721("Sworn", "SWORN")`). Everything the registry talks to, as measured on Ethereum mainnet on 2026-10-10 to 2026-10-12. Sources are vendored
under `reference/` (see `reference/PROVENANCE.md`). Where this file and a skill disagree, re-read the verified
source in `reference/IntakeV2.sol`; it is the contract that runs.

**Round 2 (2026-10-12) changed this file in five places**, each from a measurement, each with its evidence vendored:
the plane moved to Intake v2 (section 1); the attestation's signed `requestId` is the plane's own id, not the Intake's
(section 4, check 1); the domain's `verifyingContract` is the body's `consumer` field (section 4); the plane's
`questionHash` is a keccak of a canonical JSON document the registry can recompute, which is now the binding between
a pending request and its attestation (section 4, check 7); and Intake v2's failure hook delivers refusals and failed
panels (section 3).

## 1. Addresses (Ethereum mainnet, chainId 1)

| what | address |
|---|---|
| WhitelistCurator (THE LIST) | `0xcB0b0531e86A9aC36Fa865cA8e3dbccF047FDA91` |
| IdentityMD collection (IDMD, ERC-721, 2,000 tokens) | `0x0000eC93127BAA929E58E97dd0095A2BFb38ec1D` |
| IMD token (ERC-20, 18 decimals, a LayerZero OFT, **no `permit`**) | `0xD34a99Bc0f67aE1bbd63C660e6d0b0dd03E263B7` |
| **IMD Intake v2** (pay and ask in one transaction; the one the registry uses) | `0xa43e6f75ee006411f79ac1c84120606c2330de82` |
| IMD Intake v1 (legacy; `/health.intake.chains[].legacyIntakes`; still priced and still completed) | `0x1397434cd35e8a9c8ac312a61d3a285eb31dea56` |
| oracle attester (signs attestations) | `0x5598aa9146215bc13eb26f2c692ad1461fd32982` |
| IMD BurnExecutor V2 (fee destination) | `0xe29386719C155B6847aD5a4E97C6674f10ffc750` |
| Intake writer (calls `complete`) | `0x3d3c0df7c1a17d384545e9d7c8228897bd9625cb` |

Intake v2 was deployed through CREATE2 at the same address on every chain the plane serves; `/health` lists it as
`intake` for chains 1, 4663 and 11155111 with v1 under `legacyIntakes`. Its source says "every function, event and
getter of version 1 is here unchanged"; `requestWithFailure`, `failureSelectorOf` and `FailureHookSet` are new. Both
mainnet addresses return `priceOf` 0.5 IMD, `callbackGas` 200,000 and the same writer (read 2026-10-12 00:30 UTC).
Sepolia Intake v2's `callbackGas` is 1,000,000; the unit tests still prove delivery with mainnet's stricter
200,000 stipend. The Intake owner can change these values; read them before launch and monitor them afterwards.

Deployment order is Renderer, Composer, Registry. Registry has seven ordinary-storage addresses, in this exact order: `(curator, imd, intake, attester, renderer, composer, burnExecutor)`. All seven must be nonzero; Renderer, Composer and BurnExecutor must always have code. The attester is an EOA. If Curator, IMD and Intake all lack code, the floor skips only settlement, decimals and price reads. Otherwise Curator must be settled, IMD must have 18 decimals and Intake must quote a nonzero price. No constructor sends funds or creates another contract. The dependencies are fixed: no owner, setter, pause or upgrade.

The IdentityMD collection is a constant in T6's off-chain evidence recipe, not a constructor dependency or a direct-read credential. On Sepolia the deploy helper uses the supplied Curator and TestIMD mocks and the coded V1 executor; mainnet uses V2. The seven getters are the launch verification surface. Runtime contains no patched immutables, so rebuilt and deployed runtime can be compared byte-for-byte.

The Composer's public views trust their arguments, and `compose` trusts its spec: Registry passes pinned dependencies and stored, validated specs. Community validation reads `block.number` on mainnet, ignoring the caller's blockNumber. Off mainnet it uses `mainnetHeightBound()`: 15,537,395 until timestamp 1,663,224,191, then that height plus elapsed seconds / 12. Skipped slots make this upper bound exceed the actual head; clients must verify a mainnet window before spending. Catalog windows are exempt from the 7,200-block community minimum. Kind-4 fromBlock participates in the hash even though its state read is at toBlock. Duplicate specs cost their registrant. Kind-3 panel working may consider positions beyond head; its attested list must contain exactly head entries.

The attester, Intake ABI, action version, question hashing and recipe addresses cannot be rotated here. Changes require a successor deployment. Operators must monitor the Intake's price, callback stipend and signer policy and stop advertising unusable requests. DISCLOSURE.md details the trust and liveness limits.

## 2. Asking: `Intake.requestWithFailure`

```solidity
struct Callback { address target; bytes4 selector; }
function request(bytes32 action, bytes calldata body, Callback calldata callback, address asset, uint256 amount)
    external payable returns (bytes32 requestId);
function requestWithFailure(bytes32 action, bytes calldata body, Callback calldata callback, bytes4 onFailure,
    address asset, uint256 amount) external payable returns (bytes32 requestId);
function priceOf(bytes32 action, address asset) external view returns (uint256);
function callbackGas() external view returns (uint64);
function failureSelectorOf(bytes32 requestId) external view returns (bytes4);
```

- The registry calls **`requestWithFailure`** with `callback = (address(this), this.onResult.selector)` and
  `onFailure = this.onFailure.selector`, so a refusal or a failed panel reaches the registry too (section 3).
- `action` is the action name, an at sign and the version, as a right-padded `bytes32`:
  **`oracle.request@oracle-1`** = `0x6f7261636c652e72657175657374406f7261636c652d31000000000000000000`.
  `priceOf(action, IMD)` returned `500000000000000000` (0.5 IMD) on 2026-10-12; the other spellings return 0 and
  `request` reverts `ActionNotSold`. Read `priceOf` at call time and pay exactly that: the registry must never
  hard-code 0.5 IMD, and the claimant's `upgrade` charges `k * priceOf(...)`.
- `body` is the UTF-8 JSON of `TEMPLATES.md`, at most `MAX_BODY_BYTES` = 16,384 bytes. **It carries
  `"consumer": {"chainId": <deployment chainId>, "verifyingContract": "<the registry, lowercase hex>"}`**:
  `consumer.chainId` is `block.chainid` (11155111 on Sepolia), and that field supplies the EIP-712 domain
  (section 4). The top-level question `chainId` stays 1: every question is about Ethereum mainnet.
- `asset` is the IMD token; the Intake pulls `amount` with `transferFrom`, so the registry approves the Intake for
  the amount before calling. The claimant approves the registry; the registry pulls, then forwards.
- `requestId = keccak256(abi.encode(block.chainid, address(intake), ++nonce))` is returned and emitted in
  `Requested(requestId, payer, action, body, callbackTarget, callbackSelector, asset, amount)`, followed by
  `FailureHookSet(requestId, onFailure)`. **This id is the Intake's. The plane gives the same request a second id, a
  UUID, and that is the one it signs** (section 4).
- The plane reads `Requested`, admits or refuses the body, pins `toBlockHash`, runs the panel, and the writer calls
  `complete`.

## 3. Answering: what reaches `onResult` and `onFailure`

```solidity
function complete(bytes32 requestId, uint8 status, bytes32 resultHash, string calldata uri, bytes calldata args)
```

`status` 0 = a result, 1 = refused, 2 = ended without a result (a panel that disagreed, `not_answerable`). The Intake
sends `bytes.concat(selector, args)` to `callback.target` with a gas stipend of **`callbackGas()` = 200,000 on
mainnet, 1,000,000 on Sepolia** (read it; it is settable by the Intake's owner), no value, and records `delivered` without reverting the writer's
transaction. A callback that reverts or runs out of gas is simply `delivered == false`: the request is still
`completed` and will never be retried.

- **Status 0** calls the result selector with `args = abi.encode(bytes32 requestId, OracleAttestation a, bytes
  signature)`:

  ```solidity
  function onResult(bytes32 requestId, OracleAttestation calldata a, bytes calldata signature) external;
  ```

- **Status 1 and 2** call the failure selector the request named, with `args = abi.encode(bytes32 requestId, uint8
  status, bytes32 reason, uint16 agreed, uint16 answered, bytes signature)`. The Intake itself checks that the first
  two words equal this request and this status (`FailureArgsMismatch` otherwise), and calls nothing when `args` is
  empty:

  ```solidity
  function onFailure(bytes32 requestId, uint8 status, bytes32 reason, uint16 agreed, uint16 answered,
      bytes calldata signature) external;
  ```

  The registry checks `msg.sender == intake` and that `pending[requestId]` exists, clears the pending pair, emits
  `NoVerdict(requestId, traitId, status, reason, agreed, answered)` and never marks a trait. It does not interpret
  `signature` (its scheme is undocumented; the Intake and the writer authenticate the call). A claimant may request
  the same trait again afterwards.

- `onResult` must finish well inside 200,000 gas: one `ecrecover` (3,000), the digest, a few `sload`s, three or four
  `sstore`s, two events. The only loop is the `head`-bounded envelope check of T3 (at most 64 words).
- `onResult` and `onFailure` never revert on an ABI-valid envelope with bad content; they record a miss
  (`Missed(requestId, traitId, reason)`) and return. Calldata that does not decode as the declared tuple fails in
  Solidity's decoder before the function body runs; the Intake records that as `delivered == false`. The promise is
  therefore scoped to envelopes that decode, and the tests exercise the two cases separately.
- A request the plane never completes (three of the first seven Ethereum requests stayed `admitted`) stays pending
  until `abandon(requestId)` strictly after 31 days.

The registry checks `msg.sender == intake` first in both functions. For a pending result, it bounds both dynamic
fields directly in calldata before copying signature bytes or hashing the answer. Even an ABI-valid 262,144-byte
signature or answer must finish as a miss under the stipend, clear its pending record and reverse index, and allow
an immediate paid retry. An unknown request still returns reason 1 without inspecting these fields.

## 4. The attestation

EIP-712, domain `{ name: "IdentityMD Oracle", version: "2", chainId: <deployment chainId>, verifyingContract: <consumer> }`.
The body supplies `consumer.chainId = block.chainid`; the signed message's `chainId` and the top-level body
`chainId` are both 1, the question's Ethereum mainnet evidence chain. These are separate checks: a mainnet
question signed under the Sepolia consumer domain is valid on Sepolia, while `a.chainId == 11155111` is reason 3.

**`verifyingContract` is the body's `consumer.verifyingContract`**, measured on two third-party requests: for one the
consumer equals the callback target, for the other it is a different contract (a `SwarmFeed`), and the attester signed
the consumer, not the callback target (`reference/attestations/2026-10-10-meatbag-consumer.json`,
`2026-10-11-feed-consumer-v2.json`, both verified with `cast wallet verify` under their domain and refused under the
zero domain). Requests without a `consumer` field were signed for the zero address (the three pilot attestations).
The registry therefore writes its own address into every body and verifies with
`verifyingContract = address(this)`.

Primary type and field order, identical on five mainnet completions and five served attestations:

```solidity
struct OracleAttestation {
    bytes32 requestId;      // the plane's oracle request UUID, right-padded to 32 bytes; NOT the Intake's requestId
    uint256 chainId;
    bytes32 questionHash;   // keccak256 of the canonical question document (check 7)
    uint8   answerType;     // 0 bool, 1 address, 2 bytes32, 3 uint256, 4 address[], 5 bytes32[]
    bytes   answer;         // abi.encode of the value: bool -> 32 bytes 0/1; uint256 -> 32 bytes; address[] -> abi.encode(address[])
    uint256 figure;         // the number behind the answer where there is one; the plane leaves it 0 for panel answers
    uint64  fromBlock;
    uint64  toBlock;
    bytes32 blockHash;      // the hash of toBlock, pinned by the plane at admission
    bytes32 panelJobId;
    uint16  panelSize;
    uint16  quorum;
    uint16  agreed;
    uint64  issuedAt;
    uint64  expiresAt;
}
```

Type string for the struct hash:
`OracleAttestation(bytes32 requestId,uint256 chainId,bytes32 questionHash,uint8 answerType,bytes answer,uint256 figure,uint64 fromBlock,uint64 toBlock,bytes32 blockHash,bytes32 panelJobId,uint16 panelSize,uint16 quorum,uint16 agreed,uint64 issuedAt,uint64 expiresAt)`
(`bytes answer` hashes as `keccak256(answer)` per EIP-712). The signature is 65 bytes r, s, v.

**Digest without immutables.** Do not inherit OpenZeppelin's `EIP712` (its cached domain separator and name/version
fallbacks are seven immutables, and two deployments of the same source produce different runtime code; measured by
the round-2 reviewer). Compute at verification time:

```solidity
bytes32 domainSeparator = keccak256(abi.encode(
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
    keccak256("IdentityMD Oracle"), keccak256("2"), block.chainid, address(this)));
bytes32 digest = MessageHashUtils.toTypedDataHash(domainSeparator, structHash);   // keccak256("\x19\x01" . ds . sh)
(address signer, ECDSA.RecoverError err, ) = ECDSA.tryRecover(digest, signature); // never ECDSA.recover: it reverts
```

A `tryRecover` error, a zero signer or a signer other than the attester is reason 2. The compiler artifact's
`immutableReferences` must be empty for all three contracts (a test asserts it, and deploys them twice to compare
runtime bytes).

**What the registry verifies before marking a trait** (`CATALOG.md` section 4; reason codes below):

1. `msg.sender == intake`; `pending[requestId]` exists (the `requestId` argument is the Intake's id, which the
   registry stored when it sent the request). **`a.requestId` is not compared with it**: the signed id is the plane's
   UUID. It is stored in the `verified` tuple as `oracleRequestId`, so a third party can fetch
   `/oracle/requests/<uuid>/attestation` from it.
2. Before any dynamic copy or hash: `signature.length == 65` (otherwise reason 2); then
   `a.answer.length <= 2112` (64 ABI-encoded addresses) and, for the pending bool/uint256 kind,
   `a.answer.length == 32` (otherwise reason 9). The expected kind comes from the pending trait, not the untrusted
   `a.answerType`. Only then check `a.chainId == QUESTION_CHAIN_ID` (1), followed by the recovered signer == attester.
3. `a.answerType` equals the template's type; `a.agreed >= a.quorum`, `a.quorum >= the template's quorum` (3 for kinds 1, 2 and 4; 7 for kinds 3, 5 and 6), `a.panelSize >= the template's panel size`.

   The consumer refuses below-quorum signatures even when the plane signs one; historical failed attempts are recorded in the archived integration document. T3 currently uses 11 members / quorum 7 and explicitly names the indexed grouping topic. A quorum failure spends the price and stores no fact.
4. `a.fromBlock` and `a.toBlock` equal the pending request's window (the trait's canonical window or the spec's).
5. `requestedAt <= a.issuedAt <= requestedAt + 1 days`, `a.expiresAt <= a.issuedAt + 30 days`, `block.timestamp <= a.expiresAt` and `a.issuedAt <= block.timestamp + 1 hours` (the plane's clock may run ahead of
   block time; issuance before the request is always refused).
6. After the question-hash check (7), the decoded answer passes the rule: `>= threshold`, `== true`, or (T3) the envelope is canonical (check 8).
7. **`a.questionHash == pending.questionHash`.** The plane's `questionHash` is
   `keccak256(canonical JSON document)` where the document is the request body reduced to
   `{answerType, chainId, definitions, question, v, window: {fromBlock, toBlock}}`, plus `head` when the body has one
   and `evidence` only when it is `"panel"` (the default `"chain"` is omitted), serialised as RFC 8785 canonical JSON:
   keys sorted, no whitespace, integers as decimal digits, strings escaped only for `"`, `\` and control characters.
   `panelSize`, `quorum`, `validForSeconds`, `consumer` and the pinned `toBlockHash` are **not** in the document.
   Changing the consumer chain therefore does not change the question hash; on chain 1 every body byte remains
   identical to the mainnet fixtures.
   Measured on 14 free quotes (ten fixtures with their vendored quotes in `reference/plane/quotes/`, four probes) and
   on the x402 pilot, whose quote hash equals its attested hash. The registry computes the document from the same
   parameters it composes the body from, at request time, and stores the hash in the pending record; the callback
   compares one word. This binds the attestation to the exact question the registry asked, so a writer that pairs
   claimant A's attestation with claimant B's request, or one trait's with another's, produces a miss, not a trait.
   The golden test asserts that the `questionHash` of the canonical document (`keccak256(canonicalDocument)`,
   the keccak of the document, never of the body: the body's keccak is a different value) equals the plane's value
   for all ten fixtures (`reference/plane/questionHashes.json`).
8. **Decode defensively, never revert.** `a.answer` for `bool` and `uint256` must be exactly 32 bytes (and for `bool`
   the word 0 or 1); otherwise reason 9. For `address[]` (T3) the callback does not decode the list; it checks the
   canonical envelope: `answer.length == 64 + 32 * n`, word 0 == `0x20`, word 1 == `n`, `n == threshold` with `1 <= n <= 32`, and the upper
   12 bytes of every element word are zero. A malformed envelope is reason 9 and **does not store the shared fact**,
   so the fact can be requested again. On success it stores `(requestId, keccak256(a.answer), n)`, nothing else.
   A plain `abi.decode` on hostile bytes reverts, and a revert in `onResult` is a permanent `delivered == false`.
9. One shape. The registry accepts the 15-field struct only. A different wire tuple does not decode as this function's
   arguments and is `delivered == false` at the Intake (section 3); no second type string is tried.

**Diagnostic precedence**, after the Intake caller and pending-request checks: signature length (2), answer
length (9), chainId (3), signer (2), answerType (4), panel/quorum (5), window (6), expiry/issuedAt (7), questionHash
(10), then defensive decoding (9) and the rule (8). When several fields are invalid, the first failed check wins.
The size checks precede EIP-712 hashing and signature recovery; the subsequent quorum rule and canonical question
document are unchanged.

**`Missed` reason codes** (uint8): 1 not pending, 2 signer, 3 chainId, 4 answerType, 5 panel or quorum, 6 window,
7 expiry, 8 rule, 9 decode, 10 questionHash. (The round-1 code 10, "requestId mismatch", is retired: the signed id is
not the Intake id.)

### 4b. Transition table (every pending request ends in exactly one row)

The pending record is `pending[requestId] = (address claimant, uint16 traitId, uint64 requestedAt, bytes32
questionHash, uint64 fromBlock, uint64 toBlock)`; for a shared-fact request `claimant == address(0)` and `traitId` is the fact id. The reverse index is
`pendingOf[claimant][traitId] = requestId` (for shared facts `sharedPending[factId]`). "Clear" means: delete
`pending[requestId]`, and delete the reverse index **only if it still equals this `requestId`**.

| event | who | effect on the pair | stored | event emitted |
|---|---|---|---|---|
| `onResult`, all checks pass, personal | Intake | clear | `verified[claimant][traitId] = (requestId, a.requestId, fromBlock, toBlock)`; a community id is appended to `verifiedSpecsOf(claimant)` | `Verified`, `MetadataUpdate(tokenOf[claimant])` if a card exists |
| `onResult`, all checks pass, shared | Intake | clear | `sharedFact[factId] = (requestId, keccak256(a.answer), n)` | `SharedFactStored` |
| `onResult`, rule false (reason 8) | Intake | clear | nothing; the pair may be requested again (paid by the claimant) | `Missed` |
| `onResult`, any other reason 2 to 10 | Intake | clear | nothing | `Missed` |
| `onResult` or `onFailure`, `requestId` unknown (abandoned, consumed, never ours) | Intake | nothing | nothing | `Missed(reason 1)` |
| `onFailure` (status 1 or 2) | Intake | clear | nothing; the pair may be requested again | `NoVerdict` |
| `abandon(requestId)` strictly after `requestedAt + 31 days`, personal | stored claimant only | clear | nothing | `Abandoned` |
| `abandon(requestId)` strictly after `requestedAt + 31 days`, shared (`claimant == 0`) | anyone | clear | nothing | `Abandoned` |
| `abandon` of a personal request after the deadline by a stranger | anyone but its claimant | revert `NotClaimant()` | | |
| `abandon` at or before the deadline | anyone | revert `TooEarly()` | | |
| late callback for an abandoned request | Intake | as the unknown-id row: the successor request's reverse index is untouched, because the index is cleared only when it equals the stale id | | `Missed(reason 1)` |
| not called back, not abandoned | | stays pending; at most one pending request per pair, so a new `upgrade` for the pair reverts | | |

A miss permits a fresh paid request. The Intake id is the pending key and the signed oracle UUID is a distinct stored identifier. A duplicate live Intake id reverts the entire new request, including transfers and approvals. An old callback after abandonment is reason 1 and cannot clear a successor. At exactly day 31 the latest valid answer may verify and abandonment is TooEarly; one second later it has expired and abandonment is permitted. Swarmed callbacks compare against the stored request window, never a newly computed head.

## 5. Paying

Approve IMD to Registry for the intended action. `mintCard` costs 0.1 IMD and `registerSpec` costs 6.4 IMD. Fees are forwarded to the BurnExecutor V2 for bridging and burning on Base. No ETH is attached or processed. Oracle requests pay the live Intake quote (0.5 IMD at the pinned integration block) through an exact allowance and `requestWithFailure`; the transaction leaves no request funds in Registry. maxPrice protects against price changes. The price is spent even on false, invalid, refused or unanswered requests. No refunds are promised.

Anyone can bridge the executor balance by separately paying LayerZero's quote. The amount is subject to dust and OFT limits, and Base burning is asynchronous. Registry guarantees the transfer only. The executor owner can change its token, OFT, destination and options or rescue funds. See DISCLOSURE.md and the mainnet fork test at block 26,237,654. Unsolicited token transfers can still land at any contract address and cannot be recovered from this ownerless Registry; “zero at rest” refers to its own transaction flows.

## 6. The Curator's views the registry reads (all `view`, all frozen since the Curator settled)

| view | returns | used by |
|---|---|---|
| `firstHourOf(address)` | `(uint256 hour, bool hasJoined)`; a non-member is `(0, false)` | 101, 201, 202 |
| `txCountOf(address)` | `uint256` deposits | 301 to 303 |
| `contributedBy(address)` | `uint256` wei, the largest single send (`highWater`) | 401 to 404 |
| `pointsOf(address)` | `uint256` points (1000 x sqrt(weight in ETH)) | 501 to 503 |
| `isSettled()` | `bool`, true since hour 66 | sanity check in the constructor outside the floor (Curator, IMD and Intake all without code), nothing else |

Never read `contributors(address)` for the hour: its fourth word is `firstHour + 1`. IDMD: `balanceOf(address)` for
Swarmed uses T6 historical evidence, never a live balance predicate.
