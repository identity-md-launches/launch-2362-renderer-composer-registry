// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Base} from "./Base.t.sol";
import {Registry} from "../src/Registry.sol";
import {Composer} from "../src/Composer.sol";
import {TemplateData} from "../src/TemplateData.sol";
import {HiveData} from "../src/HiveData.sol";
import {OracleAttestation} from "../src/interfaces/IOracleConsumer.sol";
import {Spec} from "../src/Types.sol";

/// @notice Independent edge and failure-path tests for docs/V2.md items 1 to 21, beside `V2.t.sol`:
///         the boundaries of every new limit, the callers the code must refuse, and the transfer rule.
contract V2EdgesTest is Base {
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal carol = address(0xCA201);

    function setUp() public override {
        super.setUp();
        curator.set(alice, 1, true, 1, 1, 1);
        curator.set(bob, 1, true, 1, 1, 1);
    }

    function _one(uint16 id) internal pure returns (uint16[] memory ids) {
        ids = new uint16[](1);
        ids[0] = id;
    }

    /// forge-config: default.fuzz.runs = 512

    // ------------------------------------------------------------------ item 2: zero price

    function test_item2_zeroPriceRevertsOnSharedFacts() public {
        intake.setPrice(0);
        fund(bob, 1 ether);
        vm.prank(bob);
        vm.expectRevert(Registry.ZeroPrice.selector);
        registry.requestSharedFact(1201, 1 ether);
    }

    function test_item2_priceAboveMaxOnPaidPaths() public {
        intake.setPrice(1 ether);
        fund(bob, 2 ether);
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(Registry.PriceAboveMax.selector, 1 ether, 1 ether - 1));
        registry.upgrade(_one(701), 1 ether - 1);
        vm.expectRevert(abi.encodeWithSelector(Registry.PriceAboveMax.selector, 1 ether, 0));
        registry.requestSharedFact(1201, 0);
        vm.expectRevert(Registry.NoTraits.selector);
        registry.upgrade(new uint16[](0), 1 ether);
        vm.stopPrank();
        assertEq(imd.balanceOf(bob), 2 ether, "nothing pulled");
    }

    // ------------------------------------------------------------------ items 3 and 7: release and one completion

    function test_item7_callbacksRefuseEveryCallerButTheIntake() public {
        bytes32 rid = ask(alice, 701);
        OracleAttestation memory a = attestationFor(rid, word(1));
        bytes memory sig = sign(a);
        vm.prank(alice);
        vm.expectRevert(Registry.NotIntake.selector);
        registry.onResult(rid, a, sig);
        vm.prank(alice);
        vm.expectRevert(Registry.NotIntake.selector);
        registry.onFailure(rid, 2, "disagreed", 0, 0, "");
        assertEq(registry.pendingOf(alice, 701), rid, "still pending");
    }

    function test_item7_unknownIdFromTheIntakeMissesWithReasonOne() public {
        bytes32 rid = ask(alice, 701);
        OracleAttestation memory a = attestationFor(rid, word(1));
        assertTrue(deliver(rid, a));
        assertTrue(registry.hasTrait(alice, 701));
        // the same signed attestation against a forged id from the Intake itself
        bytes memory sig = sign(a);
        vm.expectEmit(false, false, false, true, address(registry));
        emit Registry.Missed(keccak256("other"), 0, 1);
        vm.prank(address(intake));
        registry.onResult(keccak256("other"), a, sig);
        vm.expectEmit(false, false, false, true, address(registry));
        emit Registry.Missed(rid, 0, 1);
        vm.prank(address(intake));
        registry.onFailure(rid, 2, "disagreed", 0, 0, "");
        assertTrue(registry.hasTrait(alice, 701), "a stale failure clears nothing");
    }

    function test_item7_wrongSignerAndTamperedAnswerMiss() public {
        bytes32 rid = ask(alice, 701);
        OracleAttestation memory a = attestationFor(rid, word(1));
        bytes memory forged = signWith(0xB4D, a);
        vm.expectEmit(false, false, false, true, address(registry));
        emit Registry.Missed(rid, 701, 2);
        assertTrue(deliver(rid, a, forged));
        assertFalse(registry.hasTrait(alice, 701));
        bytes32 r2 = ask(alice, 701);
        OracleAttestation memory b = attestationFor(r2, word(1));
        bytes memory sig = sign(b);
        b.answer = word(2); // signed over 1
        vm.expectEmit(false, false, false, true, address(registry));
        emit Registry.Missed(r2, 701, 2);
        assertTrue(deliver(r2, b, sig));
        assertFalse(registry.hasTrait(alice, 701));
    }

    // ------------------------------------------------------------------ item 5: abandon

    function test_item5_personalAbandonBoundariesAndCallers() public {
        bytes32 rid = ask(alice, 701);
        OracleAttestation memory late = attestationFor(rid, word(1));
        vm.warp(T0 + 31 days - 1);
        vm.prank(alice);
        vm.expectRevert(Registry.TooEarly.selector);
        registry.abandon(rid);
        vm.warp(T0 + 31 days + 1);
        vm.prank(bob);
        vm.expectRevert(Registry.NotClaimant.selector);
        registry.abandon(rid);
        vm.expectEmit(false, false, false, true, address(registry));
        emit Registry.Abandoned(rid);
        vm.prank(alice);
        registry.abandon(rid);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Registry.NotPending.selector, rid));
        registry.abandon(rid);
        vm.expectRevert(abi.encodeWithSelector(Registry.NotPending.selector, bytes32(0)));
        registry.abandon(bytes32(0));
        // the abandoned id's late answer misses with reason 1 and lights nothing
        late.expiresAt = uint64(block.timestamp + 1 days);
        vm.expectEmit(false, false, false, true, address(registry));
        emit Registry.Missed(rid, 0, 1);
        assertTrue(deliver(rid, late));
        assertFalse(registry.hasTrait(alice, 701));
    }

    function test_item5_sharedFactCanBeClearedByAnyone() public {
        fund(bob, PRICE);
        vm.prank(bob);
        registry.requestSharedFact(1201, PRICE);
        bytes32 rid = intake.lastId();
        vm.warp(T0 + 31 days + 1);
        vm.prank(alice);
        registry.abandon(rid);
        fund(alice, PRICE);
        vm.prank(alice);
        registry.requestSharedFact(1201, PRICE);
        assertEq(registry.sharedPending(1201), intake.lastId());
    }

    // ------------------------------------------------------------------ item 9: expectedId

    function test_item9_expectedIdAheadOrBehindReverts() public {
        Spec memory s = t1Spec(CURATOR_ADDR, "Ahead");
        fund(alice, 2 * registry.SPEC_FEE());
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(Registry.UnexpectedSpecId.selector, 10002, 10001));
        registry.registerSpec(s, 10002);
        vm.expectRevert(abi.encodeWithSelector(Registry.UnexpectedSpecId.selector, 10000, 10001));
        registry.registerSpec(s, 10000);
        vm.expectRevert(abi.encodeWithSelector(Registry.UnexpectedSpecId.selector, 10001 + 65536, 10001));
        registry.registerSpec(s, 10001 + 65536); // no truncation of the uint256 argument
        assertEq(registry.registerSpec(s, 10001), 10001);
        vm.stopPrank();
        assertEq(imd.balanceOf(alice), registry.SPEC_FEE(), "one fee pulled");
        assertEq(registry.nextSpecId(), 10002);
    }

    // ------------------------------------------------------------------ items 12, 13, 14: cards

    function test_item12_totalSupplyCountsMintsNotTransfersAndOneCardPerWallet() public {
        assertEq(registry.totalSupply(), 0);
        uint256 id = mint(alice);
        fund(alice, 0.1 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Registry.AlreadyMinted.selector, alice));
        registry.mintCard();
        vm.prank(alice);
        registry.transferFrom(alice, bob, id);
        assertEq(registry.totalSupply(), 1);
        // a transferred card does not block the minter's second mint guard nor the buyer's own mint
        fund(alice, 0.1 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Registry.AlreadyMinted.selector, alice));
        registry.mintCard();
        uint256 bid = mint(bob);
        assertEq(bid, 2);
        assertEq(registry.totalSupply(), 2);
        assertEq(registry.balanceOf(bob), 2);
        vm.expectRevert(abi.encodeWithSelector(Registry.NoCard.selector, 3));
        registry.tokenURI(3);
        vm.expectRevert(abi.encodeWithSelector(Registry.NoCard.selector, 0));
        registry.tokenURI(0);
    }

    /// @dev Item 8 makes a community T3 answer exactly `threshold` addresses long, so the spec's head is the
    ///      length the callback walks under its 200,000 gas; it must stay within 1..32 or a registered spec
    ///      could never be answered. A refused registration keeps the fee and the id.
    /// forge-config: default.fuzz.runs = 256
    function testFuzz_item8_kind3HeadRegistersExactlyWithinOneToThirtyTwo(uint256 head) public {
        head = bound(head, 0, 1000);
        Spec memory s;
        s.kind = 3;
        s.target = address(0x1234);
        s.item = "event Transfer(address indexed from, address indexed to, uint256 value)";
        s.arg = "to";
        s.sumArg = "value";
        s.threshold = head;
        s.fromBlock = B_DEPLOY;
        s.toBlock = B_END;
        s.name = "Head";
        uint256 fee = registry.SPEC_FEE();
        fund(alice, fee);
        bool ok = head >= 1 && head <= 32;
        vm.prank(alice);
        if (!ok) vm.expectRevert(abi.encodeWithSelector(Composer.BadSpec.selector, "threshold"));
        registry.registerSpec(s, 0);
        assertEq(registry.nextSpecId(), ok ? 10002 : 10001);
        assertEq(imd.balanceOf(alice), ok ? 0 : fee);
    }

    /// @dev A complete 1201 answer (V2 item 8: exactly the head of 32 addresses) holding `first` and,
    ///      unless zero, `second`; the rest are distinct wallets that never act in these tests.
    function _headList(address first, address second) internal pure returns (address[] memory list) {
        list = new address[](32);
        for (uint256 i; i < 32; ++i) {
            list[i] = address(uint160(0x5000 + i));
        }
        list[0] = first;
        if (second != address(0)) list[31] = second;
    }

    function test_item13_unsolicitedRecipientKeepsItsOwnPowers() public {
        imd.mint(address(registry), 100 ether);
        uint256 id = mint(alice);
        uint32 snap = registry.frozenDirect(id);
        // bob holds alice's card, unasked
        vm.prank(alice);
        registry.transferFrom(alice, bob, id);
        assertEq(registry.tokenOf(bob), 0);
        bytes32 rs = ask(bob, 701);
        assertTrue(deliver(rs, attestationFor(rs, word(1))));
        bytes32 rp = ask(bob, 801);
        assertTrue(deliver(rp, attestationFor(rp, word(1))));
        address[] memory list = _headList(alice, bob);
        fund(carol, PRICE);
        vm.prank(carol);
        registry.requestSharedFact(1201, PRICE);
        bytes32 rf = intake.lastId();
        assertTrue(deliver(rf, attestationFor(rf, abi.encode(list))));
        vm.prank(bob);
        registry.applySharedFact(1201, list);
        assertTrue(registry.hasTrait(bob, 701) && registry.hasTrait(bob, 801) && registry.hasTrait(bob, 1201));
        // the card's minter facts and snapshot are untouched by what its holder did
        assertEq(registry.claimantOf(id), alice);
        assertEq(registry.tokenOf(alice), id);
        assertEq(registry.frozenDirect(id), snap);
        assertFalse(registry.hasTrait(alice, 701) || registry.hasTrait(alice, 801) || registry.hasTrait(alice, 1201));
        // the holder transferring onwards cannot move the minter's facts either
        vm.prank(bob);
        registry.transferFrom(bob, carol, id);
        assertEq(registry.claimantOf(id), alice);
        // bob may still mint his own card later, which freezes his own direct traits
        uint256 bid = mint(bob);
        assertEq(registry.claimantOf(bid), bob);
        assertTrue(registry.hasTrait(bob, 101));
    }

    function test_item13_minterKeepsFactsAfterSaleAndOnlyMinterCanApplyItsListEntry() public {
        uint256 id = mint(alice);
        vm.prank(alice);
        registry.transferFrom(alice, bob, id);
        address[] memory list = _headList(alice, address(0));
        fund(carol, PRICE);
        vm.prank(carol);
        registry.requestSharedFact(1201, PRICE);
        bytes32 rf = intake.lastId();
        assertTrue(deliver(rf, attestationFor(rf, abi.encode(list))));
        vm.prank(bob);
        vm.expectRevert(Registry.NotInList.selector);
        registry.applySharedFact(1201, list);
        vm.prank(alice);
        registry.applySharedFact(1201, list);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Registry.AlreadyVerified.selector, alice, 1201));
        registry.applySharedFact(1201, list);
        address[] memory other = new address[](1);
        other[0] = bob;
        vm.prank(bob);
        vm.expectRevert(Registry.ListMismatch.selector);
        registry.applySharedFact(1201, other);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Registry.FactNotStored.selector, 10001));
        registry.applySharedFact(10001, list);
        assertTrue(registry.hasTrait(alice, 1201));
    }

    function test_item14_operatorOffAtMintStaysOffAfterReceivingASeat() public {
        uint256 id = mint(alice);
        assertFalse(registry.hasTrait(alice, 601));
        idmd.setBalance(alice, 3);
        assertFalse(registry.hasTrait(alice, 601), "snapshot");
        assertEq(registry.frozenDirect(id) & (1 << 20), 0);
        // a wallet without a card never reads Swarmed live
        idmd.setBalance(carol, 1);
        assertFalse(registry.hasTrait(carol, 601));
        assertFalse(registry.hasDirectTrait(carol, 601));
    }

    function test_item13_snapshotBitsMatchEveryDirectId() public {
        curator.set(carol, 0, true, 10, 800 ether, 10_000);
        idmd.setBalance(carol, 1);
        uint256 id = mint(carol);
        uint16[13] memory direct = [101, 201, 202, 301, 302, 303, 401, 402, 403, 404, 501, 502, 503];
        for (uint256 i; i < 13; ++i) {
            assertTrue(registry.hasDirectTrait(carol, direct[i]));
        }
        // 13 bits exactly; bit 20 is permanently unused, at (family - 1) * 4 + tier - 1
        uint32 bits = registry.frozenDirect(id);
        assertEq(bits, uint32((1 << 0) | (3 << 4) | (7 << 8) | (15 << 12) | (7 << 16)));
        curator.set(carol, 9, false, 0, 0, 0);
        idmd.setBalance(carol, 0);
        for (uint256 i; i < 13; ++i) {
            assertTrue(registry.hasTrait(carol, direct[i]), "frozen");
        }
        assertFalse(registry.hasDirectTrait(carol, 701), "not a direct id");
        assertFalse(registry.hasTrait(address(0), 101));
    }

    // ------------------------------------------------------------------ item 16: finality margin

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_item16_registersExactlyWhenSixtyFourBlocksDeep(uint256 depth) public {
        depth = bound(depth, 0, 200);
        Spec memory s = t1Spec(CURATOR_ADDR, "Deep");
        s.toBlock = uint64(block.number - depth);
        s.fromBlock = s.toBlock - 7199;
        fund(alice, registry.SPEC_FEE());
        vm.prank(alice);
        if (depth < 64) vm.expectRevert(abi.encodeWithSelector(Composer.BadSpec.selector, "window"));
        registry.registerSpec(s, 0);
        assertEq(registry.nextSpecId(), depth < 64 ? 10001 : 10002);
    }

    function test_item16_futureWindowAndShortWindowRefused() public {
        Spec memory s = t1Spec(CURATOR_ADDR, "Future");
        s.fromBlock = uint64(block.number);
        s.toBlock = uint64(block.number + 7199);
        fund(alice, registry.SPEC_FEE());
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(Composer.BadSpec.selector, "window"));
        registry.registerSpec(s, 0);
        s.toBlock = uint64(block.number - 64);
        s.fromBlock = s.toBlock - 7198; // 7199 blocks
        vm.expectRevert(abi.encodeWithSelector(Composer.BadSpec.selector, "window"));
        registry.registerSpec(s, 0);
        vm.stopPrank();
        assertEq(imd.balanceOf(alice), registry.SPEC_FEE());
    }

    // ------------------------------------------------------------------ item 20: the generated tables tile

    function _u16(bytes memory hexAscii, uint256 i) internal pure returns (uint256 v) {
        for (uint256 k; k < 4; ++k) {
            uint8 c = uint8(hexAscii[i * 4 + k]);
            uint256 d = c >= 97 ? c - 87 : c >= 65 ? c - 55 : c - 48;
            assertLt(d, 16, "hex digit");
            v = v * 16 + d;
        }
    }

    function _assertStartsTile(bytes memory starts, uint256 count, uint256 blobLength) internal pure {
        assertEq(starts.length, (count + 1) * 4, "N+1 starts");
        assertEq(_u16(starts, 0), 0, "starts at zero");
        for (uint256 i; i < count; ++i) {
            assertGt(_u16(starts, i + 1), _u16(starts, i), "no empty or overlapping entry");
        }
        assertEq(_u16(starts, count), blobLength, "ends at the blob length");
    }

    function test_item20_templateSlicesTileTheEnvelope() public pure {
        bytes memory offs = TemplateData.OFFSETS;
        assertEq(offs.length, TemplateData.SLICES * 8);
        assertEq(TemplateData.SLICES, TemplateData.SLOTS + 1);
        uint256 cursor;
        for (uint256 i; i < TemplateData.SLICES; ++i) {
            uint256 start = _u16(offs, 2 * i);
            uint256 len = _u16(offs, 2 * i + 1);
            assertEq(start, cursor, "zero gap, zero overlap");
            cursor = start + len;
        }
        assertEq(cursor, TemplateData.TEMPLATE.length, "the slices cover the whole envelope");
    }

    function test_item20_hiveTablesTile() public pure {
        _assertStartsTile(HiveData.POINT_STARTS, HiveData.POINT_COUNT, HiveData.POINTS.length);
        _assertStartsTile(HiveData.FRAGMENT_STARTS, HiveData.FRAGMENT_COUNT, HiveData.FRAGMENTS.length);
        assertEq(HiveData.CENTRE_BASE + 13, HiveData.POINT_COUNT, "13 family centres close the point table");
        assertEq(HiveData.F_OPACITY_78 + 1, HiveData.FRAGMENT_COUNT);
    }
}
