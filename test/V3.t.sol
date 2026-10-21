// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Base} from "./Base.t.sol";
import {Registry} from "../src/Registry.sol";
import {Composer} from "../src/Composer.sol";
import {Renderer} from "../src/Renderer.sol";
import {Spec, Card, OracleMeta} from "../src/Types.sol";
import {OracleAttestation} from "../src/interfaces/IOracleConsumer.sol";

contract HostileCardSource {
    uint256 public mode;

    constructor(uint256 m) {
        mode = m;
    }

    function claimantOf(uint256) external pure returns (address) {
        return address(0x1234);
    }

    function traitsOf(address) external view returns (uint16[] memory ids) {
        ids = new uint16[](mode == 4 ? 26 : 1);
        ids[0] = mode == 3 ? 50 : mode == 5 ? 1400 : 601;
        if (mode == 4) {
            for (uint256 i; i < 25; ++i) {
                ids[i] = 101;
            }
            ids[25] = 601;
        }
    }

    function verifiedSpecsOf(address) external pure returns (uint16[] memory ids) {
        ids = new uint16[](0);
    }

    function verified(address, uint16) external pure returns (bytes32, bytes32, uint64, uint64) {
        return (bytes32(uint256(1)), bytes32(uint256(2)), 100, 200);
    }

    fallback() external {
        uint256 m = mode;
        if (m == 2) {
            bytes memory huge = new bytes(1_048_576);
            assembly ("memory-safe") { return(add(huge, 32), mload(huge)) }
        }
        bytes memory ret = new bytes(512);
        assembly ("memory-safe") {
            let ptr := add(ret, 32)
            switch m
            case 0 { mstore(ptr, shl(255, 1)) }
            default {
                mstore(ptr, 32)
                mstore(add(ptr, 384), sub(0, 200))
            }
            return(ptr, 512)
        }
    }
}

