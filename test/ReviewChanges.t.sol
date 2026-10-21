// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Base} from "./Base.t.sol";
import {Registry} from "../src/Registry.sol";
import {Composer} from "../src/Composer.sol";
import {OracleAttestation} from "../src/interfaces/IOracleConsumer.sol";
import {Card, Spec} from "../src/Types.sol";

/// @notice Regression tests for the bounded review follow-up, including Intake's actual stipend.
contract ReviewChangesTest is Base {
    function _askShared() internal returns (bytes32 rid) {
        fund(C1A1, PRICE);
        vm.prank(C1A1);
        registry.requestSharedFact(1201, PRICE);
        return intake.lastId();
    }

    function _miss(bytes32 rid, uint16 id, uint8 reason, OracleAttestation memory a, bytes memory sig) internal {
        // Build the large wire envelope outside the callback budget, just as Intake.complete does.
        bytes memory args = abi.encode(rid, a, sig);
        vm.cool(address(registry));
        vm.expectEmit(false, false, false, true, address(registry));
        emit Registry.Missed(rid, id, reason);
        assertTrue(intake.complete(rid, 0, args), "ABI-valid miss must finish under 200,000 gas");
        (,,, uint64 toBlock) = registry.verified(C1A1, id);
        assertEq(toBlock, 0, "miss stored no verification");
        (,, uint64 requestedAt,) = registry.pendingRequest(rid);
        assertEq(requestedAt, 0, "pending record cleared");
        assertEq(registry.pendingOf(C1A1, id), bytes32(0), "personal reverse index cleared");
        assertEq(registry.sharedPending(id), bytes32(0), "shared reverse index cleared");
        if (id == 1201) {
            (bytes32 stored,,) = registry.sharedFact(id);
            assertEq(stored, bytes32(0), "miss did not poison shared fact");
        }
    }

    function test_hugeSignatureClearsPendingAndAllowsImmediateRetry() public {
        bytes32 rid = ask(C1A1, 701);
        OracleAttestation memory a = attestationFor(rid, word(1));
        _miss(rid, 701, 2, a, new bytes(262_144));
        rid = ask(C1A1, 701);
        assertTrue(deliver(rid, attestationFor(rid, word(1))));
        assertTrue(registry.hasTrait(C1A1, 701));
    }

    function test_hugeAnswerClearsUintBoolAndSharedRequestsUnderStipend() public {
        uint16[3] memory ids = [701, 1301, 1201];
        for (uint256 i; i < ids.length; ++i) {
            bytes32 rid = ids[i] == 1201 ? _askShared() : ask(C1A1, ids[i]);
            OracleAttestation memory a = attestationFor(rid, new bytes(262_144));
            _miss(rid, ids[i], 9, a, sign(a));
            // A paid retry can pass immediately, including a shared fact at its head of 32 addresses.
            rid = ids[i] == 1201 ? _askShared() : ask(C1A1, ids[i]);
            bytes memory answer = ids[i] == 1201 ? abi.encode(new address[](32)) : word(1);
            a = attestationFor(rid, answer);
            bytes memory sig = sign(a);
            vm.cool(address(registry));
            assertTrue(deliver(rid, a, sig));
            if (ids[i] == 1201) {
                (bytes32 stored,, uint16 count) = registry.sharedFact(1201);
                assertEq(stored, rid);
                assertEq(count, 32);
            } else {
                assertTrue(registry.hasTrait(C1A1, ids[i]));
            }
        }
    }

    function test_signatureLengthPrecedesAnswerLengthAndChain() public {
        uint256[4] memory lengths = [uint256(0), 64, 66, 262_144];
        for (uint256 i; i < lengths.length; ++i) {
            bytes32 rid = ask(C1A1, 701);
            OracleAttestation memory a = attestationFor(rid, new bytes(262_144));
            a.chainId = 4663;
            _miss(rid, 701, 2, a, new bytes(lengths[i]));
        }
    }

    function test_scalarAnswerLengthPrecedesChainSignerAndClaimedType() public {
        uint256[5] memory lengths = [uint256(0), 31, 33, 2112, 2113];
        for (uint256 i; i < lengths.length; ++i) {
            for (uint256 j; j < 2; ++j) {
                uint16 id = j == 0 ? 701 : 1301;
                bytes32 rid = ask(C1A1, id);
                OracleAttestation memory a = attestationFor(rid, new bytes(lengths[i]));
                a.chainId = 4663;
                a.answerType = 4; // Length follows the pending kind, not this untrusted field.
                _miss(rid, id, 9, a, new bytes(65));
            }
        }
    }

    function test_sharedAnswerUpperBoundPrecedesChainAndSigner() public {
        bytes32 rid = _askShared();
        OracleAttestation memory a = attestationFor(rid, new bytes(2113));
        a.chainId = 4663;
        _miss(rid, 1201, 9, a, new bytes(65));

        rid = _askShared();
        a = attestationFor(rid, new bytes(2112));
        a.chainId = 4663;
        _miss(rid, 1201, 3, a, new bytes(65)); // At the cap, chain validation is reached.

        rid = _askShared();
        a = attestationFor(rid, abi.encode(new address[](65)));
        _miss(rid, 1201, 9, a, sign(a));
    }

    function test_validationPrecedenceAfterSizes() public {
        uint8[9] memory reasons = [3, 2, 4, 5, 6, 7, 10, 9, 8];
        for (uint256 first; first < reasons.length; ++first) {
            bytes32 rid = ask(C1A1, 1301);
            OracleAttestation memory a = attestationFor(rid, word(first <= 7 ? 2 : 0));
            if (first <= 6) a.questionHash ^= bytes32(uint256(1));
            if (first <= 5) a.expiresAt = uint64(block.timestamp - 1);
            if (first <= 4) a.toBlock++;
            if (first <= 3) a.agreed = 0;
            if (first <= 2) a.answerType = 3;
            if (first == 0) a.chainId = 4663;
            bytes memory sig = first <= 1 ? signWith(0xBAD, a) : sign(a);
            _miss(rid, 1301, reasons[first], a, sig);
        }
    }

    function test_unknownRequestStillPrecedesDynamicSizeChecks() public {
        bytes32 rid = ask(C1A1, 701);
        OracleAttestation memory a = attestationFor(rid, new bytes(262_144));
        vm.warp(T0 + 31 days + 1);
        vm.prank(C1A1);
        registry.abandon(rid);
        bytes32 successor = ask(C1A1, 701);
        vm.expectEmit(false, false, false, true, address(registry));
        emit Registry.Missed(rid, 0, 1);
        assertTrue(deliver(rid, a, new bytes(262_144)));
        assertEq(registry.pendingOf(C1A1, 701), successor);
    }

    function test_fuzz_ordinalShowsLowestVerifiedId(uint8 mask) public {
        mask = uint8(bound(mask, 0, 31));
        curator.set(C1A1, 0, true, 10, 800 ether, 10000); // direct traits are frozen at mint
        uint256 tokenId = mint(C1A1);
        uint16 expected;
        // Acquire descending, so rendering cannot accidentally rely on verification order.
        for (uint16 i = 5; i > 0; --i) {
            if ((mask & (1 << (i - 1))) == 0) continue;
            uint16 id = 1100 + i;
            bytes32 rid = ask(C1A1, id);
            assertTrue(deliver(rid, attestationFor(rid, word(1))));
            expected = id;
        }
        Card memory c = renderer.cardOfOn(address(registry), tokenId);
        assertEq(c.top[10], expected);
        assertEq(c.top[1], 202, "true tier families still show their highest tier");
        assertEq(c.top[2], 303);
        assertEq(c.top[3], 404);
        assertEq(c.top[4], 503);
        string memory value = expected == 0 ? "none" : vm.toString(expected);
        string memory metadata = string(renderer.preimageOf(c));
        assertEq(vm.parseJsonString(metadata, ".attributes[11].trait_type"), "PID");
        assertEq(vm.parseJsonString(metadata, ".attributes[11].value"), value);
        // the hive shows the Ordinal cell lit for any ordinal, with the rare dot for 1101 to 1104 only;
        // 202 (Zero-Shot's top tier) is the other rare dot on this card
        string memory image = vm.parseJsonString(metadata, ".image");
        uint256 dots = vm.split(image, "%3Ccircle%20").length - 1;
        assertEq(dots, (expected != 0 && expected != 1105) ? 2 : 1, "rare dots");
    }

    function test_metadataReportsMinimaEvenWhenSignedPanelIsLarger() public {
        uint256 tokenId = mint(C1A1);
        uint16[2] memory ids = [701, 1301];
        for (uint256 i; i < ids.length; ++i) {
            bytes32 rid = ask(C1A1, ids[i]);
            OracleAttestation memory a = attestationFor(rid, word(1));
            a.panelSize = 30;
            a.quorum = 20;
            a.agreed = 22;
            assertTrue(deliver(rid, a));
            string memory prefix = string.concat(".oracle[", vm.toString(i), "]");
            string memory metadata = string(renderer.preimageOf(renderer.cardOfOn(address(registry), tokenId)));
            assertEq(vm.parseJsonUint(metadata, string.concat(prefix, ".minPanelSize")), i == 0 ? 5 : 11);
            assertEq(vm.parseJsonUint(metadata, string.concat(prefix, ".minQuorum")), i == 0 ? 3 : 7);
            assertFalse(vm.keyExistsJson(metadata, string.concat(prefix, ".panelSize")));
            assertFalse(vm.keyExistsJson(metadata, string.concat(prefix, ".quorum")));
            assertEq(vm.parseJsonBytes32(metadata, string.concat(prefix, ".oracleRequestId")), a.requestId);
        }
    }

    function test_fuzz_emptyFixedArgRequiresZeroValueForT1AndT2(uint256 value) public {
        value = bound(value, 1, type(uint256).max);
        for (uint8 kind = 1; kind <= 2; ++kind) {
            Spec memory s = t1Spec(REGISTRY_ADDR, "Filter");
            s.kind = kind;
            if (kind == 2) s.sumArg = "value";
            s.fixedVal = value;
            fund(C1A1, registry.SPEC_FEE());
            uint256 registryBalanceBefore = imd.balanceOf(address(registry));
            uint256 balanceBefore = imd.balanceOf(C1A1);
            uint16 nextId = registry.nextSpecId();
            vm.prank(C1A1);
            vm.expectRevert(abi.encodeWithSelector(Composer.BadSpec.selector, "fixedVal"));
            registry.registerSpec(s, 0);
            assertEq(imd.balanceOf(address(registry)), registryBalanceBefore);
            assertEq(imd.balanceOf(C1A1), balanceBefore);
            assertEq(registry.nextSpecId(), nextId);

            s.fixedVal = 0;
            assertEq(register(C1A1, s), nextId, "empty filter with zero accepted");
            s.fixedArg = "from";
            assertEq(register(C1A1, s), nextId + 1, "named filter may match zero");
            s.fixedVal = value;
            assertEq(register(C1A1, s), nextId + 2, "named filter may match nonzero");
        }
    }
}
