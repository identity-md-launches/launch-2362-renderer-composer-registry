// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {IBurnExecutor} from "../../src/interfaces/IBurnExecutor.sol";

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Registry} from "../../src/Registry.sol";
import {Renderer} from "../../src/Renderer.sol";
import {Composer} from "../../src/Composer.sol";
import {IWhitelistCurator} from "../../src/interfaces/IWhitelistCurator.sol";
import {IIDMD} from "../../src/interfaces/IIDMD.sol";
import {IIntake} from "../../src/interfaces/IIntake.sol";
import {OracleAttestation} from "../../src/interfaces/IOracleConsumer.sol";
import {Spec} from "../../src/Types.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Opt-in archive integration checks. Run using Forge's --fork-url and --fork-block-number
///         CLI arguments, never environment reads in a test. The offline suite skips without live code.
contract MainnetForkTest is Test {
    uint256 internal constant FORK_BLOCK = 26_237_654;
    address internal constant EXECUTOR = 0xe29386719C155B6847aD5a4E97C6674f10ffc750;

    address internal constant CURATOR = 0xcB0b0531e86A9aC36Fa865cA8e3dbccF047FDA91;
    address internal constant IDMD = 0x0000eC93127BAA929E58E97dd0095A2BFb38ec1D;
    address internal constant IMD = 0xD34a99Bc0f67aE1bbd63C660e6d0b0dd03E263B7;
    address internal constant INTAKE_V2 = 0xa43e6F75ee006411F79Ac1C84120606C2330DE82;
    address internal constant ATTESTER = 0x5598Aa9146215Bc13eb26f2c692Ad1461Fd32982;
    address internal constant WRITER = 0x3d3C0Df7C1a17d384545e9D7C8228897bD9625CB;
    bytes32 internal constant ACTION = bytes32("oracle.request@oracle-1");

    // `FirstDeposit` indices 1, 1000 and 19522, read from the Curator's logs at the anchor blocks
    // of CATALOG.md section 1 (0x18937a0, 0x1893b91, 0x1898270). Public onchain facts, not goldens.
    address internal constant FIRST_IN = 0x200E710aCAA6A93bbc77146026328C40F1d60fB1;
    address internal constant THOUSANDTH = 0x3730cE983bcde8a76c00e5FAfeA7B2F89fEB10b0;
    address internal constant LAST_IN = 0x2E96662e64eD947a9656Fb586b2a3596ea8bA6c2;

    uint256 internal constant ATTESTER_KEY = 0xF04C;
    uint64 internal constant B_DEPLOY = 0x189378e;
    uint64 internal constant B_H24 = 0x1895395;
    uint64 internal constant B_END = 0x18984a4;

    IWhitelistCurator internal curator = IWhitelistCurator(CURATOR);
    IIDMD internal idmd = IIDMD(IDMD);
    IERC20 internal imd = IERC20(IMD);
    IIntake internal intake = IIntake(INTAKE_V2);
    Registry internal registry;
    address internal attester;
    address internal alice = address(0xA11CE);
    bool internal forked;

    function setUp() public {
        if (CURATOR.code.length == 0 || EXECUTOR.code.length == 0) return;
        require(block.number == FORK_BLOCK, "pin the CLI fork block to 26237654");
        forked = true;
        assertEq(block.chainid, 1, "the fork must be Ethereum mainnet");
        attester = vm.addr(ATTESTER_KEY);
        Renderer renderer = new Renderer();
        Composer composer = new Composer();
        registry = new Registry(CURATOR, IMD, INTAKE_V2, attester, address(renderer), address(composer), EXECUTOR);
    }

    modifier onFork() {
        if (!forked) {
            vm.skip(true);
            return;
        }
        _;
    }

    // ------------------------------------------------------------------ the Curator

    function test_fork_pinnedBlockIsTheOneRecorded() public onFork {
        assertEq(block.number, FORK_BLOCK);
        assertEq(blockhash(FORK_BLOCK - 1) != bytes32(0), true);
    }

    function test_fork_curatorIsSettledWithTheBriefsConstants() public onFork {
        assertTrue(curator.isSettled(), "THE LIST settled in hour 66");
        assertEq(curator.hourDuration(), 3600);
        assertGt(curator.currentHour(), 66);
        assertEq(curator.creditCap(), 1000 ether);
    }

    function test_fork_firstContributorIsAnHourZeroEarlyBird() public onFork {
        (uint256 hour, bool joined) = curator.firstHourOf(FIRST_IN);
        assertTrue(joined);
        assertEq(hour, 0);
        assertTrue(registry.hasTrait(FIRST_IN, 101));
        assertTrue(registry.hasTrait(FIRST_IN, 201));
        assertTrue(registry.hasTrait(FIRST_IN, 202));
        // the live views agree with the direct-read rules tier by tier
        _assertDirectRulesAgree(FIRST_IN);
    }

    function test_fork_thousandthContributorJoinedInsideTheFirstThousandWindow() public onFork {
        (uint256 hour, bool joined) = curator.firstHourOf(THOUSANDTH);
        assertTrue(joined);
        assertLe(hour, 3, "index 1000 landed in block 0x1893b91, hour 3 per the anchors");
        assertTrue(registry.hasTrait(THOUSANDTH, 101));
        _assertDirectRulesAgree(THOUSANDTH);
    }

    function test_fork_lastContributorIsNoEarlyBird() public onFork {
        (uint256 hour, bool joined) = curator.firstHourOf(LAST_IN);
        assertTrue(joined);
        assertEq(hour, 64, "index 19522 came in hour 64");
        assertTrue(registry.hasTrait(LAST_IN, 101));
        assertFalse(registry.hasTrait(LAST_IN, 201));
        assertFalse(registry.hasTrait(LAST_IN, 202));
        _assertDirectRulesAgree(LAST_IN);
    }

    function test_fork_nonMemberReadsZeroFalseAndHasNoCuratorTrait() public onFork {
        // the registry itself never deposited; the raw struct would read "hour 0" for it
        (uint256 hour, bool joined) = curator.firstHourOf(address(registry));
        assertEq(hour, 0);
        assertFalse(joined);
        for (uint16 id = 101; id <= 503; ++id) {
            if (!_isDirectId(id)) continue;
            assertFalse(registry.hasTrait(address(registry), id), "a non-member has no Curator trait");
        }
        assertEq(registry.traitsOf(address(registry)).length, 0);
    }

    function _assertDirectRulesAgree(address w) internal view {
        uint256 n = curator.txCountOf(w);
        uint256 c = curator.contributedBy(w);
        uint256 p = curator.pointsOf(w);
        assertEq(registry.hasTrait(w, 301), n >= 3);
        assertEq(registry.hasTrait(w, 302), n >= 5);
        assertEq(registry.hasTrait(w, 303), n >= 10);
        assertEq(registry.hasTrait(w, 401), c >= 1e18);
        assertEq(registry.hasTrait(w, 402), c >= 1e19);
        assertEq(registry.hasTrait(w, 403), c >= 1e20);
        assertEq(registry.hasTrait(w, 404), c >= 8e20);
        assertEq(registry.hasTrait(w, 501), p >= 1000);
        assertEq(registry.hasTrait(w, 502), p >= 3162);
        assertEq(registry.hasTrait(w, 503), p >= 10000);
        assertFalse(registry.hasTrait(w, 601));
        assertFalse(registry.hasDirectTrait(w, 601));
    }

    function _isDirectId(uint16 id) internal pure returns (bool) {
        return id == 101 || id == 201 || id == 202 || (id >= 301 && id <= 303) || (id >= 401 && id <= 404)
            || (id >= 501 && id <= 503);
    }

    // ------------------------------------------------------------------ IDMD

    function test_fork_operatorTraitRequiresAnAttestationEvenForASeatHolder() public onFork {
        address holder = idmd.ownerOf(1);
        assertTrue(holder != address(0));
        assertFalse(registry.hasTrait(holder, 601));
        // OpenZeppelin's balanceOf(0) reverts on the real collection; the registry answers false
        vm.expectRevert();
        idmd.balanceOf(address(0));
        assertFalse(registry.hasTrait(address(0), 601));
        assertFalse(registry.hasTrait(address(registry), 601));
    }

    // ------------------------------------------------------------------ Intake v2

    function test_fork_intakeV2SellsTheActionAsTheBriefRecords() public onFork {
        assertEq(intake.priceOf(ACTION, IMD), 0.5 ether, "0.5 IMD per request");
        assertEq(intake.priceOf(ACTION, address(0)), 0, "the native coin is not sold");
        assertEq(intake.priceOf(bytes32("oracle.request"), IMD), 0, "only the versioned spelling is sold");
        assertEq(intake.callbackGas(), 200_000);
        assertEq(IntakeViews(INTAKE_V2).writer(), WRITER);
        assertEq(intake.failureSelectorOf(keccak256("never asked")), bytes4(0));
    }

    function test_fork_upgradeThroughTheRealIntakeThenCompleteFromTheWriter() public onFork {
        deal(IMD, alice, 2 ether);
        vm.startPrank(alice);
        imd.approve(address(registry), type(uint256).max);
        uint16[] memory ids = new uint16[](2);
        ids[0] = 701;
        ids[1] = 1301;
        registry.upgrade(ids, 0.5 ether);
        vm.stopPrank();
        assertEq(imd.balanceOf(alice), 1 ether, "two prices pulled");
        assertEq(imd.balanceOf(address(registry)), 0, "nothing stays in the registry on a claimant-paid request");
        bytes32 rid = registry.pendingOf(alice, 701);
        bytes32 rid2 = registry.pendingOf(alice, 1301);
        assertTrue(rid != 0 && rid2 != 0 && rid != rid2);
        assertEq(intake.failureSelectorOf(rid), registry.onFailure.selector, "the failure hook is registered");
        assertEq(intake.failureSelectorOf(rid2), registry.onFailure.selector);

        // status 0 from the writer, under the Intake's real 200,000-gas call
        OracleAttestation memory a = _attestationFor(rid, 701, abi.encode(uint256(2)));
        bytes memory args = abi.encode(rid, a, _sign(a));
        vm.prank(address(0xBAD));
        vm.expectRevert();
        IntakeComplete(INTAKE_V2).complete(rid, 0, bytes32(0), "", args);
        vm.prank(WRITER);
        vm.recordLogs();
        IntakeComplete(INTAKE_V2).complete(rid, 0, bytes32(0), "", args);
        assertTrue(_deliveredFlag(), "delivered == true");
        assertTrue(registry.hasTrait(alice, 701));
        (bytes32 vr, bytes32 vo, uint64 f, uint64 t) = registry.verified(alice, 701);
        assertEq(vr, rid);
        assertEq(vo, a.requestId);
        assertEq(f, B_H24);
        assertEq(t, B_END);
        assertEq(registry.pendingOf(alice, 701), bytes32(0));
        vm.prank(WRITER);
        vm.expectRevert();
        IntakeComplete(INTAKE_V2).complete(rid, 0, bytes32(0), "", args); // AlreadyCompleted

        // status 2 for the panel question reaches onFailure through the real hook
        bytes memory fargs = abi.encode(rid2, uint8(2), bytes32("disagreed"), uint16(5), uint16(11), bytes(""));
        vm.prank(WRITER);
        vm.expectEmit(false, false, false, true, address(registry));
        emit Registry.NoVerdict(rid2, 1301, 2, "disagreed", 5, 11);
        IntakeComplete(INTAKE_V2).complete(rid2, 2, bytes32(0), "", fargs);
        assertEq(registry.pendingOf(alice, 1301), bytes32(0));
        assertFalse(registry.hasTrait(alice, 1301));
        // the pair may be asked again, and paid again
        vm.prank(alice);
        ids = new uint16[](1);
        ids[0] = 1301;
        registry.upgrade(ids, 0.5 ether);
        assertEq(imd.balanceOf(alice), 0.5 ether);
    }

    function test_fork_attestationSignedForAnotherConsumerMissesOnTheRealIntake() public onFork {
        deal(IMD, alice, 1 ether);
        vm.startPrank(alice);
        imd.approve(address(registry), type(uint256).max);
        uint16[] memory ids = new uint16[](1);
        ids[0] = 801;
        registry.upgrade(ids, 0.5 ether);
        vm.stopPrank();
        bytes32 rid = registry.pendingOf(alice, 801);
        OracleAttestation memory a = _attestationFor(rid, 801, abi.encode(uint256(1)));
        // signed with the right key but for a registry at another address
        Registry other = new Registry(
            CURATOR, IMD, INTAKE_V2, attester, address(registry.renderer()), address(registry.composer()), EXECUTOR
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ATTESTER_KEY, other.attestationDigest(a));
        vm.prank(WRITER);
        vm.expectEmit(false, false, false, true, address(registry));
        emit Registry.Missed(rid, 801, 2);
        IntakeComplete(INTAKE_V2).complete(rid, 0, bytes32(0), "", abi.encode(rid, a, abi.encodePacked(r, s, v)));
        assertFalse(registry.hasTrait(alice, 801));
        assertEq(registry.pendingOf(alice, 801), bytes32(0), "a miss clears the pair");
    }

    function test_fork_memberMintsAndRendersAgainstTheRealCurator() public onFork {
        deal(IMD, FIRST_IN, 0.1 ether);
        vm.startPrank(FIRST_IN);
        imd.approve(address(registry), 0.1 ether);
        uint256 id = registry.mintCard();
        vm.stopPrank();
        assertEq(registry.claimantOf(id), FIRST_IN);
        uint16[] memory t = registry.traitsOf(FIRST_IN);
        assertGe(t.length, 3, "101, 201, 202 at least");
        assertEq(t[0], 101);
        assertEq(t[1], 201);
        assertEq(t[2], 202);
        string memory uri = registry.tokenURI(id);
        assertGt(bytes(uri).length, 1000);
        assertEq(imd.balanceOf(address(registry)), 0, "the mint fee leaves the Registry");
    }

    function test_fork_mintForwardsFeeAndPreviewIncludesItWithinLiveLimits() public onFork {
        uint256 balanceBefore = imd.balanceOf(EXECUTOR);
        (uint256 sendBefore,,) = IBurnExecutor(EXECUTOR).previewBridge();
        deal(IMD, alice, 0.1 ether);
        vm.startPrank(alice);
        imd.approve(address(registry), 0.1 ether);
        registry.mintCard();
        vm.stopPrank();
        uint256 balanceAfter = imd.balanceOf(EXECUTOR);
        assertEq(balanceAfter, balanceBefore + 0.1 ether);
        assertEq(imd.balanceOf(address(registry)), 0);
        (uint256 sendAfter, uint256 receiveAfter, uint256 nativeFee) = IBurnExecutor(EXECUTOR).previewBridge();
        assertGt(sendAfter, 0, "live executor is bridgeable at the pinned block");
        assertGe(sendAfter, sendBefore);
        assertLe(sendAfter, balanceAfter);
        assertLe(sendAfter - sendBefore, 0.1 ether);
        assertGt(receiveAfter, 0);
        assertGt(nativeFee, 0);
        // Quote the hypothetical old balance against the same post-mint OFT configuration.
        // If the send did not grow by the fee, the same live cap must constrain both amounts.
        (uint256 oldBalanceSend,,) = ExecutorQuote(EXECUTOR).previewBridge(balanceBefore);
        assertEq(oldBalanceSend, sendBefore);
        if (sendAfter - sendBefore < 0.1 ether) assertEq(sendAfter, sendBefore, "OFT limit, not a lost fee");
    }

    // ------------------------------------------------------------------ helpers

    function _attestationFor(bytes32 rid, uint16 traitId, bytes memory answer)
        internal
        view
        returns (OracleAttestation memory a)
    {
        (,,, bytes32 qh) = registry.pendingRequest(rid);
        Spec memory s = registry.specOf(traitId);
        bool panel = s.kind == 5;
        a.requestId = bytes32(uint256(uint128(uint256(keccak256(abi.encode("uuid", rid))))) << 128);
        a.chainId = 1;
        a.questionHash = qh;
        a.answerType = s.kind == 3 ? 4 : (s.kind == 1 || s.kind == 2) ? 3 : 0;
        a.answer = answer;
        a.fromBlock = s.fromBlock;
        a.toBlock = s.toBlock;
        a.blockHash = keccak256("block");
        a.panelJobId = keccak256("panel");
        a.panelSize = panel ? 11 : 5;
        a.quorum = panel ? 7 : 3;
        a.agreed = panel ? 7 : 3;
        a.issuedAt = uint64(block.timestamp);
        a.expiresAt = uint64(block.timestamp + 30 days);
    }

    function _sign(OracleAttestation memory a) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ATTESTER_KEY, registry.attestationDigest(a));
        return abi.encodePacked(r, s, v);
    }

    /// @dev The Intake's `Completed(bytes32 indexed requestId, uint8 status, bytes32 resultHash, string uri,
    ///      bool delivered)`: the last word of its data is the flag.
    function _deliveredFlag() internal returns (bool) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = logs.length; i > 0; --i) {
            if (logs[i - 1].emitter == INTAKE_V2 && logs[i - 1].topics.length == 2) {
                (,,, bool delivered) = abi.decode(logs[i - 1].data, (uint8, bytes32, string, bool));
                return delivered;
            }
        }
        revert("no Completed event");
    }
}

interface IntakeViews {
    function writer() external view returns (address);
}

interface IntakeComplete {
    function complete(bytes32 requestId, uint8 status, bytes32 resultHash, string calldata uri, bytes calldata args)
        external;
}

interface ExecutorQuote {
    function previewBridge(uint256) external view returns (uint256, uint256, uint256);
}
