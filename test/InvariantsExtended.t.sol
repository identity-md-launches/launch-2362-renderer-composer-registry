// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Base} from "./Base.t.sol";
import {Registry} from "../src/Registry.sol";
import {OracleAttestation} from "../src/interfaces/IOracleConsumer.sol";
import {Spec} from "../src/Types.sol";

/// @notice A wider random walk over the registry (CONCEPT.md section 6, invariants 1, 2, 3, 4, 7, 9):
///         transfers. Ghost state records what the handler itself delivered, so the invariants can
///         say that a trait is marked exactly when a passing attestation was delivered for that pair,
///         twice. Expected reverts are guarded (`fail_on_revert = true`).
contract FullHandler is Base {
    address[] internal actors;
    uint16[] internal catalogOracle = [701, 801, 901, 1001, 1101, 1102, 1103, 1104, 1105, 1301];
    uint16[] internal catalogChain = [701, 801, 901, 1001, 1101, 1102, 1103, 1104, 1105];
    uint16[] public specIds;
    bytes32[] public openRequests; // pending ids the handler created and has not settled

    uint256 public deliveries;
    uint256 public replays; // replayConsumed calls that reached the registry
    mapping(address => mapping(uint16 => bool)) public ghostVerified;
    mapping(address => uint256) public ghostCommunityCount;
    mapping(bytes32 => bool) public ridConsumed; // a request id that has been completed or abandoned
    mapping(bytes32 => bool) public ridMarked; // a request id that marked a trait or a fact
    mapping(uint16 => bytes32) public specHash;
    mapping(uint16 => bool) public ghostFactStored;
    mapping(uint16 => address[]) internal factList;
    mapping(uint16 => address) public sharedPayer;

    constructor() {
        setUp();
        for (uint160 i = 1; i <= 4; ++i) {
            address a = address(0x2000 + i);
            actors.push(a);
            curator.set(a, i % 3, true, i * 2, i * 1e19, i * 1500);
            idmd.setOwner(i, a);
        }
        actors.push(address(0x2fff)); // a non-member without an IDMD
    }

    // ------------------------------------------------------------------ selection

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _oracleId(uint256 seed) internal view returns (uint16) {
        uint256 n = catalogOracle.length + specIds.length;
        uint256 i = seed % n;
        return i < catalogOracle.length ? catalogOracle[i] : specIds[i - catalogOracle.length];
    }

    function _removeOpen(bytes32 rid) internal {
        for (uint256 i; i < openRequests.length; ++i) {
            if (openRequests[i] == rid) {
                openRequests[i] = openRequests[openRequests.length - 1];
                openRequests.pop();
                return;
            }
        }
    }

    function _isT3(uint16 id) internal view returns (bool) {
        if (id == 1201) return true;
        return id >= 10001 && registry.specOf(id).kind == 3;
    }

    // ------------------------------------------------------------------ cards and money

    function mintCard(uint256 seed) external {
        address a = _actor(seed);
        if (registry.tokenOf(a) != 0) return;
        mint(a);
    }

    function transfer(uint256 seed, uint256 to) external {
        address a = _actor(seed);
        uint256 id = registry.tokenOf(a);
        if (id == 0 || registry.ownerOf(id) != a) return;
        vm.prank(a);
        registry.transferFrom(a, _actor(to), id);
    }

    // ------------------------------------------------------------------ asking

    function upgradePaid(uint256 seed, uint256 which) external {
        address a = _actor(seed);
        uint16 id = _oracleId(which);
        if (_isT3(id)) return;
        if (registry.pendingOf(a, id) != 0 || ghostVerified[a][id]) return;
        bytes32 rid = ask(a, id);
        openRequests.push(rid);
    }

    function advanceTime(uint32 elapsed) external {
        vm.warp(vm.getBlockTimestamp() + bound(elapsed, 1, 3 days));
    }

    function registerSpec(uint256 seed, uint8 kind) external {
        if (specIds.length >= 4) return;
        address a = _actor(seed);
        kind = uint8(bound(kind, 1, 5));
        Spec memory s;
        s.kind = kind;
        s.name = string.concat("Spec ", vm.toString(specIds.length));
        s.fromBlock = B_DEPLOY;
        s.toBlock = B_END;
        s.threshold = kind == 3 ? 3 : 2;
        if (kind != 5) {
            s.target = CURATOR_ADDR;
            s.item = kind == 4 ? "function pointsOf(address) view returns (uint256)" : composer.DEPOSITED();
        }
        if (kind <= 3) s.arg = "contributor";
        if (kind == 2 || kind == 3) s.sumArg = "amount";
        if (kind == 4) s.op = 1;
        if (kind == 5) s.toBlock = B_DEPLOY;
        if (kind == 5) s.fromBlock = B_DEPLOY;
        uint16 id = register(a, s);
        specIds.push(id);
        specHash[id] = keccak256(abi.encode(registry.specOf(id)));
    }

    function requestSharedFact(uint256 seed, uint256 which) external {
        address a = _actor(seed);
        uint16 id = 1201;
        if (which % 2 == 1) {
            for (uint256 i; i < specIds.length; ++i) {
                if (registry.specOf(specIds[i]).kind == 3) id = specIds[i];
            }
        }
        if (registry.sharedPending(id) != 0 || ghostFactStored[id]) return;
        fund(a, PRICE);
        vm.prank(a);
        registry.requestSharedFact(id, PRICE);
        sharedPayer[id] = a;
        openRequests.push(intake.lastId());
    }

    // ------------------------------------------------------------------ answering

    function _pick(uint256 seed) internal view returns (bytes32 rid, address c, uint16 t) {
        if (openRequests.length == 0) return (0, address(0), 0);
        rid = openRequests[seed % openRequests.length];
        (c, t,,) = registry.pendingRequest(rid);
    }

    function _answerFor(uint16 t, address c, bool truthful, uint256 seed) internal returns (bytes memory) {
        Spec memory s = registry.specOf(t);
        if (s.kind == 3) {
            // V2 item 8: a stored list is exactly `head` long; a truthful answer has that length
            uint256 n = truthful ? s.threshold : bound(seed, 1, 40);
            if (!truthful && n == s.threshold) n = s.threshold + 1;
            address[] memory list = new address[](n);
            for (uint256 i; i < n; ++i) {
                list[i] = address(uint160(0x9000 + i));
            }
            // put every actor in the first `head` slots when truthful, so applications succeed
            if (truthful) {
                for (uint256 i; i < actors.length && i < n && i < s.threshold; ++i) {
                    list[i] = actors[i];
                }
            }
            factList[t] = list;
            return abi.encode(list);
        }
        c; // the answer does not depend on the claimant
        if (s.kind == 1 || s.kind == 2) return abi.encode(truthful ? s.threshold + (seed % 3) : s.threshold - 1);
        return abi.encode(truthful ? 1 : 0);
    }

    function deliverTrue(uint256 seed) external {
        (bytes32 rid, address c, uint16 t) = _pick(seed);
        if (rid == 0) return;
        OracleAttestation memory a = attestationFor(rid, _answerFor(t, c, true, seed));
        (,, uint64 requestedAt,) = registry.pendingRequest(rid);
        a.issuedAt = requestedAt;
        a.expiresAt = requestedAt + 30 days;
        require(deliver(rid, a), "delivered");
        deliveries++;
        _removeOpen(rid);
        ridConsumed[rid] = true;
        bool accepted = block.timestamp <= uint256(a.issuedAt) + 30 days;
        if (!accepted) return;
        ridMarked[rid] = true;
        if (c == address(0)) {
            ghostFactStored[t] = true;
        } else {
            ghostVerified[c][t] = true;
            if (t >= 10001) ghostCommunityCount[c]++;
        }
    }

    function deliverFalse(uint256 seed) external {
        (bytes32 rid, address c, uint16 t) = _pick(seed);
        if (rid == 0 || c == address(0)) return;
        OracleAttestation memory a = attestationFor(rid, _answerFor(t, c, false, seed));
        require(deliver(rid, a), "delivered");
        deliveries++;
        _removeOpen(rid);
        ridConsumed[rid] = true;
    }

    function deliverTampered(uint256 seed, uint8 how) external {
        (bytes32 rid, address c, uint16 t) = _pick(seed);
        if (rid == 0) return;
        OracleAttestation memory a = attestationFor(rid, _answerFor(t, c, true, seed));
        bytes memory sig = sign(a);
        how = uint8(bound(how, 0, 6));
        if (how == 0) sig = signWith(0xBAD, a);
        else if (how == 1) a.questionHash = keccak256(abi.encode(a.questionHash));
        else if (how == 2) a.chainId = 4663;
        else if (how == 3) a.agreed = a.quorum - 1;
        else if (how == 4) a.toBlock = a.toBlock + 1;
        else if (how == 5) a.expiresAt = uint64(block.timestamp) - 1;
        else a.answerType = a.answerType == 0 ? 3 : 0;
        if (how != 0) sig = sign(a);
        require(deliver(rid, a, sig), "delivered");
        deliveries++;
        _removeOpen(rid);
        ridConsumed[rid] = true;
    }

    function failRequest(uint256 seed, uint8 status) external {
        (bytes32 rid,,) = _pick(seed);
        if (rid == 0) return;
        status = uint8(bound(status, 1, 2));
        require(fail(rid, status, status == 1 ? bytes32("body_refused") : bytes32("disagreed")), "delivered");
        _removeOpen(rid);
        ridConsumed[rid] = true;
    }

    function abandonLate(uint256 seed) external {
        (bytes32 rid,,) = _pick(seed);
        if (rid == 0) return;
        (address claimant, uint16 t, uint64 at,) = registry.pendingRequest(rid);
        if (block.timestamp < uint256(at) + 31 days + 1) vm.warp(uint256(at) + 31 days + 1);
        vm.prank(claimant != address(0) ? claimant : sharedPayer[t]);
        registry.abandon(rid);
        _removeOpen(rid);
        ridConsumed[rid] = true;
        // a late completion for the abandoned id is reason 1 and touches nothing
        OracleAttestation memory a;
        vm.prank(address(intake));
        registry.onResult(rid, a, "");
    }

    function replayConsumed(uint256 seed, uint256 which) external {
        // any settled id replayed through the Intake is a no-op
        address c = _actor(seed);
        uint16 t = _oracleId(which);
        (bytes32 rid,,,) = registry.verified(c, t);
        if (rid == 0) return;
        OracleAttestation memory a;
        vm.prank(address(intake));
        registry.onResult(rid, a, "");
        vm.prank(address(intake));
        registry.onFailure(rid, 1, "x", 0, 0, "");
        replays++;
    }

    function applyShared(uint256 seed, uint256 which) external {
        address a = _actor(seed);
        uint16 id = 1201;
        if (which % 2 == 1) {
            for (uint256 i; i < specIds.length; ++i) {
                if (registry.specOf(specIds[i]).kind == 3) id = specIds[i];
            }
        }
        if (!ghostFactStored[id] || ghostVerified[a][id]) return;
        address[] memory list = factList[id];
        uint256 head = registry.specOf(id).threshold;
        uint256 n = list.length < head ? list.length : head;
        bool inHead;
        for (uint256 i; i < n; ++i) {
            if (list[i] == a) inHead = true;
        }
        vm.prank(a);
        if (!inHead) {
            vm.expectRevert(Registry.NotInList.selector);
            registry.applySharedFact(id, list);
            return;
        }
        registry.applySharedFact(id, list);
        ghostVerified[a][id] = true;
        if (id >= 10001) ghostCommunityCount[a]++;
    }

    // ------------------------------------------------------------------ views for the invariants

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function actorAt(uint256 i) external view returns (address) {
        return actors[i];
    }

    function oracleIds() external view returns (uint16[] memory ids) {
        ids = new uint16[](catalogOracle.length + 1 + specIds.length);
        uint256 k;
        for (uint256 i; i < catalogOracle.length; ++i) {
            ids[k++] = catalogOracle[i];
        }
        ids[k++] = 1201;
        for (uint256 i; i < specIds.length; ++i) {
            ids[k++] = specIds[i];
        }
    }

    function openCount() external view returns (uint256) {
        return openRequests.length;
    }

    function theRegistry() external view returns (Registry) {
        return registry;
    }
}

