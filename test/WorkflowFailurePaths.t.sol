// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Base} from "./Base.t.sol";
import {MockIMD, MockIntake} from "./mocks/Mocks.sol";
import {Registry} from "src/Registry.sol";
import {Composer} from "src/Composer.sol";
import {OracleAttestation} from "src/interfaces/IOracleConsumer.sol";
import {Spec} from "src/Types.sol";

/// @notice Fault injection at an ERC20 transfer boundary. The ordinary successful path is unchanged.
contract PaymentFaultIMD is MockIMD {
    uint256 public attempts;
    uint256 public failAt;
    bool public returnFalse;

    error PaymentBlocked(uint256 attempt);

    function arm(uint256 attempt, bool falseResult) external {
        failAt = attempt;
        returnFalse = falseResult;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        ++attempts;
        if (attempts == failAt) {
            if (returnFalse) return false;
            revert PaymentBlocked(attempts);
        }
        return super.transferFrom(from, to, amount);
    }
}

contract WorkflowFailurePathsTest is Base {
    address internal alice;
    address internal bob;
    PaymentFaultIMD internal faultToken;

    function setUp() public override {
        super.setUp();
        alice = makeAddr("failure claimant");
        bob = makeAddr("independent claimant");
        faultToken = new PaymentFaultIMD();
        imd = faultToken;
        intake = new MockIntake(address(imd));
        registry = new Registry(
            address(curator),
            address(imd),
            address(intake),
            attester,
            address(renderer),
            address(composer),
            address(executor)
        );
    }

    function _ids(uint256 n) internal pure returns (uint16[] memory ids) {
        uint16[11] memory catalog = [uint16(601), 701, 801, 901, 1001, 1101, 1102, 1103, 1104, 1105, 1301];
        ids = new uint16[](n);
        for (uint256 i; i < n; ++i) {
            ids[i] = catalog[i];
        }
    }

    function _one(uint16 id) internal pure returns (uint16[] memory ids) {
        ids = new uint16[](1);
        ids[0] = id;
    }

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_laterIntakePaymentFailureUnwindsTheEntireBatch(uint8 count, uint8 failIndex, uint96 price)
        public
    {
        uint256 n = bound(count, 2, 11);
        uint256 failedPayment = bound(failIndex, 2, n);
        uint256 p = bound(price, 1, 100 ether);
        intake.setPrice(p);
        imd.mint(alice, n * p);
        vm.prank(alice);
        imd.approve(address(registry), n * p);
        // Transfer 1 funds the batch; subsequent transfers collect each oracle payment.
        faultToken.arm(failedPayment + 1, false);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(PaymentFaultIMD.PaymentBlocked.selector, failedPayment + 1));
        registry.upgrade(_ids(n), p);
        assertEq(imd.balanceOf(alice), n * p);
        assertEq(imd.allowance(alice, address(registry)), n * p);
        assertEq(imd.allowance(address(registry), address(intake)), 0);
        assertEq(imd.balanceOf(address(intake)), 0);
        assertEq(imd.balanceOf(address(registry)), 0);
        assertEq(intake.nonce(), 0);
        assertEq(faultToken.attempts(), 0, "token state also rolls back");
        uint16[] memory ids = _ids(n);
        for (uint256 i; i < n; ++i) {
            assertEq(registry.pendingOf(alice, ids[i]), bytes32(0));
        }

        faultToken.arm(0, false);
        vm.prank(alice);
        registry.upgrade(ids, p);
        assertEq(intake.nonce(), n);
        assertEq(imd.balanceOf(alice), 0);
        assertEq(imd.balanceOf(address(intake)), n * p);
        assertEq(imd.balanceOf(address(registry)), 0);
        assertEq(imd.allowance(address(registry), address(intake)), 0);
        for (uint256 i; i < n; ++i) {
            bytes32 rid = registry.pendingOf(alice, ids[i]);
            assertTrue(rid != 0, "every request can be retried after an atomic revert");
            (address c, uint16 t,,) = registry.pendingRequest(rid);
            assertEq(c, alice);
            assertEq(t, ids[i]);
        }
    }

    function test_duplicateAtEndUnwindsEarlierDistinctRequests() public {
        fund(alice, 3 * PRICE);
        uint16[] memory ids = _ids(3);
        ids[2] = 601;
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Registry.AlreadyPending.selector, alice, uint16(601)));
        registry.upgrade(ids, PRICE);
        assertEq(imd.balanceOf(alice), 3 * PRICE);
        assertEq(imd.balanceOf(address(intake)), 0);
        assertEq(registry.pendingOf(alice, 601), bytes32(0));
        assertEq(registry.pendingOf(alice, 701), bytes32(0));
        assertEq(intake.nonce(), 0);
        assertEq(faultToken.attempts(), 0);
    }

    function test_mintDependencyFailureRollsBackTheAlreadyForwardedFee() public {
        fund(alice, registry.MINT_FEE());
        vm.mockCallRevert(
            address(composer),
            abi.encodeCall(composer.directSnapshot, (alice, registry.curator())),
            bytes("snapshot unavailable")
        );
        vm.prank(alice);
        vm.expectRevert(bytes("snapshot unavailable"));
        registry.mintCard();
        assertEq(imd.balanceOf(alice), registry.MINT_FEE());
        assertEq(imd.balanceOf(address(executor)), 0);
        assertEq(registry.totalSupply(), 0);
        assertEq(registry.tokenOf(alice), 0);
        assertEq(registry.claimantOf(1), address(0));
        assertEq(registry.mintedAtBlock(1), 0);
        assertEq(registry.frozenDirect(1), 0);
        vm.clearMockedCalls();
        vm.prank(alice);
        assertEq(registry.mintCard(), 1, "the reverted mint consumes no id");
        assertEq(imd.balanceOf(address(executor)), registry.MINT_FEE());
    }

    function test_falseReturnOnFeeTransferCannotCreateCardOrSpec() public {
        fund(alice, registry.MINT_FEE() + registry.SPEC_FEE());
        faultToken.arm(1, true);
        bytes memory failure = abi.encodeWithSignature("SafeERC20FailedOperation(address)", address(imd));
        vm.prank(alice);
        vm.expectRevert(failure);
        registry.mintCard();
        Spec memory spec = t1Spec(CURATOR_ADDR, "Fee receipt");
        vm.prank(alice);
        vm.expectRevert(failure);
        registry.registerSpec(spec, 10001);
        assertEq(registry.totalSupply(), 0);
        assertEq(registry.nextSpecId(), 10001);
        assertEq(imd.balanceOf(address(executor)), 0);
        assertEq(imd.balanceOf(alice), registry.MINT_FEE() + registry.SPEC_FEE());
        assertEq(faultToken.attempts(), 0);
    }

    function test_invalidSpecIsRejectedBeforeAnyPaymentIsAttempted() public {
        fund(alice, registry.SPEC_FEE());
        faultToken.arm(1, false);
        Spec memory s = t1Spec(CURATOR_ADDR, "Bad receipt");
        s.arg = "value"; // A real data field is still not an indexed address.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Composer.BadSpec.selector, "arg"));
        registry.registerSpec(s, 10001);
        assertEq(faultToken.attempts(), 0);
        assertEq(registry.nextSpecId(), 10001);
        assertEq(imd.balanceOf(alice), registry.SPEC_FEE());
    }

    /// @notice Collision protection applies across shared and personal indices, in either direction.
    function testFuzz_liveRequestCollisionAcrossNamespacesIsAtomic(bool sharedFirst) public {
        fund(alice, PRICE);
        vm.prank(alice);
        if (sharedFirst) registry.requestSharedFact(1201, PRICE);
        else registry.upgrade(_one(601), PRICE);
        bytes32 original = intake.lastId();
        bytes memory originalBody = intake.bodyOf(original);
        (address c, uint16 t, uint64 at, bytes32 q) = registry.pendingRequest(original);
        fund(bob, PRICE);
        intake.forceNextId(original);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Registry.RequestIdTaken.selector, original));
        if (sharedFirst) registry.upgrade(_one(701), PRICE);
        else registry.requestSharedFact(1201, PRICE);
        assertEq(imd.balanceOf(bob), PRICE);
        assertEq(imd.balanceOf(address(intake)), PRICE);
        assertEq(imd.balanceOf(address(registry)), 0);
        assertEq(imd.allowance(address(registry), address(intake)), 0);
        assertEq(intake.nonce(), 1);
        assertEq(intake.bodyOf(original), originalBody);
        (address afterC, uint16 afterT, uint64 afterAt, bytes32 afterQ) = registry.pendingRequest(original);
        assertEq(abi.encode(afterC, afterT, afterAt, afterQ), abi.encode(c, t, at, q));
        assertEq(registry.sharedPending(1201), sharedFirst ? original : bytes32(0));
        assertEq(registry.pendingOf(alice, 601), sharedFirst ? bytes32(0) : original);
        assertEq(registry.pendingOf(bob, 701), bytes32(0));
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_sharedDeadlineHasNoSecondWithBothAbandonAndValidDelivery(uint32 issuedDelay, bool deliverFirst)
        public
    {
        fund(alice, PRICE);
        vm.prank(alice);
        registry.requestSharedFact(1201, PRICE);
        bytes32 rid = intake.lastId();
        address[] memory list = new address[](32);
        for (uint256 i; i < list.length; ++i) {
            list[i] = makeAddr(string.concat("ranked ", vm.toString(i)));
        }
        list[0] = alice;
        OracleAttestation memory a = attestationFor(rid, abi.encode(list));
        a.issuedAt = uint64(T0 + bound(issuedDelay, 0, 1 days));
        a.expiresAt = a.issuedAt + 30 days;
        // Deliver at this particular attestation's last valid second, then replay the alternative order.
        vm.warp(a.expiresAt);
        vm.prank(bob);
        vm.expectRevert(Registry.TooEarly.selector);
        registry.abandon(rid);
        uint256 snapshotId = vm.snapshotState();
        assertTrue(deliver(rid, a));
        (bytes32 stored,,) = registry.sharedFact(1201);
        assertEq(stored, rid);
        assertTrue(vm.revertToState(snapshotId));
        vm.warp(T0 + 31 days + 1);
        if (deliverFirst) {
            vm.expectEmit(false, false, false, true, address(registry));
            emit Registry.Missed(rid, 1201, 7);
            assertTrue(deliver(rid, a));
            vm.prank(bob);
            vm.expectRevert(abi.encodeWithSelector(Registry.NotPending.selector, rid));
            registry.abandon(rid);
        } else {
            vm.prank(bob);
            registry.abandon(rid);
            vm.expectEmit(false, false, false, true, address(registry));
            emit Registry.Missed(rid, 0, 1);
            assertTrue(deliver(rid, a));
        }
        (stored,,) = registry.sharedFact(1201);
        assertEq(stored, bytes32(0));
        assertEq(registry.sharedPending(1201), bytes32(0));
        assertEq(imd.balanceOf(address(intake)), PRICE, "timeouts and rejection do not refund paid prices");
        assertEq(imd.balanceOf(alice), 0);
        fund(bob, PRICE);
        vm.prank(bob);
        registry.requestSharedFact(1201, PRICE);
        assertTrue(registry.sharedPending(1201) != rid, "a stranger can pay for the successor");
    }
}
