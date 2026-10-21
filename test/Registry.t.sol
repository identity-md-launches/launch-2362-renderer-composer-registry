// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {MockBurnExecutor} from "./mocks/MockBurnExecutor.sol";

import {Base} from "./Base.t.sol";
import {Registry} from "../src/Registry.sol";
import {OracleAttestation} from "../src/interfaces/IOracleConsumer.sol";
import {Spec} from "../src/Types.sol";
import {ReentrantIMD, MockIntake} from "./mocks/Mocks.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";

/// @notice CONCEPT.md section 6: cards (1, 2), credentials (3), the callback checks (4, 5), tiers (6),
contract RegistryTest is Base {
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    // ------------------------------------------------------------------ 1, 2: cards

    function test_mintOncePerWalletAndTransfersKeepClaimant() public {
        uint256 id = mint(alice);
        assertEq(id, 1);
        assertEq(registry.tokenOf(alice), 1);
        assertEq(registry.claimantOf(1), alice);
        assertEq(registry.mintedAtBlock(1), uint64(block.number));
        assertEq(imd.balanceOf(address(registry)), 0);
        fund(alice, 0.1 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Registry.AlreadyMinted.selector, alice));
        registry.mintCard();

        vm.roll(block.number + 10);
        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit IERC4906.MetadataUpdate(1);
        registry.transferFrom(alice, bob, 1);
        assertEq(registry.ownerOf(1), bob);
        assertEq(registry.tokenOf(alice), 1);
        assertEq(registry.tokenOf(bob), 0);
        assertEq(registry.claimantOf(1), alice);
        assertEq(registry.mintedAtBlock(1), uint64(block.number - 10));
        // the seller cannot re-mint, the buyer can mint their own
        fund(alice, 0.1 ether);
        vm.prank(alice);
        vm.expectRevert();
        registry.mintCard();
        assertEq(mint(bob), 2);
    }

    function test_mintWithoutFeeReverts() public {
        vm.prank(alice);
        vm.expectRevert();
        registry.mintCard();
    }

    function test_supportsERC4906AndERC721() public view {
        assertTrue(registry.supportsInterface(0x49064906));
        assertTrue(registry.supportsInterface(0x80ac58cd));
        assertFalse(registry.supportsInterface(0xffffffff));
    }

    function test_noReceiveOrFallback() public {
        (bool ok,) = address(registry).call{value: 1 ether}("");
        assertFalse(ok);
        (ok,) = address(registry).call(hex"deadbeef");
        assertFalse(ok);
    }

    // ------------------------------------------------------------------ 3, 6, 10: direct reads

    function test_directTraitsAreLiveAndNeedNoCard() public {
        curator.set(alice, 0, true, 10, 800 ether, 10_000);
        idmd.setBalance(alice, 1);
        uint16[] memory t = registry.traitsOf(alice);
        assertEq(t.length, 13, "601 needs a card");
        assertTrue(registry.hasTrait(alice, 101) && registry.hasTrait(alice, 201) && registry.hasTrait(alice, 202));
        assertTrue(registry.hasTrait(alice, 303) && registry.hasTrait(alice, 404) && registry.hasTrait(alice, 503));
        assertFalse(registry.hasTrait(alice, 601), "601 is a snapshot at mint: false without a card");
        assertFalse(registry.hasTrait(alice, 701));
        mint(alice);
        assertFalse(registry.hasTrait(alice, 601), "an operator fact needs an attestation");
        idmd.setBalance(alice, 0);
        assertFalse(registry.hasTrait(alice, 601), "seat balance is not a credential");
        assertFalse(registry.hasTrait(alice, 9999), "unknown id");
        assertFalse(registry.hasTrait(address(0), 101), "zero address");
        assertFalse(registry.hasTrait(address(0), 601), "zero address, 601");
    }

    function test_nonMemberIsNeverAnEarlyBird() public view {
        // the mock returns (0, false): a naive hour read would say hour 0
        assertFalse(registry.hasTrait(bob, 101));
        assertFalse(registry.hasTrait(bob, 201));
        assertFalse(registry.hasTrait(bob, 202));
        assertEq(registry.traitsOf(bob).length, 0);
    }

    function test_fuzz_tiersAreMonotone(uint8 hour, bool joined, uint32 txs, uint128 wei_, uint32 points, uint8 bal)
        public
    {
        curator.set(alice, hour, joined, txs, wei_, points);
        idmd.setBalance(alice, bal);
        if (registry.hasTrait(alice, 202)) assertTrue(registry.hasTrait(alice, 201));
        if (registry.hasTrait(alice, 201)) assertTrue(registry.hasTrait(alice, 101));
        if (registry.hasTrait(alice, 303)) assertTrue(registry.hasTrait(alice, 302));
        if (registry.hasTrait(alice, 302)) assertTrue(registry.hasTrait(alice, 301));
        if (registry.hasTrait(alice, 404)) assertTrue(registry.hasTrait(alice, 403));
        if (registry.hasTrait(alice, 403)) assertTrue(registry.hasTrait(alice, 402));
        if (registry.hasTrait(alice, 402)) assertTrue(registry.hasTrait(alice, 401));
        if (registry.hasTrait(alice, 503)) assertTrue(registry.hasTrait(alice, 502));
        if (registry.hasTrait(alice, 502)) assertTrue(registry.hasTrait(alice, 501));
        if (!joined) {
            for (uint16 id = 101; id <= 202; id += 100) {
                assertFalse(registry.hasTrait(alice, id));
            }
            assertFalse(registry.hasTrait(alice, 202));
        }
        assertFalse(registry.hasTrait(alice, 601), "no card, no Swarmed");
        assertEq(registry.hasTrait(alice, 202), joined && hour == 0);
        assertEq(registry.hasTrait(alice, 201), joined && hour <= 1);
        assertEq(registry.hasTrait(alice, 302), txs >= 5);
        assertEq(registry.hasTrait(alice, 403), wei_ >= 1e20);
        assertEq(registry.hasTrait(alice, 502), points >= 3162);
    }

    // ------------------------------------------------------------------ 3, 4, 5: upgrade and callback

    function test_upgradeHappyPathMarksTraitAndRefreshesCard() public {
        uint256 tokenId = mint(alice);
        uint256 before = imd.balanceOf(address(registry));
        bytes32 rid = ask(alice, 801);
        assertEq(imd.balanceOf(address(registry)), before, "prices leave no balance");
        assertEq(imd.balanceOf(address(intake)), PRICE);
        assertEq(registry.pendingOf(alice, 801), rid);
        (bytes memory body, bytes32 qh) = registry.composeBody(801, alice);
        assertEq(intake.bodyOf(rid), body, "the body sent is the composed body");
        (address c, uint16 t, uint64 at, bytes32 pqh) = registry.pendingRequest(rid);
        assertEq(c, alice);
        assertEq(t, 801);
        assertEq(at, uint64(block.timestamp));
        assertEq(pqh, qh);

        OracleAttestation memory a = attestationFor(rid, word(1));
        vm.expectEmit(true, true, false, true);
        emit Registry.Verified(alice, 801, rid, a.requestId);
        vm.expectEmit(true, false, false, true);
        emit IERC4906.MetadataUpdate(tokenId);
        assertTrue(deliver(rid, a), "delivered under 200,000 gas");
        (bytes32 vr, bytes32 vo, uint64 f, uint64 to) = registry.verified(alice, 801);
        assertEq(vr, rid);
        assertEq(vo, a.requestId);
        assertEq(f, B_DEPLOY);
        assertEq(to, B_END);
        assertTrue(registry.hasTrait(alice, 801));
        assertEq(registry.pendingOf(alice, 801), bytes32(0));
        // consumed once: a second delivery of the same attestation is reason 1
        bytes memory again = sign(a);
        vm.prank(address(intake));
        vm.expectEmit(false, false, false, true);
        emit Registry.Missed(rid, 0, 1);
        registry.onResult(rid, a, again);
        // an already verified trait cannot be requested again
        fund(alice, PRICE);
        uint16[] memory ids = new uint16[](1);
        ids[0] = 801;
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Registry.AlreadyVerified.selector, alice, 801));
        registry.upgrade(ids, PRICE);
    }

    function test_upgradeWithoutCardAttachesToClaimant() public {
        bytes32 rid = ask(alice, 1001);
        assertTrue(deliver(rid, attestationFor(rid, word(3))));
        assertTrue(registry.hasTrait(alice, 1001));
        assertEq(registry.tokenOf(alice), 0);
        mint(alice);
        assertTrue(registry.hasTrait(alice, 1001));
    }

    function test_upgradeGuards() public {
        fund(alice, 10 ether);
        uint16[] memory ids = new uint16[](2);
        ids[0] = 701;
        ids[1] = 701;
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Registry.AlreadyPending.selector, alice, 701));
        registry.upgrade(ids, PRICE);
        ids = new uint16[](1);
        ids[0] = 101;
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Registry.NotAnOracleTrait.selector, 101));
        registry.upgrade(ids, PRICE);
        ids[0] = 1201;
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Registry.NotASharedFact.selector, 1201));
        registry.upgrade(ids, PRICE);
        ids[0] = 10001;
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Registry.NotAnOracleTrait.selector, 10001));
        registry.upgrade(ids, PRICE);
        ids[0] = 701;
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Registry.PriceAboveMax.selector, PRICE, PRICE - 1));
        registry.upgrade(ids, PRICE - 1);
        vm.prank(alice);
        vm.expectRevert(Registry.NoTraits.selector);
        registry.upgrade(new uint16[](0), PRICE);
        // k requests cost k x priceOf, read at call time
        intake.setPrice(0.7 ether);
        ids = new uint16[](3);
        ids[0] = 701;
        ids[1] = 801;
        ids[2] = 1301;
        vm.prank(alice);
        registry.upgrade(ids, 0.7 ether);
        assertEq(imd.balanceOf(address(intake)), 2.1 ether);
        assertEq(imd.balanceOf(alice), 10 ether - 2.1 ether);
    }

    function test_callbacksRejectEveryoneButTheIntake() public {
        bytes32 rid = ask(alice, 701);
        OracleAttestation memory a = attestationFor(rid, word(1));
        bytes memory sig = sign(a);
        vm.expectRevert(Registry.NotIntake.selector);
        registry.onResult(rid, a, sig);
        vm.prank(attester);
        vm.expectRevert(Registry.NotIntake.selector);
        registry.onResult(rid, a, sig);
        vm.expectRevert(Registry.NotIntake.selector);
        registry.onFailure(rid, 1, "body_refused", 0, 0, "");
        assertFalse(isVerified(alice, 701));
        assertEq(registry.pendingOf(alice, 701), rid, "still pending");
    }

    function _expectMiss(bytes32 rid, uint16 traitId, uint8 reason, OracleAttestation memory a, bytes memory sig)
        internal
    {
        vm.expectEmit(false, false, false, true);
        emit Registry.Missed(rid, traitId, reason);
        assertTrue(deliver(rid, a, sig), "a miss never reverts");
        (address c,,,) = registry.pendingRequest(rid);
        assertEq(c, address(0), "cleared");
        assertEq(registry.pendingOf(alice, traitId), bytes32(0), "index cleared");
        assertFalse(isVerified(alice, traitId));
    }

    function test_missReasons() public {
        OracleAttestation memory a;
        bytes32 rid;

        rid = ask(alice, 701);
        a = attestationFor(rid, word(1));
        _expectMiss(rid, 701, 2, a, signWith(0xBAD, a));

        rid = ask(alice, 701);
        a = attestationFor(rid, word(1));
        _expectMiss(rid, 701, 2, a, hex"00");

        rid = ask(alice, 701);
        a = attestationFor(rid, word(1));
        bytes memory sig = sign(a);
        a.figure = 99; // tampered after signing
        _expectMiss(rid, 701, 2, a, sig);

        rid = ask(alice, 701);
        a = attestationFor(rid, word(1));
        a.chainId = 4663;
        _expectMiss(rid, 701, 3, a, sign(a));

        rid = ask(alice, 701);
        a = attestationFor(rid, word(1));
        a.answerType = 0;
        _expectMiss(rid, 701, 4, a, sign(a));

        rid = ask(alice, 701);
        a = attestationFor(rid, word(1));
        a.agreed = 2;
        _expectMiss(rid, 701, 5, a, sign(a));

        rid = ask(alice, 701);
        a = attestationFor(rid, word(1));
        a.quorum = 2;
        a.agreed = 2;
        _expectMiss(rid, 701, 5, a, sign(a));

        rid = ask(alice, 701);
        a = attestationFor(rid, word(1));
        a.panelSize = 4;
        _expectMiss(rid, 701, 5, a, sign(a));

        rid = ask(alice, 701);
        a = attestationFor(rid, word(1));
        a.fromBlock = B_DEPLOY;
        _expectMiss(rid, 701, 6, a, sign(a));

        rid = ask(alice, 701);
        a = attestationFor(rid, word(1));
        a.expiresAt = uint64(block.timestamp - 1);
        _expectMiss(rid, 701, 7, a, sign(a));

        rid = ask(alice, 701);
        a = attestationFor(rid, word(1));
        a.issuedAt = uint64(block.timestamp + 2 hours);
        _expectMiss(rid, 701, 7, a, sign(a));

        rid = ask(alice, 701);
        a = attestationFor(rid, word(1));
        a.questionHash = keccak256("another question");
        _expectMiss(rid, 701, 10, a, sign(a));

        rid = ask(alice, 701);
        a = attestationFor(rid, word(0));
        _expectMiss(rid, 701, 8, a, sign(a));

        rid = ask(alice, 701);
        a = attestationFor(rid, hex"01");
        _expectMiss(rid, 701, 9, a, sign(a));

        rid = ask(alice, 701);
        a = attestationFor(rid, bytes.concat(word(1), hex"00"));
        _expectMiss(rid, 701, 9, a, sign(a));

        rid = ask(alice, 1301);
        a = attestationFor(rid, word(2));
        _expectMiss(rid, 1301, 9, a, sign(a));

        rid = ask(alice, 1301);
        a = attestationFor(rid, word(0));
        _expectMiss(rid, 1301, 8, a, sign(a));

        rid = ask(alice, 1301);
        a = attestationFor(rid, word(1));
        assertTrue(deliver(rid, a));
        assertTrue(registry.hasTrait(alice, 1301));
    }

    function test_attestationForAnotherConsumerOrChainIsNeverAccepted() public {
        bytes32 rid = ask(alice, 701);
        OracleAttestation memory a = attestationFor(rid, word(1));
        // signed under another verifyingContract
        bytes32 ds = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("IdentityMD Oracle"),
                keccak256("2"),
                uint256(1),
                address(0xDEAD)
            )
        );
        bytes32 digestOther = keccak256(abi.encodePacked("\x19\x01", ds, _structHash(a)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ATTESTER_KEY, digestOther);
        _expectMiss(rid, 701, 2, a, abi.encodePacked(r, s, v));
        // signed for this consumer on another chain
        rid = ask(alice, 701);
        a = attestationFor(rid, word(1));
        vm.chainId(11155111);
        bytes memory sepolia = sign(a);
        vm.chainId(1);
        _expectMiss(rid, 701, 2, a, sepolia);
    }

    function test_mainnetQuestionAcceptedUnderSepoliaConsumerDomain() public {
        vm.chainId(11155111);
        bytes32 rid = ask(alice, 701);
        OracleAttestation memory a = attestationFor(rid, word(1));
        assertEq(a.chainId, 1);
        bytes32 sepoliaDigest = registry.attestationDigest(a);
        bytes memory sig = sign(a);
        vm.chainId(1);
        assertTrue(registry.attestationDigest(a) != sepoliaDigest, "signature domain binds the consumer chain");
        vm.chainId(11155111);
        assertTrue(deliver(rid, a, sig), "delivered under the 200,000 gas stipend");
        assertTrue(registry.hasTrait(alice, 701));
        assertEq(registry.pendingOf(alice, 701), bytes32(0));
    }

    function test_sepoliaQuestionMissesWithReasonThreeUnderSepoliaDomain() public {
        vm.chainId(11155111);
        bytes32 rid = ask(alice, 701);
        OracleAttestation memory a = attestationFor(rid, word(1));
        a.chainId = 11155111;
        _expectMiss(rid, 701, 3, a, sign(a));
    }

    function test_mainnetSignatureCannotAnswerSepoliaConsumer() public {
        vm.chainId(11155111);
        bytes32 rid = ask(alice, 701);
        OracleAttestation memory a = attestationFor(rid, word(1));
        vm.chainId(1);
        bytes memory sig = sign(a);
        vm.chainId(11155111);
        _expectMiss(rid, 701, 2, a, sig);
    }

    function _structHash(OracleAttestation memory a) internal pure returns (bytes32) {
        bytes32 th = keccak256(
            "OracleAttestation(bytes32 requestId,uint256 chainId,bytes32 questionHash,uint8 answerType,bytes answer,uint256 figure,uint64 fromBlock,uint64 toBlock,bytes32 blockHash,bytes32 panelJobId,uint16 panelSize,uint16 quorum,uint16 agreed,uint64 issuedAt,uint64 expiresAt)"
        );
        return keccak256(
            bytes.concat(
                abi.encode(
                    th, a.requestId, a.chainId, a.questionHash, a.answerType, keccak256(a.answer), a.figure, a.fromBlock
                ),
                abi.encode(
                    a.toBlock, a.blockHash, a.panelJobId, a.panelSize, a.quorum, a.agreed, a.issuedAt, a.expiresAt
                )
            )
        );
    }

    function test_onFailureClearsAndAllowsRetry() public {
        bytes32 rid = ask(alice, 701);
        vm.expectEmit(false, false, false, true);
        emit Registry.NoVerdict(rid, 701, 2, "disagreed", 0, 0);
        assertTrue(fail(rid, 2, "disagreed"));
        assertEq(registry.pendingOf(alice, 701), bytes32(0));
        assertFalse(isVerified(alice, 701));
        bytes32 rid2 = ask(alice, 701);
        assertTrue(rid2 != rid);
        // a failure for an unknown id is reason 1 and touches nothing
        vm.prank(address(intake));
        vm.expectEmit(false, false, false, true);
        emit Registry.Missed(rid, 0, 1);
        registry.onFailure(rid, 1, "body_refused", 0, 0, "");
        assertEq(registry.pendingOf(alice, 701), rid2);
    }

    function test_abandonOnlyAfterThirtyOneDaysAndStaleCallbackLeavesSuccessor() public {
        bytes32 rid = ask(alice, 701);
        vm.expectRevert(Registry.TooEarly.selector);
        registry.abandon(rid);
        vm.warp(block.timestamp + 31 days - 1);
        vm.expectRevert(Registry.TooEarly.selector);
        registry.abandon(rid);
        vm.warp(block.timestamp + 2);
        vm.prank(bob);
        vm.expectRevert(Registry.NotClaimant.selector);
        registry.abandon(rid);
        assertEq(registry.pendingOf(alice, 701), rid);
        vm.prank(alice);
        vm.expectEmit(false, false, false, true);
        emit Registry.Abandoned(rid);
        registry.abandon(rid);
        vm.expectRevert(abi.encodeWithSelector(Registry.NotPending.selector, rid));
        registry.abandon(rid);
        // the successor request
        bytes32 rid2 = ask(alice, 701);
        OracleAttestation memory a = attestationFor(rid2, word(1));
        // the late callback for the abandoned request: reason 1, successor index untouched
        vm.expectEmit(false, false, false, true);
        emit Registry.Missed(rid, 0, 1);
        assertTrue(deliver(rid, a));
        assertEq(registry.pendingOf(alice, 701), rid2);
        assertTrue(deliver(rid2, a));
        assertTrue(registry.hasTrait(alice, 701));
    }

    function test_strangerCannotDiscardLateValidAnswer() public {
        bytes32 rid = ask(alice, 701);
        OracleAttestation memory a = attestationFor(rid, word(1));
        a.issuedAt = uint64(T0 + 1 days);
        a.expiresAt = uint64(T0 + 31 days);
        bytes memory sig = sign(a);
        vm.warp(T0 + 31 days);
        vm.prank(bob);
        vm.expectRevert(Registry.TooEarly.selector);
        registry.abandon(rid);
        assertEq(registry.pendingOf(alice, 701), rid);
        assertTrue(deliver(rid, a, sig));
        assertTrue(registry.hasTrait(alice, 701));
    }

    function test_malformedEnvelopeIsNotDeliveredAndStaysPending() public {
        bytes32 rid = ask(alice, 701);
        // a 12-field tuple does not decode as the 15-field struct: the Intake records delivered == false
        bytes memory args = abi.encode(rid, bytes32(0), uint256(1), bytes32(0), uint8(3), bytes(""), uint256(0));
        assertFalse(intake.complete(rid, 0, args));
        assertEq(registry.pendingOf(alice, 701), rid, "still pending; abandon after 31 days");
    }

    function test_onResultGasWorstCase() public {
        // worst case: a community id appended, a card to refresh, cold storage everywhere
        uint256 tokenId = mint(alice);
        uint16 specId = register(bob, t1Spec(address(0xCAFE), "Received a token"));
        bytes32 rid = ask(alice, specId);
        OracleAttestation memory a = attestationFor(rid, word(7));
        bytes memory sig = sign(a);
        bytes memory data = abi.encodeCall(registry.onResult, (rid, a, sig));
        vm.prank(address(intake));
        uint256 g = gasleft();
        (bool ok,) = address(registry).call{gas: 200_000}(data);
        g = g - gasleft();
        assertTrue(ok);
        assertTrue(registry.hasTrait(alice, specId));
        assertEq(registry.verifiedSpecsOf(alice)[0], specId);
        assertLt(g, 180_000, "onResult must leave margin under the 200,000 stipend");
        emit log_named_uint("onResult worst-case gas", g);
        assertEq(registry.tokenOf(alice), tokenId);
    }

    // ------------------------------------------------------------------ 7: specs

    function test_registerSpecAssignsSequentialIdsAndIsImmutable() public {
        uint16 a = register(alice, t1Spec(address(0xCAFE), "First"));
        uint16 b = register(bob, t1Spec(address(0xCAFE), "Second"));
        assertEq(a, 10001);
        assertEq(b, 10002);
        assertEq(imd.balanceOf(address(registry)), 0, "fees leave the Registry");
        assertEq(registry.specOf(a).name, "First");
        assertEq(registry.traitName(b), "Second");
        (bytes memory body1,) = registry.composeBody(a, alice);
        (bytes memory body2,) = registry.composeBody(a, alice);
        assertEq(body1, body2);
    }

    function test_specGuards() public {
        fund(alice, 100 ether);
        Spec memory s = t1Spec(address(0xCAFE), "ok");
        s.kind = 6;
        _badSpec(s);
        s = t1Spec(address(0), "ok");
        _badSpec(s);
        s = t1Spec(address(0xCAFE), "ok");
        s.item = "function f(address)";
        _badSpec(s);
        s = t1Spec(address(0xCAFE), "ok");
        s.item = 'event Transfer(address indexed to) "';
        _badSpec(s);
        s = t1Spec(address(0xCAFE), "ok");
        s.arg = "";
        _badSpec(s);
        s = t1Spec(address(0xCAFE), "ok");
        s.arg = "to;";
        _badSpec(s);
        s = t1Spec(address(0xCAFE), "ok");
        s.threshold = 0;
        _badSpec(s);
        s = t1Spec(address(0xCAFE), "ok");
        s.toBlock = s.fromBlock + 7198;
        _badSpec(s);
        s = t1Spec(address(0xCAFE), "ok");
        s.toBlock = uint64(block.number);
        _badSpec(s);
        s = t1Spec(address(0xCAFE), 'na"me');
        _badSpec(s);
        s = t1Spec(address(0xCAFE), "");
        _badSpec(s);
        s = t1Spec(address(0xCAFE), "ok");
        s.sumArg = "x";
        _badSpec(s);
        s = t1Spec(address(0xCAFE), "ok");
        s.kind = 3;
        s.sumArg = "value";
        s.threshold = 33;
        _badSpec(s);
        s = t1Spec(address(0xCAFE), "ok");
        s.kind = 5;
        _badSpec(s); // target must be zero, item empty
        s = t1Spec(address(0), "ok");
        s.kind = 5;
        s.item = "";
        s.arg = "";
        s.fromBlock = uint64(block.number - 7000);
        s.toBlock = s.fromBlock;
        _badSpec(s); // too recent
        s.fromBlock = uint64(block.number - 7200);
        s.toBlock = s.fromBlock;
        vm.prank(alice);
        assertEq(registry.registerSpec(s, 0), 10001);
    }

    function _badSpec(Spec memory s) internal {
        vm.prank(alice);
        vm.expectRevert();
        registry.registerSpec(s, 0);
    }

    // ------------------------------------------------------------------ shared facts

    function _list(uint256 n) internal pure returns (address[] memory l) {
        l = new address[](n);
        for (uint256 i; i < n; ++i) {
            l[i] = address(uint160(0x1000 + i));
        }
    }

    function test_sharedFactFlow() public {
        fund(bob, PRICE);
        vm.prank(bob);
        registry.requestSharedFact(1201, PRICE);
        bytes32 rid = intake.lastId();
        assertEq(registry.sharedPending(1201), rid);
        fund(bob, PRICE);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Registry.AlreadyPending.selector, address(0), 1201));
        registry.requestSharedFact(1201, PRICE);

        address[] memory list = _list(32);
        list[3] = alice;
        OracleAttestation memory a = attestationFor(rid, abi.encode(list));
        vm.expectEmit(true, false, false, true);
        emit Registry.SharedFactStored(1201, rid, 32);
        assertTrue(deliver(rid, a));
        (bytes32 sr, bytes32 sh, uint16 n) = registry.sharedFact(1201);
        assertEq(sr, rid);
        assertEq(sh, keccak256(abi.encode(list)));
        assertEq(n, 32);
        assertEq(registry.sharedPending(1201), bytes32(0));
        fund(bob, PRICE);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Registry.FactAlreadyStored.selector, 1201));
        registry.requestSharedFact(1201, PRICE);

        address[] memory wrong = _list(32);
        vm.prank(alice);
        vm.expectRevert(Registry.ListMismatch.selector);
        registry.applySharedFact(1201, wrong);
        vm.prank(bob);
        vm.expectRevert(Registry.NotInList.selector);
        registry.applySharedFact(1201, list);
        // position 35 is beyond head 32
        vm.prank(address(uint160(0x1000 + 35)));
        vm.expectRevert(Registry.NotInList.selector);
        registry.applySharedFact(1201, list);
        vm.prank(alice);
        registry.applySharedFact(1201, list);
        assertTrue(registry.hasTrait(alice, 1201));
        (bytes32 vr, bytes32 vo, uint64 f, uint64 t) = registry.verified(alice, 1201);
        assertEq(vr, rid);
        assertEq(vo, a.requestId);
        assertEq(f, B_DEPLOY);
        assertEq(t, B_END);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Registry.AlreadyVerified.selector, alice, 1201));
        registry.applySharedFact(1201, list);
        vm.prank(address(uint160(0x1000 + 31)));
        registry.applySharedFact(1201, list);
    }

    function test_sharedFactBadEnvelopeIsAMissAndCanBeRequestedAgain() public {
        fund(bob, 10 ether);
        vm.prank(bob);
        registry.requestSharedFact(1201, PRICE);
        bytes32 rid = intake.lastId();
        // a dirty address word
        bytes memory env = abi.encode(_list(2));
        env[64] = 0xff;
        OracleAttestation memory a = attestationFor(rid, env);
        vm.expectEmit(false, false, false, true);
        emit Registry.Missed(rid, 1201, 9);
        assertTrue(deliver(rid, a));
        (bytes32 sr,,) = registry.sharedFact(1201);
        assertEq(sr, bytes32(0));
        // an empty list, an offset that is not 0x20, a too-long list, a truncated envelope
        bytes[4] memory bad = [
            abi.encode(new address[](0)),
            bytes.concat(abi.encode(uint256(0x40), uint256(1)), word(1)),
            abi.encode(_list(65)),
            bytes.concat(abi.encode(uint256(0x20), uint256(3)), word(1))
        ];
        for (uint256 i; i < 4; ++i) {
            vm.prank(bob);
            registry.requestSharedFact(1201, PRICE);
            rid = intake.lastId();
            a = attestationFor(rid, bad[i]);
            vm.expectEmit(false, false, false, true);
            emit Registry.Missed(rid, 1201, 9);
            assertTrue(deliver(rid, a));
        }
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Registry.NotASharedFact.selector, 701));
        registry.requestSharedFact(701, PRICE);
        vm.expectRevert(abi.encodeWithSelector(Registry.FactNotStored.selector, 1201));
        registry.applySharedFact(1201, _list(1));
    }

    // ------------------------------------------------------------------ reentrancy, 11

    function test_reentrantTokenCannotReenterMint() public {
        ReentrantIMD evil = new ReentrantIMD();
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
        evil.mint(alice, 1 ether);
        vm.prank(alice);
        evil.approve(address(r), type(uint256).max);
        evil.arm(abi.encodeCall(r.mintCard, ()));
        vm.prank(alice);
        r.mintCard();
        assertTrue(evil.reentryReverted(), "the re-entered mintCard reverted on the guard");
        assertEq(r.tokenOf(alice), 1);
        assertEq(evil.balanceOf(address(r)), 0);
    }

    function test_anyoneReadsAnyWalletAndNothingUsesTxOrigin() public {
        curator.set(alice, 0, true, 3, 1 ether, 1000);
        mint(alice);
        vm.prank(bob, address(0xF00D));
        assertTrue(registry.hasTrait(alice, 101));
        vm.prank(address(0xF00D), address(0xF00D));
        string memory uri = registry.tokenURI(1);
        assertGt(bytes(uri).length, 100);
        vm.expectRevert(abi.encodeWithSelector(Registry.NoCard.selector, 2));
        registry.tokenURI(2);
    }
}
