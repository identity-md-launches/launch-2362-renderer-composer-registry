// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {MockBurnExecutor} from "./mocks/MockBurnExecutor.sol";

import {Test} from "forge-std/Test.sol";
import {Registry} from "../src/Registry.sol";
import {Renderer} from "../src/Renderer.sol";
import {RendererHarness} from "./mocks/RendererHarness.sol";
import {Composer} from "../src/Composer.sol";
import {OracleAttestation} from "../src/interfaces/IOracleConsumer.sol";
import {Spec} from "../src/Types.sol";
import {MockCurator, MockIDMD, MockIMD, MockIntake} from "./mocks/Mocks.sol";

/// @notice Shared fixture: mainnet chain id, the Curator mock at its real address, the registry at the
///         fixtures' synthetic consumer `0x...c0de`, a test attester key, and attestation helpers.
abstract contract Base is Test {
    address internal constant CURATOR_ADDR = 0xcB0b0531e86A9aC36Fa865cA8e3dbccF047FDA91;
    address internal constant REGISTRY_ADDR = 0x000000000000000000000000000000000000c0DE;
    address internal constant C1A1 = 0x000000000000000000000000000000000000C1a1;
    address internal constant AC1A1 = 0x00000000000000000000000000000000000aC1a1;
    uint256 internal constant ATTESTER_KEY = 0xA11CE;
    uint64 internal constant B_DEPLOY = 0x189378e;
    uint64 internal constant B_FIRST1000 = 0x1893b91;
    uint64 internal constant B_H24 = 0x1895395;
    uint64 internal constant B_END = 0x18984a4;
    uint256 internal constant PRICE = 0.5 ether;
    uint256 internal constant T0 = 1_791_700_000;

    MockCurator internal curator;
    MockIDMD internal idmd;
    MockIMD internal imd;
    MockBurnExecutor internal executor;
    MockIntake internal intake;
    RendererHarness internal renderer;
    Composer internal composer;
    Registry internal registry;
    address internal attester;

    function setUp() public virtual {
        vm.chainId(1);
        vm.roll(26_200_000);
        vm.warp(T0);
        attester = vm.addr(ATTESTER_KEY);
        deployCodeTo("Mocks.sol:MockCurator", CURATOR_ADDR);
        curator = MockCurator(CURATOR_ADDR);
        idmd = new MockIDMD();
        imd = new MockIMD();
        executor = new MockBurnExecutor();
        intake = new MockIntake(address(imd));
        renderer = new RendererHarness();
        composer = new Composer();
        deployCodeTo(
            "Registry.sol:Registry",
            abi.encode(
                CURATOR_ADDR,
                address(imd),
                address(intake),
                attester,
                address(renderer),
                address(composer),
                address(executor)
            ),
            REGISTRY_ADDR
        );
        registry = Registry(REGISTRY_ADDR);
    }

    // ------------------------------------------------------------------ helpers

    function fund(address who, uint256 amount) internal {
        imd.mint(who, amount);
        vm.prank(who);
        imd.approve(address(registry), type(uint256).max);
    }

    function mint(address who) internal returns (uint256 id) {
        fund(who, 0.1 ether);
        vm.prank(who);
        id = registry.mintCard();
    }

    function ask(address who, uint16 traitId) internal returns (bytes32 requestId) {
        fund(who, PRICE);
        uint16[] memory ids = new uint16[](1);
        ids[0] = traitId;
        vm.prank(who);
        registry.upgrade(ids, PRICE);
        requestId = intake.lastId();
    }

    /// @dev A well-formed attestation for a pending request: the pending record's hash, the trait's
    ///      window, the template's panel, a fresh window, answer `answer`.
    function attestationFor(bytes32 requestId, bytes memory answer) internal view returns (OracleAttestation memory a) {
        (, uint16 traitId,, bytes32 qh) = registry.pendingRequest(requestId);
        Spec memory s = registry.specOf(traitId);
        bool panel = s.kind == 5 || s.kind == 3 || s.kind == 6;
        a.requestId = bytes32(uint256(uint128(uint256(keccak256(abi.encode("uuid", requestId))))) << 128);
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

    function sign(OracleAttestation memory a) internal view returns (bytes memory) {
        return signWith(ATTESTER_KEY, a);
    }

    function signWith(uint256 key, OracleAttestation memory a) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, registry.attestationDigest(a));
        return abi.encodePacked(r, s, v);
    }

    /// @dev Delivers through the mock Intake under the real stipend; returns `delivered`.
    function deliver(bytes32 requestId, OracleAttestation memory a, bytes memory sig) internal returns (bool) {
        return intake.complete(requestId, 0, abi.encode(requestId, a, sig));
    }

    function deliver(bytes32 requestId, OracleAttestation memory a) internal returns (bool) {
        return deliver(requestId, a, sign(a));
    }

    function fail(bytes32 requestId, uint8 status, bytes32 reason) internal returns (bool) {
        return
            intake.complete(requestId, status, abi.encode(requestId, status, reason, uint16(0), uint16(0), bytes("")));
    }

    function word(uint256 v) internal pure returns (bytes memory) {
        return abi.encode(v);
    }

    function t1Spec(address target, string memory name) internal pure returns (Spec memory s) {
        s.kind = 1;
        s.target = target;
        s.item = "event Transfer(address indexed from, address indexed to, uint256 value)";
        s.arg = "to";
        s.threshold = 1;
        s.fromBlock = B_DEPLOY;
        s.toBlock = B_END;
        s.name = name;
    }

    function register(address who, Spec memory s) internal returns (uint16 id) {
        fund(who, registry.SPEC_FEE());
        vm.prank(who);
        id = registry.registerSpec(s, 0);
    }

    function isVerified(address c, uint16 t) internal view returns (bool) {
        (bytes32 rid,,,) = registry.verified(c, t);
        return rid != 0;
    }
}
