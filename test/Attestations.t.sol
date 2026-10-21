// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {MockBurnExecutor} from "./mocks/MockBurnExecutor.sol";

import {Test} from "forge-std/Test.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {OracleAttestation} from "../src/interfaces/IOracleConsumer.sol";
import {Registry} from "../src/Registry.sol";
import {Renderer} from "../src/Renderer.sol";
import {Composer} from "../src/Composer.sol";
import {MockCurator, MockIDMD, MockIntake, MockIMD} from "./mocks/Mocks.sol";

/// @notice Signature recovery over the five served mainnet attestations: each recovers the attester
///         under its own domain (the registry's digest, deployed at that domain's `verifyingContract`)
///         and does not under any other. The loader maps the served `answerType` name to its code.
contract AttestationsTest is Test {
    address internal constant ATTESTER = 0x5598Aa9146215Bc13eb26f2c692Ad1461Fd32982;
    string[5] internal FILES = [
        "2026-10-10-link-pilot",
        "2026-10-11-nonce-true",
        "2026-10-11-nonce-false",
        "2026-10-10-meatbag-consumer",
        "2026-10-11-feed-consumer-v2"
    ];

    Renderer internal renderer;
    Composer internal composer;

    function setUp() public {
        vm.chainId(1);
        renderer = new Renderer();
        composer = new Composer();
    }

    function _code(string memory name) internal pure returns (uint8) {
        bytes32 h = keccak256(bytes(name));
        if (h == keccak256("bool")) return 0;
        if (h == keccak256("address")) return 1;
        if (h == keccak256("bytes32")) return 2;
        if (h == keccak256("uint256")) return 3;
        if (h == keccak256("address[]")) return 4;
        if (h == keccak256("bytes32[]")) return 5;
        revert("unknown answerType name");
    }

    function _load(string memory file)
        internal
        view
        returns (OracleAttestation memory a, bytes memory sig, address consumer, uint256 chainId)
    {
        string memory j = vm.readFile(string.concat("reference/attestations/", file, ".json"));
        a.requestId = vm.parseJsonBytes32(j, ".message.requestId");
        a.chainId = vm.parseJsonUint(j, ".message.chainId");
        a.questionHash = vm.parseJsonBytes32(j, ".message.questionHash");
        a.answerType = _code(vm.parseJsonString(j, ".message.answerType"));
        a.answer = vm.parseJsonBytes(j, ".message.answer");
        a.figure = vm.parseUint(vm.parseJsonString(j, ".message.figure"));
        a.fromBlock = uint64(vm.parseJsonUint(j, ".message.fromBlock"));
        a.toBlock = uint64(vm.parseJsonUint(j, ".message.toBlock"));
        a.blockHash = vm.parseJsonBytes32(j, ".message.blockHash");
        a.panelJobId = vm.parseJsonBytes32(j, ".message.panelJobId");
        a.panelSize = uint16(vm.parseJsonUint(j, ".message.panelSize"));
        a.quorum = uint16(vm.parseJsonUint(j, ".message.quorum"));
        a.agreed = uint16(vm.parseJsonUint(j, ".message.agreed"));
        a.issuedAt = uint64(vm.parseJsonUint(j, ".message.issuedAt"));
        a.expiresAt = uint64(vm.parseJsonUint(j, ".message.expiresAt"));
        sig = vm.parseJsonBytes(j, ".signature");
        consumer = vm.parseJsonAddress(j, ".domain.verifyingContract");
        chainId = vm.parseJsonUint(j, ".domain.chainId");
        assertEq(vm.parseJsonAddress(j, ".signer"), ATTESTER);
        assertEq(vm.parseJsonString(j, ".domain.name"), "IdentityMD Oracle");
        assertEq(vm.parseJsonString(j, ".domain.version"), "2");
    }

    function _registryAt(address where) internal returns (Registry r) {
        MockIMD imdMock = new MockIMD();
        deployCodeTo(
            "Registry.sol:Registry",
            abi.encode(
                address(new MockCurator()),
                address(imdMock),
                address(new MockIntake(address(imdMock))),
                ATTESTER,
                address(renderer),
                address(composer),
                address(new MockBurnExecutor())
            ),
            where
        );
        r = Registry(where);
    }

    function test_allFiveRecoverTheAttesterUnderTheirOwnDomainOnly() public {
        for (uint256 i; i < 5; ++i) {
            (OracleAttestation memory a, bytes memory sig, address consumer, uint256 chainId) = _load(FILES[i]);
            assertEq(chainId, 1);
            address where = consumer == address(0) ? address(0) : consumer;
            // the registry cannot sit at the zero address; its digest at address(0) is reproduced by hand
            bytes32 digest;
            if (where == address(0)) {
                digest = _digest(a, address(0));
            } else {
                Registry r = _registryAt(where);
                digest = r.attestationDigest(a);
                assertEq(digest, _digest(a, where), "hand digest equals the registry's");
            }
            (address signer, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, sig);
            assertEq(uint8(err), 0, FILES[i]);
            assertEq(signer, ATTESTER, FILES[i]);
            // another consumer: never the attester
            (address other,,) = ECDSA.tryRecover(_digest(a, address(0xD00D)), sig);
            assertTrue(other != ATTESTER, "wrong verifyingContract");
            // another chain
            vm.chainId(4663);
            (address otherChain,,) = ECDSA.tryRecover(_digest(a, where), sig);
            vm.chainId(1);
            assertTrue(otherChain != ATTESTER, "wrong chain");
        }
    }

    function test_loaderRejectsUnknownAnswerTypeNames() public {
        vm.expectRevert(bytes("unknown answerType name"));
        this.codeOf("int256");
    }

    function codeOf(string memory name) external pure returns (uint8) {
        return _code(name);
    }

    function _digest(OracleAttestation memory a, address consumer) internal view returns (bytes32) {
        bytes32 ds = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("IdentityMD Oracle"),
                keccak256("2"),
                block.chainid,
                consumer
            )
        );
        bytes32 th = keccak256(
            "OracleAttestation(bytes32 requestId,uint256 chainId,bytes32 questionHash,uint8 answerType,bytes answer,uint256 figure,uint64 fromBlock,uint64 toBlock,bytes32 blockHash,bytes32 panelJobId,uint16 panelSize,uint16 quorum,uint16 agreed,uint64 issuedAt,uint64 expiresAt)"
        );
        bytes32 sh = keccak256(
            bytes.concat(
                abi.encode(
                    th, a.requestId, a.chainId, a.questionHash, a.answerType, keccak256(a.answer), a.figure, a.fromBlock
                ),
                abi.encode(
                    a.toBlock, a.blockHash, a.panelJobId, a.panelSize, a.quorum, a.agreed, a.issuedAt, a.expiresAt
                )
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", ds, sh));
    }

    /// @notice The protocol's conformance vector (oracle-consumer skill): the registry's digest at the
    ///         vector consumer on Sepolia equals the protocol's, and the callback selector is canonical.
    function test_protocolVectorDigestAndSelector() public {
        vm.chainId(11155111);
        Registry r = _registryAt(0x0000000000000000000000000000000000002748);
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = bytes32(uint256(1));
        OracleAttestation memory a = OracleAttestation({
            requestId: 0x0000000000004000800000000000000100000000000000000000000000000000,
            chainId: 1,
            questionHash: 0x2117f4362ebfa37aa8a8c0fed548604fe09ac46faf8ae7559cd64780f26a46fb,
            answerType: 5,
            answer: abi.encode(ids),
            figure: 12345,
            fromBlock: 100,
            toBlock: 200,
            blockHash: bytes32(uint256(7)),
            panelJobId: 0x0000000000004000800000000000000200000000000000000000000000000000,
            panelSize: 5,
            quorum: 4,
            agreed: 5,
            issuedAt: 1800000000,
            expiresAt: 1800003600
        });
        assertEq(r.attestationDigest(a), 0x95fefa8b7c529852f4e2b6aec888930eb2bf5078e6443a85808e36df19e1325c);
        (address signer,,) = ECDSA.tryRecover(
            r.attestationDigest(a),
            hex"a26b14918607eb565af126beb54d3c5d19e923c41506def500b3521a4f9aa6d603ab44fd22f15dd2191732961a7131e4641244add8b0f09f20e6ae64381be8481b"
        );
        assertEq(signer, 0x70997970C51812dc3A010C7d01b50e0d17dc79C8);
        assertEq(
            r.onResult.selector,
            bytes4(
                keccak256(
                    "onResult(bytes32,(bytes32,uint256,bytes32,uint8,bytes,uint256,uint64,uint64,bytes32,bytes32,uint16,uint16,uint16,uint64,uint64),bytes)"
                )
            )
        );
        assertEq(r.onFailure.selector, bytes4(keccak256("onFailure(bytes32,uint8,bytes32,uint16,uint16,bytes)")));
        vm.chainId(1);
    }
}