contract V3Test is Base {
    address internal alice = address(0xA11CE);
    address internal stranger = address(0xB0B);

    function _one(uint16 id) internal pure returns (uint16[] memory ids) {
        ids = new uint16[](1);
        ids[0] = id;
    }

    function _miss(bytes32 rid, OracleAttestation memory a, uint8 reason) internal {
        (, uint16 id,,) = registry.pendingRequest(rid);
        vm.expectEmit(false, false, false, true, address(registry));
        emit Registry.Missed(rid, id, reason);
        assertTrue(deliver(rid, a));
        (,, uint64 at,) = registry.pendingRequest(rid);
        assertEq(at, 0);
    }

    function test_feesForwardExactlyAndFailureIsAtomic() public {
        address executor = registry.burnExecutor();
        mint(alice);
        assertEq(imd.balanceOf(executor), registry.MINT_FEE());
        assertEq(imd.balanceOf(address(registry)), 0);
        register(alice, t1Spec(CURATOR_ADDR, "Receipt"));
        assertEq(imd.balanceOf(executor), registry.MINT_FEE() + registry.SPEC_FEE());
        assertEq(imd.balanceOf(address(registry)), 0);
        Spec memory bad = t1Spec(CURATOR_ADDR, "Invalid");
        bad.arg = "value";
        fund(alice, registry.SPEC_FEE());
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Composer.BadSpec.selector, "arg"));
        registry.registerSpec(bad, 0);
        assertEq(imd.balanceOf(alice), registry.SPEC_FEE());
        assertEq(registry.nextSpecId(), 10002);
        assertEq(imd.balanceOf(executor), registry.MINT_FEE() + registry.SPEC_FEE());
        vm.prank(stranger);
        vm.expectRevert();
        registry.mintCard();
        assertEq(registry.tokenOf(stranger), 0);
        assertEq(registry.totalSupply(), 1);
    }

    function test_sharedAbandonPermissionlessPersonalClaimantOnly() public {
        fund(alice, PRICE);
        vm.prank(alice);
        registry.requestSharedFact(1201, PRICE);
        bytes32 shared = intake.lastId();
        bytes32 personal = ask(alice, 701);
        vm.warp(T0 + 15 days);
        vm.prank(stranger);
        vm.expectRevert(Registry.TooEarly.selector);
        registry.abandon(shared);
        vm.warp(T0 + 32 days);
        vm.prank(stranger);
        registry.abandon(shared);
        assertEq(registry.sharedPending(1201), bytes32(0));
        vm.prank(stranger);
        vm.expectRevert(Registry.NotClaimant.selector);
        registry.abandon(personal);
        vm.prank(alice);
        registry.abandon(personal);
        assertEq(registry.pendingOf(alice, 701), bytes32(0));
    }

    function test_badIssuanceAndDurationMissWithSevenAndReleasePair() public {
        for (uint256 i; i < 3; ++i) {
            bytes32 rid = ask(alice, 701);
            OracleAttestation memory a = attestationFor(rid, word(1));
            if (i == 0) a.issuedAt = uint64(T0 - 1);
            if (i == 1) {
                a.issuedAt = uint64(T0 + 2 days);
                vm.warp(T0 + 2 days);
            }
            if (i == 2) a.expiresAt = a.issuedAt + 31 days;
            _miss(rid, a, 7);
            assertEq(registry.pendingOf(alice, 701), bytes32(0));
            vm.warp(T0);
        }
    }

    function test_issuedAt23HoursAndThirtyDaysValidityPasses() public {
        bytes32 rid = ask(alice, 701);
        vm.warp(T0 + 23 hours);
        OracleAttestation memory a = attestationFor(rid, word(1));
        assertTrue(deliver(rid, a));
        assertTrue(registry.hasTrait(alice, 701));
    }

    function test_abandonAndValidityNeverOverlapAtDeadlineInBothOrders() public {
        bytes32 rid = ask(alice, 701);
        OracleAttestation memory a = attestationFor(rid, word(1));
        a.issuedAt = uint64(T0 + 1 days);
        a.expiresAt = uint64(T0 + 31 days);
        vm.warp(T0 + 31 days);
        vm.prank(alice);
        vm.expectRevert(Registry.TooEarly.selector);
        registry.abandon(rid);
        uint256 snap = vm.snapshotState();
        assertTrue(deliver(rid, a));
        assertTrue(registry.hasTrait(alice, 701));
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Registry.NotPending.selector, rid));
        registry.abandon(rid);
        vm.revertToState(snap);
        vm.warp(T0 + 31 days + 1);
        snap = vm.snapshotState();
        _miss(rid, a, 7);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Registry.NotPending.selector, rid));
        registry.abandon(rid);
        vm.revertToState(snap);
        vm.prank(alice);
        registry.abandon(rid);
        vm.expectEmit(false, false, false, true, address(registry));
        emit Registry.Missed(rid, 0, 1);
        assertTrue(deliver(rid, a));
        assertFalse(registry.hasTrait(alice, 701));
    }

    function test_requestCollisionRollsBackTransferAndApprovalAndPending() public {
        bytes32 rid = ask(alice, 701);
        bytes memory body = intake.bodyOf(rid);
        fund(stranger, PRICE);
        uint256 before = imd.balanceOf(address(intake));
        intake.forceNextId(rid);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Registry.RequestIdTaken.selector, rid));
        registry.upgrade(_one(801), PRICE);
        assertEq(imd.balanceOf(stranger), PRICE);
        assertEq(imd.balanceOf(address(intake)), before);
        assertEq(imd.allowance(address(registry), address(intake)), 0);
        assertEq(registry.pendingOf(alice, 701), rid);
        assertEq(registry.pendingOf(stranger, 801), bytes32(0));
        assertEq(intake.bodyOf(rid), body);
    }

    function test_abandonedCallbackCannotClearSuccessor() public {
        bytes32 old = ask(alice, 601);
        OracleAttestation memory a = attestationFor(old, word(1));
        vm.warp(T0 + 32 days);
        vm.prank(alice);
        registry.abandon(old);
        vm.roll(vm.getBlockNumber() + 200);
        bytes32 fresh = ask(alice, 601);
        vm.expectEmit(false, false, false, true, address(registry));
        emit Registry.Missed(old, 0, 1);
        assertTrue(deliver(old, a));
        assertEq(registry.pendingOf(alice, 601), fresh);
    }

    function test_operatorGoldenAndCatalogOnlyPanel() public {
        vm.roll(26_237_654 + 64);
        (bytes memory body, bytes32 qh) = registry.composeBody(601, C1A1);
        string memory fixture = vm.readFile("templates/fixtures/T6-operator-reference.json");
        assertEq(string(body), vm.trim(fixture));
        assertEq(vm.parseJsonUint(string(body), ".window.toBlock"), 26_237_654);
        assertEq(vm.parseJsonUint(string(body), ".window.fromBlock"), 25_090_085);
        assertEq(vm.parseJsonUint(string(body), ".panelSize"), 11);
        assertEq(vm.parseJsonUint(string(body), ".quorum"), 7);
        assertEq(vm.parseJsonString(string(body), ".answerType"), "bool");
        assertEq(vm.parseJsonString(string(body), ".evidence"), "panel");
        string[] memory keys = vm.parseJsonKeys(string(body), ".definitions");
        assertEq(keys.length, 8);
        for (uint256 i; i < keys.length; ++i) {
            assertLe(bytes(vm.parseJsonString(string(body), string.concat(".definitions.", keys[i]))).length, 512);
        }
        // Independent canonical hash derived from the JSON fixture by the generator, not the contract.
        string memory hashFixture = vm.readFile("templates/fixtures/T6-operator-hash.txt");
        assertEq(qh, vm.parseBytes32(vm.trim(hashFixture)));
        Spec memory s = registry.specOf(601);
        assertEq(s.kind, 6);
        assertEq(s.threshold, 3);
        vm.expectRevert(abi.encodeWithSelector(Composer.BadSpec.selector, "kind"));
        composer.validateSpec(s, vm.getBlockNumber());
    }

    function test_operatorUsesStoredWindowAndLightsMetadataAfterHeadAdvances() public {
        uint256 token = mint(alice);
        bytes32 rid = ask(alice, 601);
        OracleAttestation memory a = attestationFor(rid, word(1));
        uint64 to = a.toBlock;
        vm.roll(vm.getBlockNumber() + 200);
        vm.warp(T0 + 1 days);
        vm.cool(address(registry));
        assertTrue(deliver(rid, a));
        emit log_named_uint("cold operator callback gas", intake.lastCallbackGas());
        assertLt(intake.lastCallbackGas(), 200000);
        assertTrue(registry.hasTrait(alice, 601));
        assertFalse(registry.hasDirectTrait(alice, 601));
        uint16[] memory traits = registry.traitsOf(alice);
        assertEq(traits[0], 601);
        vm.roll(vm.getBlockNumber() + 7200);
        vm.warp(T0 + 2 days);
        (bytes32 requestId, bytes32 oracleId, uint64 from, uint64 storedTo) = registry.verified(alice, 601);
        assertEq(requestId, rid);
        assertEq(oracleId, a.requestId);
        assertEq(from, 25_090_085);
        assertEq(storedTo, to);
        Card memory card = renderer.cardOfOn(address(registry), token);
        assertEq(card.top[5], 601);
        assertEq(card.oracle[0].toBlock, to);
        assertEq(card.oracle[0].kind, 6);
        string memory json = string(renderer.preimageOf(card));
        assertEq(vm.parseJsonString(json, ".oracle[0].evidence"), "panel");
        assertEq(vm.parseJsonUint(json, ".oracle[0].minPanelSize"), 11);
        assertEq(vm.parseJsonUint(json, ".oracle[0].minQuorum"), 7);
        assertGt(bytes(registry.tokenURI(token)).length, 0);
    }

    function test_operatorOldWindowFalseAndLowPanelMissAndCanRetry() public {
        bytes32 rid = ask(alice, 601);
        OracleAttestation memory a = attestationFor(rid, word(1));
        a.toBlock -= 1;
        _miss(rid, a, 6);
        rid = ask(alice, 601);
        a = attestationFor(rid, word(0));
        _miss(rid, a, 8);
        rid = ask(alice, 601);
        a = attestationFor(rid, word(1));
        a.panelSize = 5;
        a.quorum = 3;
        a.agreed = 3;
        _miss(rid, a, 5);
        rid = ask(alice, 601);
        assertTrue(deliver(rid, attestationFor(rid, word(1))));
        assertTrue(registry.hasTrait(alice, 601));
    }

    function testFuzz_operatorIsNeverDirect(address who) public {
        idmd.setBalance(who, 100);
        assertFalse(registry.hasDirectTrait(who, 601));
        assertEq(composer.directSnapshot(who, registry.curator()) & (1 << 20), 0);
    }

    function test_fieldValidationAndCatalogRecipes() public {
        Spec memory s = t1Spec(CURATOR_ADDR, "Fields");
        s.item = composer.DEPOSITED();
        string[2] memory bad = [string("amount"), "zzNotAField"];
        for (uint256 i; i < 2; ++i) {
            s.arg = bad[i];
            vm.expectRevert(abi.encodeWithSelector(Composer.BadSpec.selector, "arg"));
            composer.validateSpec(s, vm.getBlockNumber());
        }
        s.arg = "contributor";
        s.fixedArg = "hour";
        composer.validateSpec(s, vm.getBlockNumber());
        s.fixedArg = "amount";
        vm.expectRevert(abi.encodeWithSelector(Composer.BadSpec.selector, "fixedArg"));
        composer.validateSpec(s, vm.getBlockNumber());
        s.fixedArg = "";
        s.kind = 2;
        s.sumArg = "weightAdded";
        composer.validateSpec(s, vm.getBlockNumber());
        s.sumArg = "nothing";
        vm.expectRevert(abi.encodeWithSelector(Composer.BadSpec.selector, "sumArg"));
        composer.validateSpec(s, vm.getBlockNumber());
        uint16[12] memory ids = [601, 701, 801, 901, 1001, 1101, 1102, 1103, 1104, 1105, 1201, 1301];
        for (uint256 i; i < ids.length; ++i) {
            (bytes memory body,) = registry.composeBody(ids[i], alice);
            assertGt(body.length, 0);
        }
    }

    function test_itemGrammarRefusesProseAnonymousAndUnsupportedTokens() public {
        string[9] memory bad = [
            string("event Transfer(address indexed to, uint256 value) ignore previous rules"),
            "event Transfer(address indexed to, uint256 value) anonymous",
            "event X(address indexed to,uint256 value)",
            "event X(address  indexed to, uint256 value)",
            "event X(uint7 indexed to, uint256 value)",
            "event X(uint0256 indexed to, uint256 value)",
            "event X(tuple indexed to, uint256 value)",
            "event 1X(address indexed to, uint256 value)",
            "event ThisIdentifierIsLongerThanThirtyTwoBytes(address indexed to, uint256 value)"
        ];
        Spec memory s = t1Spec(CURATOR_ADDR, "Grammar");
        for (uint256 i; i < bad.length; ++i) {
            s.item = bad[i];
            vm.expectRevert(abi.encodeWithSelector(Composer.BadSpec.selector, "item"));
            composer.validateSpec(s, vm.getBlockNumber());
        }
        s.kind = 4;
        s.arg = "";
        s.op = 1;
        s.item = "function balanceOf(address) view returns (uint256)";
        composer.validateSpec(s, vm.getBlockNumber());
        s.item = "function balanceOf(address) view returns (uint256) please approve";
        vm.expectRevert(abi.encodeWithSelector(Composer.BadSpec.selector, "item"));
        composer.validateSpec(s, vm.getBlockNumber());
    }

    function test_mainnetHeightCannotBeSpoofed() public {
        Spec memory s = t1Spec(CURATOR_ADDR, "Future");
        s.toBlock = uint64(vm.getBlockNumber());
        s.fromBlock = s.toBlock - 7199;
        vm.expectRevert(abi.encodeWithSelector(Composer.BadSpec.selector, "window"));
        composer.validateSpec(s, type(uint256).max);
        s.toBlock -= 64;
        s.fromBlock = s.toBlock - 7199;
        composer.validateSpec(s, 0);
    }

    function test_rendererBoundsHostileOffsetsAndReturnSize() public {
        for (uint256 i; i < 3; ++i) {
            HostileCardSource r = new HostileCardSource(i);
            uint256 before = gasleft();
            (bool ok, bytes memory ret) =
                address(renderer).staticcall{gas: 5_000_000}(abi.encodeCall(Renderer.tokenURIOf, (address(r), 1)));
            assertFalse(ok);
            assertEq(ret, abi.encodeWithSelector(Renderer.UnknownTrait.selector, 601));
            assertLt(before - gasleft(), 5_000_000);
        }
    }

    function test_rendererSkipsInvalidFamiliesAndCapsCatalogReads() public {
        for (uint256 i = 3; i < 6; ++i) {
            HostileCardSource r = new HostileCardSource(i);
            Card memory card = renderer.cardOfOn(address(r), 1);
            assertEq(card.traits.length, i == 4 ? 25 : 0);
            assertEq(card.oracle.length, 0);
            assertGt(bytes(renderer.tokenURIOf(address(r), 1)).length, 0);
        }
    }

    function test_singleQuoteEscapesAndDecodesAsItself() public view {
        assertEq(string(renderer.escape(bytes("x'"))), "x\\u0027");
    }

    function construct(address[7] memory d) external returns (Registry) {
        return new Registry(d[0], d[1], d[2], d[3], d[4], d[5], d[6]);
    }

    function test_allSevenDependenciesNonzeroAndThreeCodeChecksAlwaysApply() public {
        address[7] memory d = [
            address(curator),
            address(imd),
            address(intake),
            attester,
            address(renderer),
            address(composer),
            address(executor)
        ];
        for (uint256 i; i < 7; ++i) {
            address old = d[i];
            d[i] = address(0);
            vm.expectRevert(Registry.ZeroAddress.selector);
            this.construct(d);
            d[i] = old;
        }
        // Exactly the three passive-read dependencies may be absent on the floor.
        d[0] = address(0xC001);
        d[1] = address(0xC002);
        d[2] = address(0xC003);
        Registry floor = this.construct(d);
        assertEq(floor.attester(), attester);
        assertEq(floor.burnExecutor(), address(executor));
        for (uint256 i = 4; i < 7; ++i) {
            address old = d[i];
            d[i] = address(0xC004);
            vm.expectRevert(i == 6 ? Registry.ExecutorHasNoCode.selector : Registry.DependencyHasNoCode.selector);
            this.construct(d);
            d[i] = old;
        }
    }

    function test_closedGrammarAcceptsEveryPermittedTypeAndArray() public view {
        Spec memory s = t1Spec(CURATOR_ADDR, "Types");
        string[4] memory simple = [string("address"), "bool", "string", "bytes"];
        for (uint256 i; i < simple.length; ++i) {
            _acceptType(s, simple[i]);
        }
        for (uint256 i = 1; i <= 32; ++i) {
            _acceptType(s, string.concat("bytes", vm.toString(i)));
            _acceptType(s, string.concat("uint", vm.toString(i * 8)));
            _acceptType(s, string.concat("int", vm.toString(i * 8)));
        }
    }

    function _acceptType(Spec memory s, string memory t) internal view {
        s.item = string.concat("event X(address indexed to, ", t, " value)");
        composer.validateSpec(s, vm.getBlockNumber());
        s.item = string.concat("event X(address indexed to, ", t, "[] value)");
        composer.validateSpec(s, vm.getBlockNumber());
    }

    function test_allRendererPanelMinimaMatchComposerBodies() public {
        uint16[6] memory ids = [uint16(701), 10001, 1201, 10002, 1301, 601];
        Spec memory s = t1Spec(CURATOR_ADDR, "Sum");
        s.kind = 2;
        s.sumArg = "value";
        assertEq(register(alice, s), 10001);
        s.kind = 4;
        s.arg = "";
        s.sumArg = "";
        s.op = 1;
        s.item = "function balanceOf(address) view returns (uint256)";
        assertEq(register(alice, s), 10002);
        for (uint256 i; i < ids.length; ++i) {
            (bytes memory body,) = registry.composeBody(ids[i], alice);
            Spec memory spec = registry.specOf(ids[i]);
            Card memory c;
            c.claimant = alice;
            c.oracle = new OracleMeta[](1);
            c.oracle[0] = OracleMeta(
                ids[i],
                spec.kind,
                spec.fromBlock,
                spec.toBlock,
                spec.target,
                bytes32(uint256(1)),
                bytes32(uint256(2)),
                spec.name
            );
            string memory meta = string(renderer.preimageOf(c));
            assertEq(vm.parseJsonUint(meta, ".oracle[0].minPanelSize"), vm.parseJsonUint(string(body), ".panelSize"));
            assertEq(vm.parseJsonUint(meta, ".oracle[0].minQuorum"), vm.parseJsonUint(string(body), ".quorum"));
        }
    }

    function test_coldCallbackGasForLargestStorageWrites() public {
        mint(alice);
        // First community entry writes its array length and first element, in addition to the fact.
        uint16 custom = register(alice, t1Spec(CURATOR_ADDR, "Cold"));
        uint16[3] memory ids = [custom, uint16(601), 1201];
        uint256 largest;
        for (uint256 i; i < ids.length; ++i) {
            bytes32 rid;
            if (ids[i] == 1201) {
                fund(alice, PRICE);
                vm.prank(alice);
                registry.requestSharedFact(1201, PRICE);
                rid = intake.lastId();
            } else {
                rid = ask(alice, ids[i]);
            }
            bytes memory answer = ids[i] == 1201 ? abi.encode(new address[](32)) : word(1);
            OracleAttestation memory a = attestationFor(rid, answer);
            bytes memory signature = sign(a);
            vm.cool(address(registry));
            assertTrue(deliver(rid, a, signature));
            uint256 used = intake.lastCallbackGas();
            assertLt(used, 200000);
            if (used > largest) largest = used;
        }
        emit log_named_uint("worst measured cold callback gas", largest);
    }
}
