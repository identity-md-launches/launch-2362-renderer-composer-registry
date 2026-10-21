// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Base} from "./Base.t.sol";
import {Composer} from "src/Composer.sol";
import {Renderer} from "src/Renderer.sol";
import {Spec, Card} from "src/Types.sol";

/// @notice An untrusted rendering source with independently encoded, deliberately corruptible metadata.
contract MetadataReplySource {
    bytes internal reply;

    function setReply(bytes memory data) external {
        reply = data;
    }

    function claimantOf(uint256) external view returns (address) {
        return address(this);
    }

    function traitsOf(address) external pure returns (uint16[] memory ids) {
        ids = new uint16[](1);
        ids[0] = 601;
    }

    function verifiedSpecsOf(address) external pure returns (uint16[] memory ids) {
        return new uint16[](0);
    }

    function verified(address, uint16) external pure returns (bytes32, bytes32, uint64, uint64) {
        return (keccak256("metadata intake receipt"), keccak256("metadata oracle receipt"), 25_090_085, 26_200_000);
    }

    fallback() external {
        bytes memory data = reply;
        assembly ("memory-safe") { return(add(data, 32), mload(data)) }
    }
}

contract WorkflowInputPropertiesTest is Base {
    function _identifier(bytes32 seed, uint256 size) internal pure returns (string memory) {
        bytes memory chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_";
        bytes memory name = new bytes(size);
        name[0] = "w";
        for (uint256 i = 1; i < size; ++i) {
            name[i] = chars[uint8(seed[i]) % chars.length];
        }
        return string(name);
    }

    function _eventSpec(bytes32 seed, uint8 length, uint8 kind, bool indexedField)
        internal
        pure
        returns (Spec memory s)
    {
        s = t1Spec(CURATOR_ADDR, "Generated field");
        s.kind = uint8(bound(kind, 1, 3));
        s.arg = _identifier(seed, bound(length, 1, 32));
        s.item = string.concat(
            "event Evidence(uint256 noise, address ",
            indexedField ? "indexed " : "",
            s.arg,
            ", uint256 indexed batch, uint256 amount)"
        );
        if (s.kind >= 2) s.sumArg = "amount";
        if (s.kind <= 2) {
            s.fixedArg = "batch";
            s.fixedVal = 42;
        }
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_referencedFieldMustExistAsAnIndexedAddress(bytes32 seed, uint8 length, uint8 kind) public {
        Spec memory s = _eventSpec(seed, length, kind, true);
        composer.validateSpec(s, 0);
        // A substring or a similarly named parameter is not the declared field.
        string memory originalArg = s.arg;
        s.arg = string.concat("z", bytes(originalArg).length == 32 ? "missing" : originalArg);
        vm.expectRevert(abi.encodeWithSelector(Composer.BadSpec.selector, "arg"));
        composer.validateSpec(s, type(uint256).max);
        s = _eventSpec(seed, length, kind, false);
        vm.expectRevert(abi.encodeWithSelector(Composer.BadSpec.selector, "arg"));
        composer.validateSpec(s, type(uint256).max);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_validFieldNamesComposeAndConsumerDoesNotChangeTheQuestion(bytes32 seed, uint8 length, uint8 kind)
        public
        view
    {
        Spec memory s = _eventSpec(seed, length, kind, true);
        composer.validateSpec(s, 0);
        (bytes memory body, bytes32 question) = composer.compose(10001, s, C1A1, address(registry), CURATOR_ADDR);
        (bytes memory other, bytes32 sameQuestion) = composer.compose(10001, s, C1A1, address(composer), CURATOR_ADDR);
        assertEq(question, sameQuestion, "transport consumer is outside the canonical question");
        assertTrue(keccak256(body) != keccak256(other), "consumer domain remains in each request body");
        assertEq(vm.parseJsonAddress(string(body), ".consumer.verifyingContract"), address(registry));
        assertEq(vm.parseJsonAddress(string(other), ".consumer.verifyingContract"), address(composer));
        assertEq(vm.parseJsonString(string(body), ".question"), vm.parseJsonString(string(other), ".question"));
        assertLe(body.length, 16_384);
        assertLe(bytes(vm.parseJsonString(string(body), ".question")).length, 1000);
        string[] memory keys = vm.parseJsonKeys(string(body), ".definitions");
        for (uint256 i; i < keys.length; ++i) {
            assertLe(bytes(vm.parseJsonString(string(body), string.concat(".definitions.", keys[i]))).length, 512);
        }
        if (s.kind == 3) {
            assertEq(vm.parseJsonUint(string(body), ".head"), s.threshold);
            assertEq(vm.parseJsonUint(string(body), ".panelSize"), 11);
            assertEq(vm.parseJsonUint(string(body), ".quorum"), 7);
        } else {
            assertEq(vm.parseJsonUint(string(body), ".panelSize"), 5);
            assertEq(vm.parseJsonUint(string(body), ".quorum"), 3);
        }
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_extraBytesOutsideAValidSignatureAlwaysFail(uint8 extra, bool prefix, bool functionItem) public {
        Spec memory s = t1Spec(CURATOR_ADDR, "Exact grammar");
        if (functionItem) {
            s.kind = 4;
            s.arg = "";
            s.op = 1;
            s.item = "function balanceOf(address) view returns (uint256)";
        }
        composer.validateSpec(s, 0);
        s.item =
            string(prefix ? bytes.concat(bytes1(extra), bytes(s.item)) : bytes.concat(bytes(s.item), bytes1(extra)));
        vm.expectRevert(abi.encodeWithSelector(Composer.BadSpec.selector, "item"));
        composer.validateSpec(s, 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_mainnetFinalityUsesTheActualHead(uint32 height, uint8 depth, uint256 suppliedHeight) public {
        uint256 head = bound(height, 26_200_000, 40_000_000);
        uint256 age = bound(depth, 0, 128);
        vm.roll(head);
        Spec memory s = t1Spec(CURATOR_ADDR, "Finality boundary");
        s.toBlock = uint64(head - age);
        s.fromBlock = s.toBlock - 7199;
        if (age < 64) vm.expectRevert(abi.encodeWithSelector(Composer.BadSpec.selector, "window"));
        composer.validateSpec(s, suppliedHeight);
    }

    function _validReply() internal pure returns (bytes memory) {
        Spec memory s;
        s.kind = 6;
        s.target = CURATOR_ADDR;
        s.fromBlock = 25_090_085;
        s.toBlock = 26_200_000;
        s.threshold = 3;
        s.name = "Operator's record";
        return abi.encode(s);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_rendererRejectsOutOfBoundsMetadataOffsetsWithoutPanic(uint256 value, uint8 field) public {
        MetadataReplySource source = new MetadataReplySource();
        bytes memory reply = _validReply();
        source.setReply(reply);
        Card memory valid = renderer.cardOfOn(address(source), 1);
        assertEq(valid.oracle.length, 1);
        assertEq(valid.oracle[0].name, "Operator's record");
        assertEq(valid.oracle[0].toBlock, 26_200_000);

        uint256 position;
        uint256 corruptWord;
        field = uint8(bound(field, 0, 3));
        if (field == 0) {
            position = 0;
            corruptWord = bound(value, reply.length - 12 * 32 + 1, type(uint256).max);
        } else if (field == 1) {
            position = 32 + 11 * 32;
            corruptWord = bound(value, reply.length - 64 + 1, type(uint256).max);
        } else if (field == 2) {
            position = 32 + 11 * 32;
            corruptWord = bound(value, 0, 12 * 32 - 1);
        } else {
            uint256 nameOffset;
            assembly ("memory-safe") { nameOffset := mload(add(reply, 416)) }
            position = 32 + nameOffset;
            corruptWord = bound(value, 33, type(uint256).max);
        }
        assembly ("memory-safe") { mstore(add(add(reply, 32), position), corruptWord) }
        source.setReply(reply);
        (bool ok, bytes memory reason) =
            address(renderer).staticcall{gas: 5_000_000}(abi.encodeCall(Renderer.tokenURIOf, (address(source), 1)));
        assertFalse(ok);
        assertEq(reason, abi.encodeWithSelector(Renderer.UnknownTrait.selector, 601), "bounded error, not panic or OOG");
    }
}
