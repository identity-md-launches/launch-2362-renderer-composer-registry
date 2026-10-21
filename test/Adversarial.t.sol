// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {MockBurnExecutor} from "./mocks/MockBurnExecutor.sol";

import {Base} from "./Base.t.sol";
import {Registry} from "../src/Registry.sol";
import {Composer} from "../src/Composer.sol";
import {OracleAttestation} from "../src/interfaces/IOracleConsumer.sol";
import {Spec, Card} from "../src/Types.sol";
import {ReentrantIMD, MockIntake} from "./mocks/Mocks.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice The inputs the happy path never sends: a writer that pairs one claimant's attestation
///         with another's request, a signed struct altered after signing (every field), panels and
///         windows at their boundaries, maximal specs, the shared-fact envelope at its largest,
///         every callback shape under the real stipend, re-entrancy through the token into every
///         IMD-moving function, and `tokenURI` as a pure function of the claimant's facts.
///         CONCEPT.md section 6: invariants 3, 4, 5, 7, 8, 9, 11.
contract AdversarialTest is Base {
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    // ------------------------------------------------------------------ 3, 4: pairing

    function test_attestationForAnotherClaimantIsAMissForThisRequest() public {
        bytes32 ra = ask(alice, 701);
        bytes32 rb = ask(bob, 701);
        // the writer pairs alice's answer with bob's request: same trait, other claimant, other hash
        OracleAttestation memory a = attestationFor(ra, word(1));
        vm.expectEmit(false, false, false, true);
        emit Registry.Missed(rb, 701, 10);
        assertTrue(deliver(rb, a));
        assertFalse(registry.hasTrait(bob, 701));
        assertFalse(registry.hasTrait(alice, 701), "alice's own request is still pending, not marked");
        assertEq(registry.pendingOf(alice, 701), ra, "alice's pair untouched");
        assertEq(registry.pendingOf(bob, 701), bytes32(0), "bob's pair cleared by the miss");
        // alice's answer for alice's request still works
        assertTrue(deliver(ra, a));
        assertTrue(registry.hasTrait(alice, 701));
    }

    function test_attestationForAnotherTraitWithTheSameWindowIsAMiss() public {
        // 801 and 901 share W_LIFE, the type, the panel: only the question differs
        bytes32 r801 = ask(alice, 801);
        bytes32 r901 = ask(alice, 901);
        OracleAttestation memory a = attestationFor(r801, word(1));
        vm.expectEmit(false, false, false, true);
        emit Registry.Missed(r901, 901, 10);
        assertTrue(deliver(r901, a));
        assertFalse(registry.hasTrait(alice, 901));
        assertTrue(deliver(r801, a));
        assertTrue(registry.hasTrait(alice, 801));
        assertFalse(registry.hasTrait(alice, 901));
    }

    function test_questionHashIsBoundToTheClaimantAndTheTrait() public view {
        (, bytes32 h1) = registry.composeBody(701, alice);
        (, bytes32 h2) = registry.composeBody(701, bob);
        (, bytes32 h3) = registry.composeBody(801, alice);
        (, bytes32 h4) = registry.composeBody(901, alice);
        assertTrue(h1 != h2 && h1 != h3 && h3 != h4 && h2 != h3);
        // the shared fact's question names no claimant: one hash for everyone
        (, bytes32 s1) = registry.composeBody(1201, alice);
        (, bytes32 s2) = registry.composeBody(1201, address(0));
        assertEq(s1, s2);
    }

    // ------------------------------------------------------------------ 4: tampering, fuzzed

    /// forge-config: default.fuzz.runs = 512
    function test_fuzz_anyFieldAlteredAfterSigningIsASignatureMiss(uint8 field, uint256 seed) public {
        field = uint8(bound(field, 0, 14));
        vm.assume(seed != 0);
        bytes32 rid = ask(alice, 701);
        OracleAttestation memory a = attestationFor(rid, word(1));
        bytes memory sig = sign(a);
        _mutate(a, field, seed);
        // Answer size precedes hashing; chain id then precedes recovery; other mutations break the signature.
        vm.expectEmit(false, false, false, true);
        emit Registry.Missed(rid, 701, field == 1 ? 3 : field == 4 ? 9 : 2);
        assertTrue(deliver(rid, a, sig));
        assertFalse(registry.hasTrait(alice, 701));
        assertEq(registry.pendingOf(alice, 701), bytes32(0));
    }

    function _mutate(OracleAttestation memory a, uint8 field, uint256 seed) internal pure {
        bytes32 x = keccak256(abi.encode(seed));
        if (field == 0) a.requestId ^= x;
        else if (field == 1) a.chainId ^= uint256(x) | 1;
        else if (field == 2) a.questionHash ^= x;
        else if (field == 3) a.answerType ^= uint8(uint256(x)) | 1;
        else if (field == 4) a.answer = bytes.concat(a.answer, bytes1(uint8(uint256(x)) | 1));
        else if (field == 5) a.figure ^= uint256(x) | 1;
        else if (field == 6) a.fromBlock ^= uint64(uint256(x)) | 1;
        else if (field == 7) a.toBlock ^= uint64(uint256(x)) | 1;
        else if (field == 8) a.blockHash ^= x;
        else if (field == 9) a.panelJobId ^= x;
        else if (field == 10) a.panelSize ^= uint16(uint256(x)) | 1;
        else if (field == 11) a.quorum ^= uint16(uint256(x)) | 1;
        else if (field == 12) a.agreed ^= uint16(uint256(x)) | 1;
        else if (field == 13) a.issuedAt ^= uint64(uint256(x)) | 1;
        else a.expiresAt ^= uint64(uint256(x)) | 1;
    }

    /// forge-config: default.fuzz.runs = 512
    function test_fuzz_panelAndQuorumBoundaries(uint16 panelSize, uint16 quorum, uint16 agreed) public {
        bytes32 rid = ask(alice, 701);
        OracleAttestation memory a = attestationFor(rid, word(1));
        a.panelSize = panelSize;
        a.quorum = quorum;
        a.agreed = agreed;
        bool ok = agreed >= quorum && quorum >= 3 && panelSize >= 5;
        if (!ok) {
            vm.expectEmit(false, false, false, true);
            emit Registry.Missed(rid, 701, 5);
        }
        assertTrue(deliver(rid, a));
        assertEq(registry.hasTrait(alice, 701), ok);
    }

    /// forge-config: default.fuzz.runs = 512
    function test_fuzz_panelTraitNeedsElevenAndSeven(uint16 panelSize, uint16 quorum, uint16 agreed) public {
        bytes32 rid = ask(alice, 1301);
        OracleAttestation memory a = attestationFor(rid, word(1));
        a.panelSize = panelSize;
        a.quorum = quorum;
        a.agreed = agreed;
        bool ok = agreed >= quorum && quorum >= 7 && panelSize >= 11;
        assertTrue(deliver(rid, a));
        assertEq(registry.hasTrait(alice, 1301), ok);
    }

    /// forge-config: default.fuzz.runs = 512
    function test_fuzz_windowMustEqualTheCanonicalOne(uint64 fromBlock, uint64 toBlock) public {
        bytes32 rid = ask(alice, 701);
        OracleAttestation memory a = attestationFor(rid, word(1));
        a.fromBlock = fromBlock;
        a.toBlock = toBlock;
        bool ok = fromBlock == B_H24 && toBlock == B_END;
        if (!ok) {
            vm.expectEmit(false, false, false, true);
            emit Registry.Missed(rid, 701, 6);
        }
        assertTrue(deliver(rid, a));
        assertEq(registry.hasTrait(alice, 701), ok);
    }

    /// forge-config: default.fuzz.runs = 512
    function test_fuzz_expiryAndClockSkewBoundaries(uint64 issuedAt, uint64 expiresAt) public {
        bytes32 rid = ask(alice, 701);
        OracleAttestation memory a = attestationFor(rid, word(1));
        a.issuedAt = issuedAt;
        a.expiresAt = expiresAt;
        uint256 now_ = block.timestamp;
        bool ok = now_ <= expiresAt && issuedAt <= now_ + 1 hours && issuedAt >= T0 && uint256(issuedAt) <= T0 + 1 days
            && uint256(expiresAt) <= uint256(issuedAt) + 30 days;
        if (!ok) {
            vm.expectEmit(false, false, false, true);
            emit Registry.Missed(rid, 701, 7);
        }
        assertTrue(deliver(rid, a));
        assertEq(registry.hasTrait(alice, 701), ok);
    }

    function test_expiryAtTheExactSecondStillPassesAndOneLaterDoesNot() public {
        bytes32 rid = ask(alice, 701);
        OracleAttestation memory a = attestationFor(rid, word(1));
        a.expiresAt = uint64(block.timestamp);
        a.issuedAt = uint64(block.timestamp + 1 hours);
        assertTrue(deliver(rid, a));
        assertTrue(registry.hasTrait(alice, 701), "expiresAt == now and issuedAt == now + 1h are inside");
        rid = ask(alice, 801);
        a = attestationFor(rid, word(1));
        a.issuedAt = uint64(block.timestamp + 1 hours + 1);
        assertTrue(deliver(rid, a));
        assertFalse(registry.hasTrait(alice, 801));
    }

    /// forge-config: default.fuzz.runs = 512
    function test_fuzz_countAnswerAgainstTheThreshold(uint256 value, bytes1 extra, bool malformed) public {
        bytes32 rid = ask(alice, 701);
        bytes memory ans = malformed ? bytes.concat(word(value), extra) : word(value);
        OracleAttestation memory a = attestationFor(rid, ans);
        assertTrue(deliver(rid, a));
        assertEq(registry.hasTrait(alice, 701), !malformed && value >= 1);
    }

    /// forge-config: default.fuzz.runs = 512
    function test_fuzz_boolAnswerMustBeExactlyZeroOrOne(uint256 value) public {
        bytes32 rid = ask(alice, 1301);
        OracleAttestation memory a = attestationFor(rid, word(value));
        uint8 reason = value == 1 ? 0 : value == 0 ? 8 : 9;
        if (reason != 0) {
            vm.expectEmit(false, false, false, true);
            emit Registry.Missed(rid, 1301, reason);
        }
        assertTrue(deliver(rid, a));
        assertEq(registry.hasTrait(alice, 1301), value == 1);
    }

    function test_signatureShapesThatDoNotRecover() public {
        uint256 n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
        // 64 bytes, 66 bytes, empty, v = 2, and the high-s twin, each derived from the signature of the
        // exact envelope delivered with it, so the shape alone is what fails.
        for (uint256 i; i < 5; ++i) {
            bytes32 rid = ask(alice, 701);
            OracleAttestation memory a = attestationFor(rid, word(1));
            bytes memory good = sign(a);
            bytes memory bad;
            if (i == 0) {
                bad = _slice(good, 64);
            } else if (i == 1) {
                bad = bytes.concat(good, hex"00");
            } else if (i == 3) {
                bad = bytes.concat(_slice(good, 64), hex"02");
            } else if (i == 4) {
                (bytes32 r, bytes32 s, uint8 v) = _split(good);
                bad = abi.encodePacked(r, bytes32(n - uint256(s)), v == 27 ? uint8(28) : uint8(27));
                // The twin is a valid secp256k1 signature of this envelope's digest by the attester:
                // only the low-s rule refuses it.
                assertEq(
                    ecrecover(registry.attestationDigest(a), v == 27 ? 28 : 27, r, bytes32(n - uint256(s))), attester
                );
            }
            vm.expectEmit(false, false, false, true);
            emit Registry.Missed(rid, 701, 2);
            assertTrue(deliver(rid, a, bad));
            assertFalse(registry.hasTrait(alice, 701));
        }
        // Positive control: the low-s original of the same shape of envelope verifies.
        bytes32 last = ask(alice, 701);
        OracleAttestation memory ok = attestationFor(last, word(1));
        assertTrue(deliver(last, ok, sign(ok)));
        assertTrue(registry.hasTrait(alice, 701));
    }

    function _slice(bytes memory b, uint256 n) internal pure returns (bytes memory out) {
        out = new bytes(n);
        for (uint256 i; i < n; ++i) {
            out[i] = b[i];
        }
    }

    function _split(bytes memory sig) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }

    // ------------------------------------------------------------------ 5: every callback under the stipend

    function test_sharedFactWorstCaseEnvelopeUnderTheStipend() public {
        fund(bob, PRICE);
        vm.prank(bob);
        registry.requestSharedFact(1201, PRICE);
        bytes32 rid = intake.lastId();
        address[] memory list = new address[](32);
        for (uint256 i; i < 32; ++i) {
            list[i] = address(uint160(0x5000 + i));
        }
        OracleAttestation memory a = attestationFor(rid, abi.encode(list));
        // the Intake's own `call(stipend, ...)`, with the stipend cut to 180,000: delivered means it fits with margin
        intake.setCallbackGas(180_000);
        assertTrue(deliver(rid, a), "the 32-address envelope must fit in 180,000, under the 200,000 stipend");
        (bytes32 sr,, uint16 n) = registry.sharedFact(1201);
        assertEq(sr, rid);
        assertEq(n, 32);
        // and the personal worst case (community id appended, card to refresh) fits the same margin
        mint(alice);
        uint16 specId = register(bob, t1Spec(address(0xCAFE), "Margin"));
        bytes32 rid2 = ask(alice, specId);
        assertTrue(deliver(rid2, attestationFor(rid2, word(1))), "worst case fits in 180,000");
        assertTrue(registry.hasTrait(alice, specId));
    }

    function test_everyTemplateVerifiesUnderTheStipendWithACard() public {
        mint(alice);
        uint16[5] memory ids = [701, 1301, 0, 0, 0];
        Spec memory s2 = t1Spec(address(0xCAFE), "T2");
        s2.kind = 2;
        s2.sumArg = "value";
        ids[2] = register(bob, s2);
        Spec memory s4 = t1Spec(address(0xCAFE), "T4");
        s4.kind = 4;
        s4.item = "function balanceOf(address) view returns (uint256)";
        s4.arg = "";
        s4.op = 2;
        s4.threshold = 5;
        ids[3] = register(bob, s4);
        Spec memory s5;
        s5.kind = 5;
        s5.threshold = 1;
        s5.fromBlock = B_DEPLOY;
        s5.toBlock = B_DEPLOY;
        s5.name = "T5";
        ids[4] = register(bob, s5);
        for (uint256 i; i < 5; ++i) {
            bytes32 rid = ask(alice, ids[i]);
            uint8 kind = registry.specOf(ids[i]).kind;
            OracleAttestation memory a = attestationFor(rid, word(kind == 2 ? 1 : 1));
            assertTrue(deliver(rid, a), "delivered under 200,000 through the Intake's call");
            assertTrue(registry.hasTrait(alice, ids[i]));
        }
        assertEq(registry.verifiedSpecsOf(alice).length, 3);
        // onFailure for a pending pair under the stipend
        bytes32 r = ask(alice, 801);
        assertTrue(fail(r, 1, "body_refused"));
    }

    function test_callbackStarvedOfGasIsNotDeliveredAndStaysPending() public {
        bytes32 rid = ask(alice, 701);
        OracleAttestation memory a = attestationFor(rid, word(1));
        intake.setCallbackGas(30_000);
        assertFalse(deliver(rid, a), "too little gas: the Intake records not delivered");
        assertEq(registry.pendingOf(alice, 701), rid, "nothing changed; abandon after 31 days");
        assertFalse(registry.hasTrait(alice, 701));
    }

    // ------------------------------------------------------------------ 3: hasTrait never reverts

    /// forge-config: default.fuzz.runs = 512
    function test_fuzz_hasTraitAndTraitsOfNeverRevert(address w, uint16 id, uint8 hour, bool joined, uint8 bal) public {
        curator.set(w, hour, joined, hour, uint256(hour) * 1e18, uint256(hour) * 100);
        if (w != address(0)) idmd.setBalance(w, bal);
        registry.hasTrait(w, id);
        registry.traitsOf(w);
        if (id > 601 && id < 10001 && !_isCatalogOracle(id)) {
            assertFalse(registry.hasTrait(w, id), "an id that is neither direct nor oracle is false");
        }
        if (id >= 10001) assertFalse(registry.hasTrait(w, id), "an unregistered spec is false");
    }

    function _isCatalogOracle(uint16 id) internal pure returns (bool) {
        return id == 601 || id == 701 || id == 801 || id == 901 || id == 1001 || (id >= 1101 && id <= 1105)
            || id == 1201 || id == 1301;
    }

    /// forge-config: default.fuzz.runs = 256
    function test_fuzz_upgradeRejectsEveryIdThatIsNotAnOracleTrait(uint16 id) public {
        // All uint16 inputs are exercised. Swarmed joined the paid catalog in docs/V3.md item 6.
        bool personalOracle = _isCatalogOracle(id) && id != 1201;
        fund(alice, PRICE);
        uint16[] memory ids = new uint16[](1);
        ids[0] = id;
        if (personalOracle) {
            vm.prank(alice);
            registry.upgrade(ids, PRICE);
            assertEq(registry.pendingOf(alice, id), intake.lastId());
            assertEq(imd.balanceOf(address(intake)), PRICE);
            assertEq(imd.balanceOf(address(registry)), 0);
            return;
        }
        vm.prank(alice);
        // 1201 is an oracle trait but a shared fact: it goes through requestSharedFact, never upgrade
        bytes4 want = id == 1201 ? Registry.NotASharedFact.selector : Registry.NotAnOracleTrait.selector;
        vm.expectRevert(abi.encodeWithSelector(want, id));
        registry.upgrade(ids, PRICE);
    }

    // ------------------------------------------------------------------ 9: paying

    /// forge-config: default.fuzz.runs = 256
    function test_fuzz_upgradeChargesExactlyKTimesPriceAndLeavesNoBalance(uint8 k, uint256 price) public {
        k = uint8(bound(k, 1, 9));
        price = bound(price, 1, 100 ether);
        intake.setPrice(price);
        uint16[9] memory chain = [701, 801, 901, 1001, 1101, 1102, 1103, 1104, 1105];
        uint16[] memory ids = new uint16[](k);
        for (uint256 i; i < k; ++i) {
            ids[i] = chain[i];
        }
        fund(alice, price * k);
        vm.prank(alice);
        registry.upgrade(ids, price);
        assertEq(imd.balanceOf(alice), 0);
        assertEq(imd.balanceOf(address(intake)), price * k);
        assertEq(imd.balanceOf(address(registry)), 0, "prices go to the Intake");
        for (uint256 i; i < k; ++i) {
            assertTrue(registry.pendingOf(alice, ids[i]) != 0);
        }
        // one wei short reverts whole
        fund(bob, price * k - 1);
        vm.prank(bob);
        vm.expectRevert();
        registry.upgrade(ids, price);
    }

    // ------------------------------------------------------------------ shared facts, edges

    function test_abandonedSharedFactCanBeRequestedAgainAndTheLateAnswerIsIgnored() public {
        fund(bob, 2 * PRICE);
        vm.prank(bob);
        registry.requestSharedFact(1201, PRICE);
        bytes32 rid = intake.lastId();
        vm.expectRevert(Registry.TooEarly.selector);
        registry.abandon(rid);
        vm.warp(block.timestamp + 31 days + 1);
        vm.prank(alice);
        registry.abandon(rid);
        assertEq(registry.sharedPending(1201), bytes32(0));
        vm.prank(bob);
        registry.requestSharedFact(1201, PRICE);
        bytes32 rid2 = intake.lastId();
        address[] memory list = new address[](32);
        list[0] = alice;
        OracleAttestation memory a = attestationFor(rid2, abi.encode(list));
        vm.expectEmit(false, false, false, true);
        emit Registry.Missed(rid, 0, 1);
        assertTrue(deliver(rid, a));
        assertEq(registry.sharedPending(1201), rid2, "the successor is untouched");
        assertTrue(deliver(rid2, a));
        vm.prank(alice);
        registry.applySharedFact(1201, list);
        assertTrue(registry.hasTrait(alice, 1201));
    }

    /// forge-config: default.fuzz.runs = 256
    function test_fuzz_applySharedFactOnlyWithinTheHead(uint8 n, uint8 pos) public {
        // V2 item 8: only a list of exactly the head (32) is stored; any other length misses (reason 9)
        n = uint8(bound(n, 1, 64));
        pos = uint8(bound(pos, 0, n - 1));
        fund(bob, PRICE);
        vm.prank(bob);
        registry.requestSharedFact(1201, PRICE);
        bytes32 rid = intake.lastId();
        address[] memory list = new address[](n);
        for (uint256 i; i < n; ++i) {
            list[i] = address(uint160(0x7000 + i));
        }
        list[pos] = alice;
        if (n != 32) {
            vm.expectEmit(false, false, false, true);
            emit Registry.Missed(rid, 1201, 9);
            assertTrue(deliver(rid, attestationFor(rid, abi.encode(list))));
            (bytes32 none,,) = registry.sharedFact(1201);
            assertEq(none, bytes32(0), "an incomplete list is never stored");
            vm.prank(alice);
            vm.expectRevert(abi.encodeWithSelector(Registry.FactNotStored.selector, 1201));
            registry.applySharedFact(1201, list);
            return;
        }
        assertTrue(deliver(rid, attestationFor(rid, abi.encode(list))));
        vm.prank(alice);
        registry.applySharedFact(1201, list);
        assertTrue(registry.hasTrait(alice, 1201));
        // a list that differs in one byte never matches
        list[(pos + 1) % n] = address(0x1);
        vm.prank(address(0x1));
        vm.expectRevert(Registry.ListMismatch.selector);
        registry.applySharedFact(1201, list);
    }

    function test_communityT3SpecIsASharedFactWithItsOwnHead() public {
        Spec memory s = t1Spec(address(0xCAFE), "Top three");
        s.kind = 3;
        s.sumArg = "value";
        s.threshold = 3;
        uint16 id = register(bob, s);
        fund(alice, PRICE);
        uint16[] memory ids = new uint16[](1);
        ids[0] = id;
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Registry.NotASharedFact.selector, id));
        registry.upgrade(ids, PRICE);
        fund(bob, PRICE);
        vm.prank(bob);
        registry.requestSharedFact(id, PRICE);
        bytes32 rid = intake.lastId();
        address[] memory list = new address[](3);
        for (uint256 i; i < 3; ++i) {
            list[i] = address(uint160(0x8000 + i));
        }
        list[2] = alice;
        assertTrue(deliver(rid, attestationFor(rid, abi.encode(list))));
        vm.prank(alice);
        registry.applySharedFact(id, list);
        vm.prank(bob);
        vm.expectRevert(Registry.NotInList.selector);
        registry.applySharedFact(id, list);
        assertTrue(registry.hasTrait(alice, id));
        assertEq(registry.verifiedSpecsOf(alice)[0], id, "a shared community fact joins the community index");
        (bytes32 vr,, uint64 f, uint64 t) = registry.verified(alice, id);
        assertEq(vr, rid);
        assertEq(f, B_DEPLOY);
        assertEq(t, B_END);
    }

    // ------------------------------------------------------------------ 7: specs at their limits

    /// forge-config: default.fuzz.runs = 64
    function test_fuzz_maximalSpecRegistersComposesAndFitsTheBody(uint8 kind, uint256 threshold, uint256 fixedVal)
        public
    {
        kind = uint8(bound(kind, 1, 5));
        Spec memory s;
        s.kind = kind;
        s.name = _repeat("N", 32);
        if (kind == 5) {
            s.threshold = bound(threshold, 1, type(uint256).max);
            s.fromBlock = B_DEPLOY;
            s.toBlock = B_DEPLOY;
        } else {
            s.target = address(0xCAFE);
            // a kind-3 item names its grouping key as an address-typed indexed parameter (V2 item 18)
            s.item = kind == 4
                ? string.concat("function ", _repeat("a", 32), "(address) view returns (uint256)")
                : string.concat(
                    "event ",
                    _repeat("a", 32),
                    "(address indexed ",
                    _repeat("b", 32),
                    ", uint256 indexed ",
                    _repeat("c", 32),
                    ", uint256 ",
                    _repeat("d", 32),
                    ")"
                );
            s.fromBlock = 1;
            s.toBlock = type(uint64).max / 2;
            vm.roll(uint256(type(uint64).max / 2) + 64); // the finality margin
            s.threshold = kind == 3 ? bound(threshold, 1, 32) : bound(threshold, 1, type(uint256).max);
            if (kind <= 3) s.arg = _repeat("b", 32);
            if (kind <= 2) {
                s.fixedArg = _repeat("c", 32);
                s.fixedVal = fixedVal;
            }
            if (kind == 2 || kind == 3) s.sumArg = _repeat("d", 32);
            if (kind == 4) s.op = 5;
        }
        uint16 id = register(bob, s);
        (bytes memory body, bytes32 qh) = registry.composeBody(id, alice);
        assertTrue(qh != bytes32(0));
        assertLe(body.length, 16_384, "the Intake's MAX_BODY_BYTES");
        assertLe(bytes(vm.parseJsonString(string(body), ".question")).length, 1000);
        string[] memory keys = vm.parseJsonKeys(string(body), ".definitions");
        for (uint256 i; i < keys.length; ++i) {
            assertLe(bytes(vm.parseJsonString(string(body), string.concat(".definitions.", keys[i]))).length, 512);
        }
        // and the registry can actually ask it
        if (kind != 3) {
            vm.roll(26_200_000);
            fund(alice, PRICE);
            uint16[] memory ids = new uint16[](1);
            ids[0] = id;
            vm.prank(alice);
            registry.upgrade(ids, PRICE);
            assertEq(intake.bodyOf(intake.lastId()), body);
        }
    }

    function _repeat(bytes1 ch, uint256 n) internal pure returns (string memory) {
        bytes memory b = new bytes(n);
        for (uint256 i; i < n; ++i) {
            b[i] = ch;
        }
        return string(b);
    }

    /// forge-config: default.fuzz.runs = 256
    function test_fuzz_specBodyIsDeterministicAndClaimantBound(address c1, address c2) public {
        uint16 id = register(bob, t1Spec(address(0xCAFE), "Det"));
        (bytes memory b1, bytes32 h1) = registry.composeBody(id, c1);
        (bytes memory b2, bytes32 h2) = registry.composeBody(id, c1);
        (bytes memory b3, bytes32 h3) = registry.composeBody(id, c2);
        assertEq(b1, b2);
        assertEq(h1, h2);
        assertEq(c1 == c2, h1 == h3);
        assertEq(c1 == c2, keccak256(b1) == keccak256(b3));
    }

    function test_traitClassForEveryCatalogIdAndRevertsForUnknown() public {
        uint16[25] memory all = [
            101,
            201,
            202,
            301,
            302,
            303,
            401,
            402,
            403,
            404,
            501,
            502,
            503,
            601,
            701,
            801,
            901,
            1001,
            1101,
            1102,
            1103,
            1104,
            1105,
            1201,
            1301
        ];
        for (uint256 i; i < 25; ++i) {
            uint16 id = all[i];
            bytes memory name = bytes(registry.traitName(id));
            assertGt(name.length, 0);
        }
        vm.expectRevert(abi.encodeWithSelector(Registry.NotAnOracleTrait.selector, 10001));
        registry.specOf(10001);
        vm.expectRevert(abi.encodeWithSelector(Registry.NotAnOracleTrait.selector, 101));
        registry.specOf(101);
    }

    function test_verifiedWindowIsTheCanonicalWindowForEveryOracleId() public {
        uint16[10] memory ids = [701, 801, 901, 1001, 1101, 1102, 1103, 1104, 1105, 1301];
        for (uint256 i; i < 10; ++i) {
            bytes32 rid = ask(alice, ids[i]);
            assertTrue(deliver(rid, attestationFor(rid, word(1))));
            (,, uint64 f, uint64 t) = registry.verified(alice, ids[i]);
            uint64 wantFrom = ids[i] == 701 ? B_H24 : B_DEPLOY;
            uint64 wantTo = ids[i] == 1105 ? B_FIRST1000 : ids[i] == 1301 ? B_DEPLOY : B_END;
            assertEq(f, wantFrom);
            assertEq(t, wantTo);
            Spec memory s = registry.specOf(ids[i]);
            assertEq(s.fromBlock, wantFrom);
            assertEq(s.toBlock, wantTo);
        }
        assertEq(registry.traitsOf(alice).length, 10);
    }

    // ------------------------------------------------------------------ 8: tokenURI is pure over the facts

    function test_tokenURIDependsOnlyOnTheClaimantsFacts() public {
        curator.set(alice, 0, true, 3, 1 ether, 1000);
        uint256 id = mint(alice);
        string memory u0 = registry.tokenURI(id);
        assertEq(registry.tokenURI(id), u0, "repeatable");
        vm.prank(alice);
        registry.transferFrom(alice, bob, id);
        assertEq(registry.tokenURI(id), u0, "a sale changes nothing on the card");
        vm.roll(block.number + 1000);
        vm.warp(block.timestamp + 1 days);
        assertEq(registry.tokenURI(id), u0, "time and blocks change nothing");
        idmd.setBalance(alice, 1);
        string memory u1 = registry.tokenURI(id);
        assertEq(u1, u0, "601 is frozen at mint: a seat bought later changes nothing");
        idmd.setBalance(bob, 1);
        assertEq(registry.tokenURI(id), u1, "the holder's IDMD is not the claimant's");
        bytes32 rid = ask(alice, 701);
        assertEq(registry.tokenURI(id), u1, "a pending request draws nothing");
        assertTrue(deliver(rid, attestationFor(rid, word(1))));
        assertTrue(keccak256(bytes(registry.tokenURI(id))) != keccak256(bytes(u1)), "a verified trait is drawn");
        Card memory c = renderer.cardOfOn(address(registry), id);
        assertEq(c.oracle.length, 1);
        assertEq(c.oracle[0].traitId, 701);
        assertEq(c.oracle[0].requestId, rid);
        assertEq(c.top[6], 701);
    }

    function test_cardShowsAtMostThirtyTwoCommunityIdsAndCountsThemAll() public {
        uint256 id = mint(alice);
        for (uint256 i; i < 34; ++i) {
            uint16 sid = register(bob, t1Spec(address(uint160(0xCAFE + i)), string.concat("S", vm.toString(i))));
            bytes32 rid = ask(alice, sid);
            assertTrue(deliver(rid, attestationFor(rid, word(1))));
        }
        Card memory c = renderer.cardOfOn(address(registry), id);
        assertEq(c.communityCount, 34);
        assertEq(c.community.length, 32);
        assertEq(c.oracle.length, 32);
        assertEq(c.community[0], 10001);
        assertEq(c.community[31], 10032);
        assertEq(registry.verifiedSpecsOf(alice).length, 34);
        string memory metadata = string(renderer.preimageOf(c));
        assertEq(vm.parseJsonUint(metadata, ".attributes[14].value"), 34, "full community count");
        for (uint256 i; i < 32; ++i) {
            string memory prefix = string.concat(".attributes[", vm.toString(15 + i), "]");
            assertEq(
                vm.parseJsonString(metadata, string.concat(prefix, ".trait_type")),
                string.concat("Community ", vm.toString(10001 + i)),
                "community id is a standard attribute"
            );
            assertEq(
                vm.parseJsonString(metadata, string.concat(prefix, ".value")),
                string.concat("S", vm.toString(i)),
                "community name is a standard attribute"
            );
        }
        assertFalse(vm.keyExistsJson(metadata, ".attributes[47]"), "only the first 32 are shown");
        assertGt(bytes(registry.tokenURI(id)).length, 0);
    }

    // ------------------------------------------------------------------ 11: re-entrancy through the token

    function test_reentrantTokenCannotReenterAnyIMDMovingFunction() public {
        ReentrantIMD evil = new ReentrantIMD();
        // An Intake selling in the evil token, so a re-entered upgrade or shared-fact request could
        // otherwise complete.
        MockIntake evilIntake = new MockIntake(address(evil));
        Registry r = new Registry(
            CURATOR_ADDR,
            address(evil),
            address(evilIntake),
            attester,
            address(renderer),
            address(composer),
            address(executor)
        );
        evil.mint(alice, 100 ether);
        vm.prank(alice);
        evil.approve(address(r), type(uint256).max);
        // The re-entered call comes from the token contract: fund and approve it, so the guard is the
        // only thing that can refuse it.
        evil.mint(address(evil), 100 ether);
        vm.prank(address(evil));
        evil.approve(address(r), type(uint256).max);
        bytes[4] memory payloads = _reentryPayloads(r);
        bytes memory guardError = abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        for (uint256 i; i < 4; ++i) {
            evil.arm(payloads[i]);
            vm.prank(alice);
            r.registerSpec(t1Spec(CURATOR_ADDR, "Reentry"), 0);
            assertTrue(evil.reentryReverted(), "the guard refused the re-entered call");
            assertEq(evil.reentryError(), guardError, "exactly ReentrancyGuardReentrantCall");
        }
        assertEq(r.nextSpecId(), 10005);
        assertEq(r.pendingOf(address(evil), 701), bytes32(0));
        assertEq(r.sharedPending(1201), bytes32(0));
        assertEq(r.tokenOf(address(evil)), 0);
        assertEq(evil.balanceOf(address(r)), 0);

        // Unguarded positive control: the same funded, approved attacker and the same payloads, fired
        // from a frame that holds no guard (the token's transferFrom called with the registry as
        // sender), succeed. The refusals above are the guard's, not a harness artefact.
        for (uint256 i; i < 4; ++i) {
            evil.arm(payloads[i]);
            vm.prank(address(r));
            evil.transferFrom(address(evil), address(r), 0);
            assertFalse(evil.reentryReverted(), "the unguarded re-entry succeeds");
            assertEq(evil.reentryError(), "");
        }
        assertEq(r.pendingOf(address(evil), 701) != bytes32(0), true);
        assertEq(r.nextSpecId(), 10006);
        assertEq(r.sharedPending(1201) != bytes32(0), true);
        assertEq(r.tokenOf(address(evil)), 1);
    }

    function _reentryPayloads(Registry r) internal pure returns (bytes[4] memory payloads) {
        uint16[] memory ids = new uint16[](1);
        ids[0] = 701;
        payloads[0] = abi.encodeCall(r.upgrade, (ids, PRICE));
        payloads[1] = abi.encodeCall(r.registerSpec, (t1Spec(address(0xCAFE), "Evil"), 0));
        payloads[2] = abi.encodeCall(r.requestSharedFact, (1201, PRICE));
        payloads[3] = abi.encodeCall(r.mintCard, ());
    }

    function test_onFailureRecordsWhatItIsToldAndStoresNothing() public {
        bytes32 rid = ask(alice, 701);
        vm.prank(address(intake));
        vm.expectEmit(false, false, false, true);
        emit Registry.NoVerdict(rid, 701, 1, "body_invalid", 65535, 65535);
        registry.onFailure(rid, 1, "body_invalid", 65535, 65535, hex"deadbeef");
        assertEq(registry.pendingOf(alice, 701), bytes32(0));
        assertFalse(registry.hasTrait(alice, 701));
        assertEq(imd.balanceOf(address(registry)), 0);
        // the Intake refuses a failure envelope that names another request or status
        bytes32 rid2 = ask(alice, 801);
        vm.expectRevert();
        intake.complete(rid2, 1, abi.encode(rid, uint8(1), bytes32(0), uint16(0), uint16(0), bytes("")));
        vm.expectRevert();
        intake.complete(rid2, 1, abi.encode(rid2, uint8(2), bytes32(0), uint16(0), uint16(0), bytes("")));
        assertEq(registry.pendingOf(alice, 801), rid2);
    }
}
