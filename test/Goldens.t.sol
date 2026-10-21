// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Base} from "./Base.t.sol";
import {Card, OracleMeta, Spec} from "../src/Types.sol";
import {Renderer} from "../src/Renderer.sol";
import {RendererHarness} from "./mocks/RendererHarness.sol";
import {TemplateData} from "../src/TemplateData.sol";
import {OracleAttestation} from "../src/interfaces/IOracleConsumer.sol";

/// @notice Invariant 8: `tokenURI` bytes equal the generator's goldens (`tools/gen_template.py`),
///         the template artifacts match the compiled constants, and hostile spec strings are escaped.
contract GoldensTest is Base {
    bytes32 internal constant REQUEST_1 = 0x1111111111111111111111111111111111111111111111111111111111111111;
    bytes32 internal constant REQUEST_2 = 0x2222222222222222222222222222222222222222222222222222222222222222;
    bytes32 internal constant ORACLE_1 = 0x0123456789abcdef0123456789abcdef00000000000000000000000000000000;
    bytes32 internal constant ORACLE_2 = 0xfedcba9876543210fedcba987654321000000000000000000000000000000000;

    function test_templateArtifactsMatchTheCompiledConstants() public view {
        bytes memory blob = vm.parseBytes(vm.trim(vm.readFile("template/blob.hex")));
        assertEq(TemplateData.TEMPLATE, blob, "blob.hex");
        string[] memory parts = vm.split(vm.trim(vm.readFile("template/offsets.txt")), ",");
        assertEq(parts.length, 44, "22 slices");
        bytes memory offs = vm.parseBytes(string(TemplateData.OFFSETS));
        assertEq(offs.length, 88);
        uint256 cursor;
        for (uint256 i; i < 44; ++i) {
            uint256 v = vm.parseUint(parts[i]);
            assertEq((uint256(uint8(offs[2 * i])) << 8) | uint256(uint8(offs[2 * i + 1])), v, "offset");
            if (i % 2 == 0) assertEq(v, cursor, "contiguous");
            else cursor += v;
        }
        assertEq(cursor, blob.length, "slices tile the blob");
    }

    function test_goldenSyntheticDirect() public {
        curator.set(C1A1, 0, true, 5, 1 ether, 1000);
        uint256 id = mint(C1A1);
        assertEq(id, 1);
        _assertGolden("synthetic_direct", registry.tokenURI(1), renderer.cardOfOn(address(registry), 1));
    }

    function test_goldenSyntheticOracle() public {
        mint(address(0xF1));
        idmd.setBalance(AC1A1, 1);
        uint256 id = mint(AC1A1);
        assertEq(id, 2);
        intake.forceNextId(REQUEST_1);
        bytes32 rid = ask(AC1A1, 801);
        assertEq(rid, REQUEST_1);
        OracleAttestation memory a = attestationFor(rid, word(1));
        a.requestId = ORACLE_1;
        assertTrue(deliver(rid, a));
        uint16 specId = register(address(0xBEEF), t1Spec(REGISTRY_ADDR, "Received a token"));
        assertEq(specId, 10001);
        intake.forceNextId(REQUEST_2);
        rid = ask(AC1A1, specId);
        a = attestationFor(rid, word(1));
        a.requestId = ORACLE_2;
        assertTrue(deliver(rid, a));
        intake.forceNextId(bytes32(uint256(0x3333333333333333333333333333333333333333333333333333333333333333)));
        rid = ask(AC1A1, 601);
        a = attestationFor(rid, word(1));
        a.requestId = 0x4444444444444444444444444444444400000000000000000000000000000000;
        assertTrue(deliver(rid, a));
        _assertGolden("synthetic_oracle", registry.tokenURI(2), renderer.cardOfOn(address(registry), 2));
    }

    function test_goldenSyntheticWidthThroughTheRenderer() public view {
        Card memory c = _widthCard();
        _assertGolden("synthetic_width", renderer.tokenURIOfCard(c), c);
    }

    function _widthCard() internal view returns (Card memory c) {
        c.tokenId = type(uint256).max;
        c.claimant = 0xffffFFFFFfffFFFFFFfFFFFfFFFFFFFFfFFFC1a1;
        uint16[13] memory top = [101, 202, 303, 404, 503, 601, 701, 801, 901, 1001, 1101, 1201, 1301];
        c.top = top;
        c.traits = new uint16[](25);
        uint16[25] memory all = [
            101,
            201,
            202,
            301,
            302,
            303,
            401,
            402,
            403,
            404,
            501,
            502,
            503,
            601,
            701,
            801,
            901,
            1001,
            1101,
            1102,
            1103,
            1104,
            1105,
            1201,
            1301
        ];
        for (uint256 i; i < 25; ++i) {
            c.traits[i] = all[i];
        }
        c.community = new uint16[](32);
        for (uint256 i; i < 32; ++i) {
            c.community[i] = uint16(10001 + i);
        }
        c.communityCount = 40;
        c.oracle = new OracleMeta[](32);
        Spec memory s;
        s.kind = 4;
        s.target = REGISTRY_ADDR;
        s.item = 'function f(address) view returns (uint256)"</text><script>&\x01\\';
        s.op = 1;
        s.threshold = 1000;
        s.fromBlock = B_DEPLOY;
        s.toBlock = B_END;
        s.name = 'a"b\\c<d>&e\'';
        for (uint256 i; i < 32; ++i) {
            c.oracle[i] =
                OracleMeta(uint16(10001 + i), s.kind, s.fromBlock, s.toBlock, s.target, REQUEST_1, ORACLE_1, s.name);
        }
    }

    // ------------------------------------------------------------------ the hive goldens (renderer only)

    function test_goldenSyntheticNewcomer() public view {
        uint16[13] memory top;
        top[0] = 101;
        uint16[] memory traits = new uint16[](1);
        traits[0] = 101;
        Card memory c = _card(3, address(uint160(0x3c1a1)), top, traits, 0, 0);
        _assertGolden("synthetic_newcomer", renderer.tokenURIOfCard(c), c);
    }

    function test_goldenSyntheticOutsider() public view {
        uint16[13] memory top;
        Card memory c = _card(4, address(uint160(0x4c1a1)), top, new uint16[](0), 5, 5);
        _assertGolden("synthetic_outsider", renderer.tokenURIOfCard(c), c);
    }

    function test_goldenSyntheticHoney() public view {
        Card memory c = _honeyCard();
        _assertGolden("synthetic_honey", renderer.tokenURIOfCard(c), c);
    }

    function _honeyCard() internal view returns (Card memory c) {
        uint16[13] memory top = [101, 201, 302, 403, 502, 601, 701, 801, 901, 1001, 1101, 1201, 1301];
        uint16[17] memory ids =
            [101, 201, 301, 302, 401, 402, 403, 501, 502, 601, 701, 801, 901, 1001, 1101, 1201, 1301];
        uint16[] memory traits = new uint16[](17);
        for (uint256 i; i < 17; ++i) {
            traits[i] = ids[i];
        }
        c = _card(5, address(uint160(0x5c1a1)), top, traits, 32, 39);
    }

    function test_goldenSyntheticCollector() public view {
        uint16[13] memory top;
        top[0] = 101;
        top[2] = 301;
        uint16[] memory traits = new uint16[](2);
        traits[0] = 101;
        traits[1] = 301;
        Card memory c = _card(6, address(uint160(0x6c1a1)), top, traits, 32, 70);
        _assertGolden("synthetic_collector", renderer.tokenURIOfCard(c), c);
    }

    function test_goldenSyntheticFullhouse() public view {
        Card memory c = _fullhouseCard();
        _assertGolden("synthetic_fullhouse", renderer.tokenURIOfCard(c), c);
    }

    function _fullhouseCard() internal view returns (Card memory c) {
        uint16[13] memory top = [101, 202, 303, 404, 503, 601, 701, 801, 901, 1001, 1101, 1201, 1301];
        c = _card(7, address(uint160(0x7c1a1)), top, _allCatalogIds(), 32, 5000);
    }

    // ------------------------------------------------------------------ step 5: gas, size, failure paths

    /// @dev Reports the tokenURI gas of the three heaviest goldens and bounds it well under a block, so a
    ///      marketplace eth_call (commonly capped at 30-50M gas) always succeeds.
    function test_reportTokenURIGas() public {
        Card memory w = _widthCard();
        Card memory f = _fullhouseCard();
        Card memory h = _honeyCard();
        uint256 g = gasleft();
        renderer.tokenURIOfCard(w);
        uint256 gw = g - gasleft();
        g = gasleft();
        renderer.tokenURIOfCard(f);
        uint256 gf = g - gasleft();
        g = gasleft();
        renderer.tokenURIOfCard(h);
        uint256 gh = g - gasleft();
        emit log_named_uint("tokenURI gas synthetic_width", gw);
        emit log_named_uint("tokenURI gas synthetic_fullhouse", gf);
        emit log_named_uint("tokenURI gas synthetic_honey", gh);
        assertLt(gw, 30_000_000);
        assertLt(gf, 30_000_000);
        assertLt(gh, 30_000_000);
    }

    /// @dev Reports the Renderer runtime size; it must stay under EIP-170 and be immutable-free and pure.
    function test_reportRendererRuntimeSize() public {
        Renderer fresh = new Renderer();
        uint256 size = address(fresh).code.length;
        emit log_named_uint("Renderer runtime bytes", size);
        assertLt(size, 24_576, "Renderer exceeds EIP-170");
        assertEq(address(fresh).code, address(new Renderer()).code, "constructor-free, identical runtime");
    }

    /// @dev Failure side of the overflow rule: at and below 39 there is no path, a single tokenURI at the
    ///      uint256 maximum count neither reverts nor overflows (count ** 8 is never evaluated from 8192).
    function test_imageOverflowPathAbsentAtOrBelow39AndNeverOverflows() public view {
        uint16[13] memory top;
        bytes memory none = renderer.imageOf(_card(1, C1A1, top, new uint16[](0), 0, 39));
        assertFalse(_contains(none, "%3Cpath%20d="), "no path at 39");
        bytes memory some = renderer.imageOf(_card(1, C1A1, top, new uint16[](0), 0, 40));
        assertTrue(_contains(some, "%3Cpath%20d="), "path at 40");
        bytes memory max = renderer.imageOf(_card(1, C1A1, top, new uint16[](0), 0, type(uint256).max));
        bytes memory at8192 = renderer.imageOf(_card(1, C1A1, top, new uint16[](0), 0, 8192));
        assertEq(max, at8192, "64 steps from 8192 up");
    }

    /// @dev XOR would give 40 ^ 8 = 32 (no path, bitlen < 41); exponentiation gives bitlen(40**8) - 41 = 2 steps,
    ///      so 40 and 41 must render a path while the XOR reading would underflow or render none.
    function test_imageStepsUseExponentiationNotXor() public view {
        uint16[13] memory top;
        bytes memory a = renderer.imageOf(_card(1, C1A1, top, new uint16[](0), 0, 40));
        bytes memory b = renderer.imageOf(_card(1, C1A1, top, new uint16[](0), 0, 53));
        assertTrue(_contains(a, "%3Cpath"), "path at 40");
        assertTrue(keccak256(a) != keccak256(b), "40 (2 steps) and 53 (5 steps) differ");
    }

    function _contains(bytes memory hay, bytes memory needle) internal pure returns (bool) {
        if (needle.length > hay.length) return false;
        for (uint256 i; i + needle.length <= hay.length; ++i) {
            bool ok = true;
            for (uint256 j; j < needle.length; ++j) {
                if (hay[i + j] != needle[j]) {
                    ok = false;
                    break;
                }
            }
            if (ok) return true;
        }
        return false;
    }

    // ------------------------------------------------------------------ the hive rules

    /// @dev The community path length table of tools/test_gen_template.py: steps for the counts, and the
    ///      number of segments the path has (one per whole corner passed, plus one to the end point).
    function test_imageCommunityPathFollowsTheStepTable() public view {
        uint256[12] memory counts = [uint256(32), 39, 40, 53, 70, 100, 200, 1000, 5000, 8191, 8192, 65535];
        uint256[12] memory segments = [uint256(0), 0, 1, 1, 1, 2, 2, 4, 6, 6, 6, 6];
        uint16[13] memory top;
        for (uint256 i; i < 12; ++i) {
            Card memory c = _card(1, C1A1, top, new uint16[](0), 0, counts[i]);
            string memory image = string(renderer.imageOf(c));
            string[] memory split = vm.split(image, "%3Cpath%20d='M");
            if (segments[i] == 0) {
                assertEq(split.length, 1, "no path up to 39 members");
                continue;
            }
            assertEq(split.length, 2, "one path");
            string memory d = vm.split(split[1], "'")[0];
            assertEq(vm.split(d, "L").length - 1, segments[i], "segments");
        }
        // 8192 and 64 steps close on the first corner: the last point equals the first
        Card memory full = _card(1, C1A1, top, new uint16[](0), 0, 8192);
        string memory dFull = vm.split(vm.split(string(renderer.imageOf(full)), "%3Cpath%20d='M")[1], "'")[0];
        string[] memory pts = vm.split(dFull, "L");
        assertEq(pts[0], pts[6], "closed");
        Card memory max = _card(1, C1A1, top, new uint16[](0), 0, type(uint256).max);
        assertEq(string(renderer.imageOf(max)), string(renderer.imageOf(full)), "capped at 64 steps");
    }

    function test_imageRareDotOnlyAtATopTierRareId() public view {
        uint16[25] memory all = _allCatalogIdsFixed();
        for (uint256 j; j < 25; ++j) {
            uint16 id = all[j];
            uint16[13] memory top;
            top[id / 100 - 1] = id;
            Card memory c = _card(1, C1A1, top, new uint16[](0), 0, 0);
            string memory image = string(renderer.imageOf(c));
            bool rare = id == 202 || id == 801 || id == 901 || id == 1001 || id == 1201 || (id >= 1101 && id <= 1104);
            assertEq(vm.split(image, "%3Ccircle%20").length - 1, rare ? 1 : 0, vm.toString(id));
            // a lit cell is outlined in its class colour; the twelve others are dark
            assertEq(vm.split(image, "stroke='%23151515'").length - 1, 12, "dark outlines");
            // a part-filled family carries exactly two clip paths; a full or single-tier one carries none
            uint256 n = id / 100 == 2 ? 2 : id / 100 == 3 ? 3 : id / 100 == 4 ? 4 : id / 100 == 5 ? 3 : 1;
            bool partFilled = id / 100 != 11 && id % 100 < n;
            assertEq(vm.split(image, "%3CclipPath%20id='").length - 1, partFilled ? 2 : 0, "clip paths");
        }
    }

    function test_imageRingsByCommunityCount() public view {
        uint16[13] memory top;
        top[5] = 601; // Swarmed sits in the centre slot, so its rings come first
        uint256[5] memory counts = [uint256(0), 1, 14, 27, 39];
        uint256[5] memory ringsInCentre = [uint256(0), 1, 2, 3, 3];
        uint256[5] memory ringsTotal = [uint256(0), 1, 14, 27, 39];
        for (uint256 i; i < 5; ++i) {
            Card memory c = _card(1, C1A1, top, new uint16[](0), 0, counts[i]);
            string memory image = string(renderer.imageOf(c));
            // the centre cell is lit: its zones carry fill-opacity, one per ring plus the cell
            assertEq(vm.split(image, "fill-opacity='").length - 1, ringsInCentre[i] + 1, "centre zones");
            // every other cell is empty: its rings are outlines of width 3 (the outer ring V is one more)
            assertEq(
                vm.split(image, "stroke-width='3'%20stroke-linejoin='round'/%3E").length - 1,
                ringsTotal[i] - ringsInCentre[i] + 1,
                "empty ring outlines"
            );
        }
        Card memory many = _card(1, C1A1, top, new uint16[](0), 0, 5000);
        Card memory thirtyNine = _card(1, C1A1, top, new uint16[](0), 0, 39);
        assertEq(
            vm.split(string(renderer.imageOf(many)), "fill-opacity='0.57'").length,
            vm.split(string(renderer.imageOf(thirtyNine)), "fill-opacity='0.57'").length,
            "rings saturate at 39"
        );
    }

    function test_imageIdsOutsideTheCatalogRenderWithoutReverting() public view {
        uint16[13] memory top = [uint16(199), 200, 399, 65535, 1, 602, 0, 0, 0, 0, 1199, 0, 0];
        Card memory c = _card(1, C1A1, top, new uint16[](0), 0, 0);
        bytes memory image = renderer.imageOf(c);
        assertGt(image.length, 0);
        assertEq(vm.split(string(image), "%3Ccircle%20").length - 1, 0, "nothing rare");
        // the level is clamped into the family's tier list: 199, 399, 65535, 602 and 1199 count as full
        // cells (one zone each), 200 and 1 as the first of several tiers (two clip paths and one zone each)
        assertEq(vm.split(string(image), "%3Cpolygon%20points='").length - 1, 13 + 5 + 2 * 3 + 1, "polygons");
        assertEq(vm.split(string(image), "%3CclipPath%20id='").length - 1, 4, "two part-filled cells");
    }

    function test_imageIsPureAndDeterministic() public {
        uint16[13] memory top = [101, 202, 303, 404, 503, 601, 701, 801, 901, 1001, 1101, 1201, 1301];
        Card memory c = _card(7, C1A1, top, _allCatalogIds(), 32, 5000);
        bytes memory first = renderer.imageOf(c);
        RendererHarness other = new RendererHarness();
        assertEq(other.imageOf(c), first);
        assertEq(keccak256(renderer.preimageOf(c)), keccak256(other.preimageOf(c)));
    }

    function _card(
        uint256 tokenId,
        address claimant,
        uint16[13] memory top,
        uint16[] memory traits,
        uint256 shownCommunity,
        uint256 communityCount
    ) internal view returns (Card memory c) {
        c.tokenId = tokenId;
        c.claimant = claimant;
        c.top = top;
        c.traits = traits;
        c.community = new uint16[](shownCommunity);
        c.oracle = new OracleMeta[](shownCommunity);
        for (uint256 i; i < shownCommunity; ++i) {
            uint16 id = uint16(10001 + i);
            c.community[i] = id;
            Spec memory s = t1Spec(REGISTRY_ADDR, string.concat("Community spec ", vm.toString(id)));
            c.oracle[i] = OracleMeta(id, s.kind, s.fromBlock, s.toBlock, s.target, REQUEST_1, ORACLE_1, s.name);
        }
        c.communityCount = communityCount;
    }

    function _allCatalogIdsFixed() internal pure returns (uint16[25] memory all) {
        all = [
            101,
            201,
            202,
            301,
            302,
            303,
            401,
            402,
            403,
            404,
            501,
            502,
            503,
            601,
            701,
            801,
            901,
            1001,
            1101,
            1102,
            1103,
            1104,
            1105,
            1201,
            1301
        ];
    }

    function _allCatalogIds() internal pure returns (uint16[] memory ids) {
        uint16[25] memory all = _allCatalogIdsFixed();
        ids = new uint16[](25);
        for (uint256 i; i < 25; ++i) {
            ids[i] = all[i];
        }
    }

    function test_escapeJsonNeutralisesMarkup() public view {
        assertEq(string(renderer.escape('a"b\\c<d>&e\x01')), 'a\\"b\\\\c\\u003cd\\u003e\\u0026e\\u0001');
        assertEq(string(renderer.escape("plain Name 1.0-x")), "plain Name 1.0-x");
    }

    function _assertGolden(string memory name_, string memory uri, Card memory c) internal view {
        string memory base = string.concat("test/fixtures/golden_", name_);
        assertEq(uri, vm.readFile(string.concat(base, "_uri.txt")), "uri");
        bytes memory preimage = renderer.preimageOf(c);
        assertEq(string(preimage), vm.readFile(string.concat(base, "_preimage.txt")), "preimage");
        string memory image = vm.parseJsonString(string(preimage), ".image");
        string memory encoded = vm.replace(image, "data:image/svg+xml,", "");
        assertEq(string(_pctDecode(bytes(encoded))), vm.readFile(string.concat(base, "_svg.txt")), "svg");
    }

    function _pctDecode(bytes memory input) internal pure returns (bytes memory out) {
        out = new bytes(input.length);
        uint256 o;
        uint256 i;
        while (i < input.length) {
            if (input[i] == "%") {
                out[o++] = bytes1(_nibble(input[i + 1]) * 16 + _nibble(input[i + 2]));
                i += 3;
            } else {
                out[o++] = input[i++];
            }
        }
        assembly {
            mstore(out, o)
        }
    }

    function _nibble(bytes1 c) internal pure returns (uint8) {
        uint8 b = uint8(c);
        if (b >= 48 && b <= 57) return b - 48;
        if (b >= 65 && b <= 70) return b - 55;
        return b - 87;
    }
}