/// forge-config: default.invariant.runs = 96
/// forge-config: default.invariant.depth = 48
contract InvariantsExtendedTest is Test {
    function invariant_feesLeaveTheRegistry() public view {
        assertEq(registry.imd().balanceOf(address(registry)), 0);
    }
    FullHandler internal h;
    Registry internal registry;

    function setUp() public {
        h = new FullHandler();
        registry = h.theRegistry();
        targetContract(address(h));
        bytes4[] memory sel = new bytes4[](13);
        sel[0] = FullHandler.mintCard.selector;
        sel[1] = FullHandler.transfer.selector;
        sel[2] = FullHandler.upgradePaid.selector;
        sel[3] = FullHandler.registerSpec.selector;
        sel[4] = FullHandler.requestSharedFact.selector;
        sel[5] = FullHandler.deliverTrue.selector;
        sel[6] = FullHandler.deliverFalse.selector;
        sel[7] = FullHandler.deliverTampered.selector;
        sel[8] = FullHandler.failRequest.selector;
        sel[9] = FullHandler.abandonLate.selector;
        sel[10] = FullHandler.applyShared.selector;
        sel[11] = FullHandler.replayConsumed.selector;
        sel[12] = FullHandler.advanceTime.selector;
        targetSelector(FuzzSelector({addr: address(h), selectors: sel}));
    }

    function test_handlerReplayOfAConsumedIdChangesNothing() public {
        h.upgradePaid(0, 0); // actor 0x2001 asks for 701
        h.deliverTrue(0);
        address c = h.actorAt(0);
        (bytes32 rid,,,) = registry.verified(c, 701);
        assertTrue(rid != 0);
        h.replayConsumed(0, 0);
        assertEq(h.replays(), 1, "the replay reached onResult and onFailure");
        (bytes32 after_,,,) = registry.verified(c, 701);
        assertEq(after_, rid, "a replayed settled id leaves the verification intact");
        assertTrue(registry.hasTrait(c, 701));
        assertEq(registry.imd().balanceOf(address(registry)), 0);
    }

    /// @dev Invariants 3 and 4: a pair is marked exactly when the handler delivered a passing
    ///      attestation (or applied a stored fact) for that pair; a pending pair is never marked and
    ///      its record names exactly that pair.
    function invariant_markedExactlyWhenAPassingAttestationWasDelivered() public view {
        uint16[] memory ids = h.oracleIds();
        for (uint256 i; i < h.actorCount(); ++i) {
            address c = h.actorAt(i);
            uint256 community;
            for (uint256 j; j < ids.length; ++j) {
                uint16 t = ids[j];
                bool marked = registry.hasTrait(c, t);
                assertEq(marked, h.ghostVerified(c, t), "marked iff a passing delivery");
                (bytes32 rid,,,) = registry.verified(c, t);
                assertEq(rid != 0, marked);
                if (marked && t >= 10001) community++;
                bytes32 pending = registry.pendingOf(c, t);
                if (pending != 0) {
                    assertFalse(marked, "pending implies not verified");
                    (address pc, uint16 pt,,) = registry.pendingRequest(pending);
                    assertEq(pc, c);
                    assertEq(pt, t);
                }
            }
            assertEq(registry.verifiedSpecsOf(c).length, community, "community index has no duplicates");
            assertEq(community, h.ghostCommunityCount(c));
        }
    }

    /// @dev Invariants 1 and 2: one card per claimant, claimant immutable, the holder may differ.
    function invariant_oneCardPerClaimant() public view {
        for (uint256 i; i < h.actorCount(); ++i) {
            address c = h.actorAt(i);
            uint256 id = registry.tokenOf(c);
            if (id == 0) continue;
            assertEq(registry.claimantOf(id), c);
            assertTrue(registry.ownerOf(id) != address(0));
            assertEq(registry.mintedAtBlock(id) != 0, true);
        }
    }

    /// @dev Invariant 7: a registered spec never changes.
    function invariant_specsAreImmutable() public view {
        uint16[] memory ids = h.oracleIds();
        for (uint256 j; j < ids.length; ++j) {
            if (ids[j] < 10001) continue;
            assertEq(keccak256(abi.encode(registry.specOf(ids[j]))), h.specHash(ids[j]));
        }
    }

    /// @dev Invariant 9: a shared fact is a hash and a length at most 64, stored only after a
    ///      passing delivery; one pending request per fact id.
    function invariant_sharedFactsAreHashesStoredOnlyOnDelivery() public view {
        uint16[] memory ids = h.oracleIds();
        for (uint256 j; j < ids.length; ++j) {
            uint16 t = ids[j];
            if (t != 1201 && (t < 10001 || registry.specOf(t).kind != 3)) continue;
            (bytes32 rid, bytes32 hash, uint16 n) = registry.sharedFact(t);
            assertEq(rid != 0, h.ghostFactStored(t));
            if (rid != 0) {
                assertTrue(n >= 1 && n <= 64);
                assertTrue(hash != bytes32(0));
                assertEq(registry.sharedPending(t), bytes32(0), "stored facts have no pending request");
            }
        }
    }
}
