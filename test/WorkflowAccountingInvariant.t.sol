// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Base} from "./Base.t.sol";
import {Registry} from "src/Registry.sol";
import {OracleAttestation} from "src/interfaces/IOracleConsumer.sol";
import {Spec} from "src/Types.sol";

/// @notice Fixed actor budgets and independent receipts reconcile every successful paid operation.
/// No tokens are created after setup. Callbacks, transfers and abandonment must never change fees.
contract WorkflowAccountingHandler is Base {
    uint256 public constant BUDGET = 1_000 ether;
    address[4] public actors;
    mapping(address => uint256) public executorSpent;
    mapping(address => uint256) public oracleSpent;
    mapping(address => uint256) public card;
    mapping(uint256 => address) public cardOwner;
    mapping(uint256 => uint32) public snapshot;
    mapping(uint256 => uint64) public mintBlock;
    mapping(address => mapping(uint16 => bytes32)) public accepted;
    mapping(address => mapping(uint16 => bytes32)) public openPair;
    mapping(address => uint64) public acceptedOperatorEnd;
    uint16[] public specs;
    mapping(uint16 => bytes32) public specCommitment;
    uint256 public mints;
    uint256 public requests;
    uint256 public results;
    uint256 public failures;
    uint256 public abandons;
    uint256 public lateCallbacks;

    struct RequestReceipt {
        bytes32 id;
        address claimant;
        uint16 trait;
        uint64 at;
        uint64 from;
        uint64 to;
        bytes32 question;
        bool closed;
    }

    RequestReceipt[] internal receipts;
    bytes32 public openShared;
    bytes32 public storedShared;
    bytes32 public storedSharedHash;
    address[] internal sharedList;

    constructor() {
        setUp();
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("workflow actor ", vm.toString(i)));
            fund(actors[i], BUDGET);
            curator.set(actors[i], i, true, i * 4, i * 20 ether, i * 4000);
        }
        for (uint256 i; i < 32; ++i) {
            sharedList.push(i < actors.length ? actors[i] : makeAddr(string.concat("list member ", vm.toString(i))));
        }
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _trait(uint256 seed) internal view returns (uint16) {
        uint256 index = seed % (3 + specs.length);
        if (index == 0) return 601;
        if (index == 1) return 701;
        if (index == 2) return 1301;
        return specs[index - 3];
    }

    function mintCard(uint256 seed) external {
        address actor = _actor(seed);
        vm.prank(actor);
        if (card[actor] != 0) {
            vm.expectRevert(abi.encodeWithSelector(Registry.AlreadyMinted.selector, actor));
            registry.mintCard();
            return;
        }
        uint256 id = registry.mintCard();
        ++mints;
        assertEq(id, mints, "sequential, unique card ids");
        card[actor] = id;
        cardOwner[id] = actor;
        snapshot[id] = registry.frozenDirect(id);
        mintBlock[id] = uint64(vm.getBlockNumber());
        executorSpent[actor] += 0.1 ether;
    }

    function transferCard(uint256 seed, uint256 destination, bool approved) external {
        if (mints == 0) return;
        uint256 id = seed % mints + 1;
        address owner = cardOwner[id];
        address to = _actor(destination);
        address operator = approved ? _actor(destination % actors.length + 1) : owner;
        // Approval is only needed when the chosen actor is not the present holder.
        if (operator != owner) {
            vm.prank(owner);
            registry.approve(operator, id);
        }
        vm.prank(operator);
        registry.transferFrom(owner, to, id);
        cardOwner[id] = to;
    }

    function changeLiveReads(uint256 seed, uint256 value) external {
        address actor = _actor(seed);
        value = bound(value, 0, 10000);
        curator.set(actor, value % 66, value % 2 == 0, value, value * 1 ether, value);
    }

    function registerSpec(uint256 seed) external {
        if (specs.length == 8) return;
        address actor = _actor(seed);
        Spec memory s = t1Spec(CURATOR_ADDR, "Sequence receipt");
        s.threshold = 1 + specs.length;
        vm.prank(actor);
        uint16 id = registry.registerSpec(s, 10001 + specs.length);
        specCommitment[id] = keccak256(abi.encode(s));
        specs.push(id);
        executorSpent[actor] += 6.4 ether;
    }

    function changePrice(uint256 value) external {
        intake.setPrice(bound(value, 0, 1 ether));
    }

    function _remember(bytes32 id, address actor, uint16 trait) internal {
        (address c, uint16 t, uint64 at, bytes32 q) = registry.pendingRequest(id);
        assertEq(c, actor);
        assertEq(t, trait);
        assertEq(at, vm.getBlockTimestamp());
        Spec memory s = registry.specOf(trait);
        receipts.push(RequestReceipt(id, actor, trait, at, s.fromBlock, s.toBlock, q, false));
        if (actor == address(0)) openShared = id;
        else openPair[actor][trait] = id;
        ++requests;
    }

    function askPersonal(uint256 seed, uint256 which, bool tooCheap) external {
        address actor = _actor(seed);
        uint16 trait = _trait(which);
        if (openPair[actor][trait] != 0 || accepted[actor][trait] != 0) return;
        uint256 price = intake.price();
        uint16[] memory ids = new uint16[](1);
        ids[0] = trait;
        vm.prank(actor);
        if (price == 0) {
            vm.expectRevert(Registry.ZeroPrice.selector);
            registry.upgrade(ids, 0);
        } else if (tooCheap) {
            vm.expectRevert(abi.encodeWithSelector(Registry.PriceAboveMax.selector, price, price - 1));
            registry.upgrade(ids, price - 1);
        } else {
            registry.upgrade(ids, price);
            oracleSpent[actor] += price;
            _remember(intake.lastId(), actor, trait);
        }
    }

    function duplicateBatch(uint256 seed, uint256 which) external {
        address actor = _actor(seed);
        uint16 trait = _trait(which);
        uint256 price = intake.price();
        if (price == 0 || openPair[actor][trait] != 0 || accepted[actor][trait] != 0) return;
        uint16[] memory ids = new uint16[](2);
        ids[0] = trait;
        ids[1] = trait;
        vm.prank(actor);
        vm.expectRevert(abi.encodeWithSelector(Registry.AlreadyPending.selector, actor, trait));
        registry.upgrade(ids, price);
        assertEq(registry.pendingOf(actor, trait), bytes32(0), "first request rolled back");
    }

    function askShared(uint256 seed) external {
        if (openShared != 0 || storedShared != 0 || intake.price() == 0) return;
        address actor = _actor(seed);
        uint256 price = intake.price();
        vm.prank(actor);
        registry.requestSharedFact(1201, price);
        oracleSpent[actor] += price;
        _remember(intake.lastId(), address(0), 1201);
    }

    function advance(uint256 elapsed, uint256 blocks) external {
        vm.warp(vm.getBlockTimestamp() + bound(elapsed, 1, 32 days));
        vm.roll(vm.getBlockNumber() + bound(blocks, 1, 1024));
    }

    function _close(RequestReceipt storage r) internal {
        r.closed = true;
        if (r.claimant == address(0)) openShared = 0;
        else openPair[r.claimant][r.trait] = 0;
    }

    function complete(uint256 seed, uint8 outcome) external {
        if (receipts.length == 0) return;
        RequestReceipt storage r = receipts[seed % receipts.length];
        if (r.closed) return;
        outcome = uint8(bound(outcome, 0, 4));
        if (outcome == 4) {
            assertTrue(fail(r.id, 2, "disagreed"), "failure callback delivered");
            ++failures;
            _close(r);
            return;
        }
        Spec memory s = registry.specOf(r.trait);
        bytes memory answer = s.kind == 3 ? abi.encode(sharedList) : word(s.kind == 1 ? s.threshold : 1);
        OracleAttestation memory a = attestationFor(r.id, answer);
        // The independent request receipt, not today's catalog window, fixes the signed window.
        a.fromBlock = r.from;
        a.toBlock = r.to;
        a.issuedAt = r.at;
        a.expiresAt = r.at + 30 days;
        if (outcome == 1) a.answer = word(0);
        if (outcome == 2) a.questionHash ^= bytes32(uint256(1));
        if (outcome == 3) a.agreed = a.quorum - 1;
        bytes memory signature = sign(a);
        vm.cool(address(registry));
        assertTrue(deliver(r.id, a, signature), "result callback delivered within stipend");
        ++results;
        if (outcome == 0 && vm.getBlockTimestamp() <= uint256(r.at) + 30 days) {
            if (r.claimant == address(0)) {
                storedShared = r.id;
                storedSharedHash = keccak256(abi.encode(sharedList));
            } else {
                accepted[r.claimant][r.trait] = r.id;
                if (r.trait == 601) acceptedOperatorEnd[r.claimant] = r.to;
            }
        }
        _close(r);
    }

    function abandon(uint256 seed, uint256 callerSeed) external {
        if (receipts.length == 0) return;
        RequestReceipt storage r = receipts[seed % receipts.length];
        if (r.closed) return;
        address caller = _actor(callerSeed);
        vm.prank(caller);
        if (vm.getBlockTimestamp() <= uint256(r.at) + 31 days) {
            vm.expectRevert(Registry.TooEarly.selector);
            registry.abandon(r.id);
        } else if (r.claimant != address(0) && caller != r.claimant) {
            vm.expectRevert(Registry.NotClaimant.selector);
            registry.abandon(r.id);
        } else {
            registry.abandon(r.id);
            ++abandons;
            _close(r);
        }
    }

    function replayClosed(uint256 seed) external {
        if (receipts.length == 0) return;
        RequestReceipt storage r = receipts[seed % receipts.length];
        if (!r.closed) return;
        OracleAttestation memory a;
        vm.prank(address(intake));
        registry.onResult(r.id, a, "");
        vm.prank(address(intake));
        registry.onFailure(r.id, 1, "body_refused", 0, 0, "");
        ++lateCallbacks;
    }

    function applyShared(uint256 seed, bool wrongList) external {
        if (storedShared == 0) return;
        address actor = _actor(seed);
        address[] memory list = sharedList;
        if (wrongList) {
            (list[0], list[1]) = (list[1], list[0]);
            vm.prank(actor);
            vm.expectRevert(Registry.ListMismatch.selector);
            registry.applySharedFact(1201, list);
        } else if (accepted[actor][1201] != 0) {
            vm.prank(actor);
            vm.expectRevert(abi.encodeWithSelector(Registry.AlreadyVerified.selector, actor, uint16(1201)));
            registry.applySharedFact(1201, list);
        } else {
            vm.prank(actor);
            registry.applySharedFact(1201, list);
            accepted[actor][1201] = storedShared;
        }
    }

    function assertAccounting() external view {
        uint256 toExecutor;
        uint256 toIntake;
        uint256 balances;
        for (uint256 i; i < actors.length; ++i) {
            address actor = actors[i];
            toExecutor += executorSpent[actor];
            toIntake += oracleSpent[actor];
            balances += imd.balanceOf(actor);
            assertEq(imd.balanceOf(actor) + executorSpent[actor] + oracleSpent[actor], BUDGET, "claimant budget");
        }
        assertEq(toExecutor, mints * 0.1 ether + specs.length * 6.4 ether, "fee schedule");
        assertEq(imd.balanceOf(address(executor)), toExecutor, "executor receipts");
        assertEq(imd.balanceOf(address(intake)), toIntake, "oracle receipts");
        assertEq(balances + toExecutor + toIntake, 4 * BUDGET, "conservation");
        assertEq(imd.totalSupply(), 4 * BUDGET, "no later fixture minting");
        assertEq(imd.balanceOf(address(registry)), 0, "no retained action funds");
        assertEq(imd.allowance(address(registry), address(intake)), 0, "no residual intake allowance");
        assertEq(intake.nonce(), requests, "failed requests roll back intake state");
    }

    function assertCardsAndFacts() external view {
        uint256 balances;
        for (uint256 i; i < actors.length; ++i) {
            address actor = actors[i];
            balances += registry.balanceOf(actor);
            assertEq(registry.tokenOf(actor), card[actor], "transfers do not change original claimant's card");
            if (card[actor] != 0) {
                uint256 id = card[actor];
                assertEq(registry.claimantOf(id), actor);
                assertEq(registry.ownerOf(id), cardOwner[id]);
                assertEq(registry.frozenDirect(id), snapshot[id], "mint snapshot never changes");
                assertEq(registry.frozenDirect(id) & (1 << 20), 0, "operator never becomes a direct bit");
                assertEq(registry.mintedAtBlock(id), mintBlock[id]);
            }
            uint256 community;
            for (uint256 j; j < 4 + specs.length; ++j) {
                uint16 trait = j == 3 + specs.length ? 1201 : _trait(j);
                (bytes32 rid,,, uint64 to) = registry.verified(actor, trait);
                assertEq(rid, accepted[actor][trait], "only accepted evidence grants a fact");
                assertEq(registry.hasTrait(actor, trait), rid != 0);
                assertEq(registry.pendingOf(actor, trait), openPair[actor][trait]);
                if (trait == 601 && rid != 0) assertEq(to, acceptedOperatorEnd[actor], "operator window frozen");
                if (trait >= 10001 && rid != 0) ++community;
            }
            uint16[] memory communityIds = registry.verifiedSpecsOf(actor);
            assertEq(communityIds.length, community, "community index contains exactly the accepted specs");
            for (uint256 j; j < communityIds.length; ++j) {
                assertTrue(accepted[actor][communityIds[j]] != 0, "community index contains accepted ids only");
                for (uint256 k; k < j; ++k) {
                    assertTrue(communityIds[j] != communityIds[k], "no duplicate index entries");
                }
            }
        }
        assertEq(registry.totalSupply(), mints);
        assertEq(balances, mints, "all cards remain owned");
        assertEq(registry.nextSpecId(), 10001 + specs.length);
        for (uint256 i; i < specs.length; ++i) {
            assertEq(keccak256(abi.encode(registry.specOf(specs[i]))), specCommitment[specs[i]]);
        }
        (bytes32 sharedRid, bytes32 hash, uint16 length) = registry.sharedFact(1201);
        assertEq(sharedRid, storedShared);
        assertEq(hash, storedSharedHash);
        assertEq(length, storedShared == 0 ? 0 : 32);
        assertEq(registry.sharedPending(1201), openShared);
    }

    function assertPendingRecords() external view {
        for (uint256 i; i < receipts.length; ++i) {
            RequestReceipt storage r = receipts[i];
            (address c, uint16 t, uint64 at, bytes32 q) = registry.pendingRequest(r.id);
            if (r.closed) {
                assertEq(abi.encode(c, t, at, q), abi.encode(address(0), uint16(0), uint64(0), bytes32(0)));
            } else {
                assertEq(abi.encode(c, t, at, q), abi.encode(r.claimant, r.trait, r.at, r.question));
                assertEq(c == address(0) ? registry.sharedPending(t) : registry.pendingOf(c, t), r.id);
            }
        }
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract WorkflowAccountingInvariantTest is Test {
    WorkflowAccountingHandler internal h;

    function setUp() public {
        h = new WorkflowAccountingHandler();
        targetContract(address(h));
        bytes4[] memory selectors = new bytes4[](13);
        selectors[0] = h.mintCard.selector;
        selectors[1] = h.transferCard.selector;
        selectors[2] = h.changeLiveReads.selector;
        selectors[3] = h.registerSpec.selector;
        selectors[4] = h.changePrice.selector;
        selectors[5] = h.askPersonal.selector;
        selectors[6] = h.duplicateBatch.selector;
        selectors[7] = h.askShared.selector;
        selectors[8] = h.advance.selector;
        selectors[9] = h.complete.selector;
        selectors[10] = h.abandon.selector;
        selectors[11] = h.replayClosed.selector;
        selectors[12] = h.applyShared.selector;
        targetSelector(FuzzSelector({addr: address(h), selectors: selectors}));
    }

    function invariant_everyFeeHasOnePayerAndOneDestination() public view {
        h.assertAccounting();
    }

    function invariant_claimantsSnapshotsAndAcceptedFactsSurviveSequences() public view {
        h.assertCardsAndFacts();
    }

    function invariant_pendingRecordsAndReverseIndicesAgree() public view {
        h.assertPendingRecords();
    }

    /// @notice Exercises every stateful action explicitly so random early returns cannot hide a dead handler.
    function test_handlerExercisesSuccessFailureRetryAndLateCallback() public {
        h.mintCard(0);
        h.mintCard(1);
        h.transferCard(0, 1, false);
        h.transferCard(0, 2, true);
        h.mintCard(0); // Original claimant cannot remint after transfer.
        h.changeLiveReads(0, 10000);
        h.registerSpec(1);
        h.changePrice(1);
        h.duplicateBatch(0, 0);
        h.askPersonal(0, 0, true);
        h.askPersonal(0, 0, false);
        h.advance(1, 1000);
        h.complete(0, 0); // Swarmed accepts the old, stored window.
        h.askShared(1);
        h.complete(1, 0);
        h.applyShared(0, true);
        h.applyShared(0, false);
        h.applyShared(0, false);
        h.askPersonal(2, 1, false);
        h.complete(2, 4);
        h.askPersonal(2, 1, false);
        h.replayClosed(2); // Prior failure cannot clear the successor.
        h.advance(32 days, 1);
        h.abandon(3, 1); // Wrong caller.
        h.abandon(3, 2);
        h.replayClosed(3);
        h.changePrice(0);
        h.askPersonal(3, 2, false);
        assertEq(h.mints(), 2);
        assertEq(h.requests(), 4);
        assertEq(h.results(), 2);
        assertEq(h.failures(), 1);
        assertEq(h.abandons(), 1);
        assertEq(h.lateCallbacks(), 2);
        h.assertAccounting();
        h.assertCardsAndFacts();
        h.assertPendingRecords();
    }
}
