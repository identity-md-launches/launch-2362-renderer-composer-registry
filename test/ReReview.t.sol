// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {MockBurnExecutor} from "./mocks/MockBurnExecutor.sol";

import {Base} from "./Base.t.sol";
import {stdStorage, StdStorage, stdError} from "forge-std/Test.sol";
import {Registry} from "../src/Registry.sol";
import {Composer} from "../src/Composer.sol";
import {OracleAttestation} from "../src/interfaces/IOracleConsumer.sol";
import {Spec} from "../src/Types.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";

/// @notice A Curator whose `isSettled` writes storage: under the constructor's STATICCALL it must fail.
contract WritingCurator {
    uint256 public reads;

    function isSettled() external returns (bool) {
        reads++;
        return true;
    }
}

/// @notice Re-review of the review follow-up (test/NOTES.md, changes (j) and (k)): cold onResult gas
///         through the mock Intake's real `call(200,000)`, and further regressions for (a), (b), (c),
///         (e) and (f).
contract ReReviewTest is Base {
    using stdStorage for StdStorage;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    // ------------------------------------------------------------------ (j) cold gas

    /// @dev Delivers a prepared envelope with the registry's account and storage cold, as in a fresh
    ///      transaction from the writer: the request and the signature are built first, then
    ///      `vm.cool`, then the Intake's own `call(stipend)`. Returns the gas the callback used.
    function _coldDeliver(bytes32 rid, OracleAttestation memory a) internal returns (uint256 used) {
        bytes memory args = abi.encode(rid, a, sign(a));
        assertEq(intake.callbackGas(), 200_000, "the real stipend");
        vm.cool(address(registry));
        assertTrue(intake.complete(rid, 0, args), "delivered under the Intake's 200,000 stipend");
        used = intake.lastCallbackGas();
        assertLt(used, 200_000);
    }

    function _list64() internal pure returns (address[] memory list) {
        list = new address[](32);
        for (uint256 i; i < 32; ++i) {
            list[i] = address(uint160(0x5000 + i));
        }
    }

    function test_coldGas_firstCommunityVerificationWithACard() public {
        uint256 tokenId = mint(alice);
        uint16 specId = register(bob, t1Spec(address(0xCAFE), "Received a token"));
        bytes32 rid = ask(alice, specId);
        assertEq(registry.verifiedSpecsOf(alice).length, 0, "first community verification");
        vm.expectEmit(true, true, true, true, address(registry));
        emit IERC4906.MetadataUpdate(tokenId);
        uint256 used = _coldDeliver(rid, attestationFor(rid, word(7)));
        assertTrue(registry.hasTrait(alice, specId));
        assertEq(registry.verifiedSpecsOf(alice)[0], specId);
        emit log_named_uint("cold onResult gas, first community verification with a card", used);
    }

    function test_coldGas_sharedFact64Catalog() public {
        fund(bob, PRICE);
        vm.prank(bob);
        registry.requestSharedFact(1201, PRICE);
        bytes32 rid = intake.lastId();
        uint256 used = _coldDeliver(rid, attestationFor(rid, abi.encode(_list64())));
        (bytes32 stored, bytes32 hash, uint16 n) = registry.sharedFact(1201);
        assertEq(stored, rid);
        assertEq(hash, keccak256(abi.encode(_list64())));
        assertEq(n, 32);
        emit log_named_uint("cold onResult gas, 64-address shared fact (catalog 1201)", used);
    }

    function test_coldGas_sharedFact64Community() public {
        Spec memory s = t1Spec(address(0xCAFE), "Top sixty four");
        s.kind = 3;
        s.sumArg = "value";
        s.threshold = 32; // the head is at most 32; the list carries exactly 32 addresses
        uint16 id = register(bob, s);
        fund(bob, PRICE);
        vm.prank(bob);
        registry.requestSharedFact(id, PRICE);
        bytes32 rid = intake.lastId();
        uint256 used = _coldDeliver(rid, attestationFor(rid, abi.encode(_list64())));
        (bytes32 stored,, uint16 n) = registry.sharedFact(id);
        assertEq(stored, rid);
        assertEq(n, 32);
        emit log_named_uint("cold onResult gas, 64-address shared fact (community T3)", used);
    }

    // ------------------------------------------------------------------ (a) bounds before copying

    function test_hugeSignatureOnCommunitySharedFactAndCardRequestClearsUnderStipend() public {
        mint(alice);
        Spec memory t3 = t1Spec(address(0xCAFE), "Shared");
        t3.kind = 3;
        t3.sumArg = "value";
        t3.threshold = 3;
        uint16 shared = register(bob, t3);
        uint16 personal = register(bob, t1Spec(address(0xBEEF), "Personal"));

        fund(bob, PRICE);
        vm.prank(bob);
        registry.requestSharedFact(shared, PRICE);
        bytes32 rid = intake.lastId();
        OracleAttestation memory a = attestationFor(rid, abi.encode(_list64()));
        bytes memory args = abi.encode(rid, a, new bytes(262_144));
        vm.cool(address(registry));
        vm.expectEmit(false, false, false, true, address(registry));
        emit Registry.Missed(rid, shared, 2);
        assertTrue(intake.complete(rid, 0, args));
        assertEq(registry.sharedPending(shared), bytes32(0));

        rid = ask(alice, personal);
        a = attestationFor(rid, word(1));
        args = abi.encode(rid, a, new bytes(262_144));
        vm.cool(address(registry));
        vm.expectEmit(false, false, false, true, address(registry));
        emit Registry.Missed(rid, personal, 2);
        assertTrue(intake.complete(rid, 0, args));
        assertEq(registry.pendingOf(alice, personal), bytes32(0));
        assertFalse(registry.hasTrait(alice, personal));
    }

    // ------------------------------------------------------------------ (b) ordinal is the lowest id

    function test_lowerOrdinalAcquiredLaterReplacesTheHigherOne() public {
        uint256 tokenId = mint(alice);
        bytes32 rid = ask(alice, 1104);
        assertTrue(deliver(rid, attestationFor(rid, word(1))));
        assertEq(renderer.cardOfOn(address(registry), tokenId).top[10], 1104);
        string memory before = registry.tokenURI(tokenId);
        rid = ask(alice, 1102);
        assertTrue(deliver(rid, attestationFor(rid, word(1))));
        assertEq(renderer.cardOfOn(address(registry), tokenId).top[10], 1102, "the lowest verified ordinal is shown");
        assertTrue(keccak256(bytes(registry.tokenURI(tokenId))) != keccak256(bytes(before)));
        rid = ask(alice, 1105);
        assertTrue(deliver(rid, attestationFor(rid, word(1))));
        assertEq(
            renderer.cardOfOn(address(registry), tokenId).top[10], 1102, "a higher ordinal never replaces a lower one"
        );
    }

    // ------------------------------------------------------------------ (c) community attributes

    function test_communityAttributesAppearOnlyForVerifiedSpecs() public {
        uint256 tokenId = mint(alice);
        uint16 first = register(bob, t1Spec(address(0xCAFE), "First spec"));
        uint16 second = register(bob, t1Spec(address(0xBEEF), "Second-spec.v2"));
        string memory metadata = string(renderer.preimageOf(renderer.cardOfOn(address(registry), tokenId)));
        assertFalse(vm.contains(metadata, '"trait_type":"Community 1'), "no community attribute without one");
        assertEq(vm.parseJsonUint(metadata, ".attributes[14].value"), 0);
        assertFalse(vm.keyExistsJson(metadata, ".attributes[15]"));

        bytes32 rid = ask(alice, second);
        assertTrue(deliver(rid, attestationFor(rid, word(1))));
        metadata = string(renderer.preimageOf(renderer.cardOfOn(address(registry), tokenId)));
        assertEq(vm.parseJsonUint(metadata, ".attributes[14].value"), 1);
        assertEq(
            vm.parseJsonString(metadata, ".attributes[15].trait_type"), string.concat("Community ", vm.toString(second))
        );
        assertEq(vm.parseJsonString(metadata, ".attributes[15].value"), "Second-spec.v2");
        assertFalse(vm.keyExistsJson(metadata, ".attributes[16]"), "an unverified spec is not listed");
        assertFalse(vm.contains(metadata, string.concat('"Community ', vm.toString(first), '"')));
    }

    // ------------------------------------------------------------------ (e) unused fixedVal

    function test_unusedFixedValIsRefusedAndAnEmptyFilterIsNotSerialised() public {
        Spec memory s = t1Spec(address(0xCAFE), "Filterless");
        s.fixedVal = 1;
        fund(alice, registry.SPEC_FEE());
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Composer.BadSpec.selector, "fixedVal"));
        registry.registerSpec(s, 0);
        s.fixedVal = 0;
        uint16 id = register(alice, s);
        (bytes memory raw,) = registry.composeBody(id, alice);
        string memory body = string(raw);
        assertFalse(vm.contains(body, " and whose indexed "), "an empty filter is omitted from the question");
        s.fixedArg = "from";
        s.fixedVal = 1;
        uint16 filtered = register(alice, s);
        (raw,) = registry.composeBody(filtered, alice);
        body = string(raw);
        assertTrue(vm.contains(body, " and whose indexed from argument equals 1"));
    }

    // ------------------------------------------------------------------ (f) settled Curator

    function test_constructorReadsIsSettledWithoutWriting() public {
        WritingCurator w = new WritingCurator();
        vm.expectRevert();
        new Registry(
            address(w), address(imd), address(intake), attester, address(renderer), address(composer), address(executor)
        );
        assertEq(w.reads(), 0, "a static call cannot change the Curator");
        // The settled mock at the real address deploys, and the registry is fully usable.
        Registry r = new Registry(
            CURATOR_ADDR,
            address(imd),
            address(intake),
            attester,
            address(renderer),
            address(composer),
            address(executor)
        );
        assertEq(address(r.curator()), CURATOR_ADDR);
    }

    // ------------------------------------------------------------------ (p) the spec id bound

    function test_specIdsEndAt65534() public {
        stdstore.target(address(registry)).sig("nextSpecId()").checked_write(uint256(65534));
        assertEq(register(alice, t1Spec(address(0xCAFE), "Last")), 65534, "the last community id");
        assertEq(registry.nextSpecId(), 65535);
        Spec memory s = t1Spec(address(0xCAFE), "One too many");
        fund(alice, registry.SPEC_FEE());
        vm.prank(alice);
        vm.expectRevert(stdError.arithmeticError);
        registry.registerSpec(s, 0);
        assertEq(registry.specOf(65534).name, "Last");
    }

    // ------------------------------------------------------------------ (n) consumed once, per request

    function test_oldSignedEvidenceCannotSatisfyASuccessorAfterAbandon() public {
        bytes32 r1 = ask(alice, 701);
        OracleAttestation memory a = attestationFor(r1, word(1));
        a.expiresAt += 2 days; // outlives the 31-day abandon window
        bytes memory sig = sign(a);
        vm.warp(block.timestamp + 31 days + 1);
        vm.prank(alice);
        registry.abandon(r1);
        bytes32 r2 = ask(alice, 701);
        (,,, bytes32 q2) = registry.pendingRequest(r2);
        assertEq(q2, a.questionHash, "identical canonical question");
        // The request that was abandoned is consumed: its id is reason 1 and touches nothing.
        vm.expectEmit(false, false, false, true, address(registry));
        emit Registry.Missed(r1, 0, 1);
        assertTrue(deliver(r1, a, sig));
        assertEq(registry.pendingOf(alice, 701), r2);
        // Issuance bounds reject stale evidence even for an identical canonical question.
        assertTrue(deliver(r2, a, sig));
        assertFalse(registry.hasTrait(alice, 701));
        (bytes32 vr,,,) = registry.verified(alice, 701);
        assertEq(vr, bytes32(0));
        // And the successor, once consumed, is consumed for good.
        vm.expectEmit(false, false, false, true, address(registry));
        emit Registry.Missed(r2, 0, 1);
        vm.prank(address(intake));
        registry.onResult(r2, a, sig);
    }
}
