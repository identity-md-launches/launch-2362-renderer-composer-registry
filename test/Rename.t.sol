// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Base} from "./Base.t.sol";
import {Registry} from "../src/Registry.sol";
import {Composer} from "../src/Composer.sol";
import {Renderer} from "../src/Renderer.sol";
import {Spec} from "../src/Types.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";

/// @notice The rename of 2026-10-16 (CATALOG.md section 7): collection strings, the name table, the catalog
///         spec names, the metadata family labels, the Composer size budget, and the `upgrade` error for 1201.
contract RenameTest is Base {
    address internal alice = address(0xA11CE);

    function test_collectionNameAndSymbol() public view {
        assertEq(registry.name(), "Sworn");
        assertEq(registry.symbol(), "SWORN");
    }

    /// @dev Every catalog id against the final name table; 1105 keeps its working name.
    function test_nameTableIsTheFinalTable() public view {
        uint16[25] memory ids = [
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
        string[25] memory names = [
            "Spawned",
            "Zero-Shot, hour <= 1",
            "Zero-Shot, hour 0",
            "Hopper >= 3",
            "Hopper >= 5",
            "Hopper >= 10",
            "Bullfrog >= 1 ETH",
            "Bullfrog >= 10 ETH",
            "Bullfrog >= 100 ETH",
            "Bullfrog >= 800 ETH",
            "Benchmarked >= 1000",
            "Benchmarked >= 3162",
            "Benchmarked >= 10000",
            "Swarmed",
            "Uptime",
            "Holdout",
            "Final Token",
            "Hotfix",
            "PID #1",
            "PID #1000",
            "PID #10000",
            "PID #19522",
            "First thousand",
            "Top Weights",
            "Pretrained"
        ];
        for (uint256 i; i < 25; ++i) {
            assertEq(registry.traitName(ids[i]), names[i]);
            assertEq(renderer.traitName(ids[i]), names[i]);
        }
    }

    /// @dev The catalog specs carry the same final names as the table (the renderer prints `spec.name`).
    function test_catalogSpecNamesMatchTheTable() public view {
        uint16[11] memory ids = [701, 801, 901, 1001, 1101, 1102, 1103, 1104, 1105, 1201, 1301];
        for (uint256 i; i < 11; ++i) {
            Spec memory s = registry.specOf(ids[i]);
            assertEq(s.name, registry.traitName(ids[i]));
            // the rename touched no rule: ids, kinds, windows and thresholds as frozen
            assertEq(s.fromBlock, ids[i] == 701 ? B_H24 : B_DEPLOY);
            assertEq(s.toBlock, ids[i] == 1105 ? B_FIRST1000 : ids[i] == 1301 ? B_DEPLOY : B_END);
            assertEq(s.threshold, ids[i] == 1201 ? 32 : ids[i] == 1301 ? 20 : 1);
        }
    }

    function test_noWorkingNameSurvivesInTheNameTable() public {
        uint16[25] memory ids = [
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
        string[12] memory old = [
            "Contributor",
            "Early bird",
            "Climber",
            "Capital",
            "Scoreboard",
            "Operator",
            "Still here",
            "Last stand",
            "The last one in",
            "Hour savior",
            "Ordinal",
            "Top 32"
        ];
        for (uint256 i; i < 25; ++i) {
            string memory n = registry.traitName(ids[i]);
            for (uint256 j; j < 12; ++j) {
                assertFalse(vm.contains(n, old[j]), string.concat("working name survives: ", n));
            }
            assertFalse(vm.contains(n, "Not born yesterday"));
        }
    }

    function test_unknownIdHasNoName() public {
        vm.expectRevert(abi.encodeWithSelector(Renderer.UnknownTrait.selector, 102));
        renderer.traitName(102);
        vm.expectRevert(abi.encodeWithSelector(Registry.NotAnOracleTrait.selector, 10001));
        registry.traitName(10001);
    }

    /// @dev The metadata of a card: `Sworn #<id>`, the thirteen family `trait_type`s in catalog order.
    function test_metadataCarriesTheFinalFamilyNames() public {
        uint256 tokenId = mint(alice);
        string memory uri = registry.tokenURI(tokenId);
        string memory prefix = "data:application/json;base64,";
        bytes memory u = bytes(uri);
        bytes memory payload = new bytes(u.length - bytes(prefix).length);
        for (uint256 i; i < payload.length; ++i) {
            payload[i] = u[i + bytes(prefix).length];
        }
        string memory metadata = string(Base64.decode(string(payload)));
        assertEq(vm.parseJsonString(metadata, ".name"), "Sworn #1");
        assertTrue(vm.contains(vm.parseJsonString(metadata, ".description"), "Sworn is an ownerless onchain registry"));
        string[13] memory families = [
            "Spawned",
            "Zero-Shot",
            "Hopper",
            "Bullfrog",
            "Benchmarked",
            "Swarmed",
            "Uptime",
            "Holdout",
            "Final Token",
            "Hotfix",
            "PID",
            "Top Weights",
            "Pretrained"
        ];
        assertEq(vm.parseJsonString(metadata, ".attributes[0].trait_type"), "Claimant");
        for (uint256 i; i < 13; ++i) {
            string memory key = string.concat(".attributes[", vm.toString(i + 1), "].trait_type");
            assertEq(vm.parseJsonString(metadata, key), families[i]);
        }
        assertEq(vm.parseJsonString(metadata, ".attributes[14].trait_type"), "community_count");
        // the hive card prints no text at all: no token id, no family label; both live in the JSON
        string memory image = vm.parseJsonString(metadata, ".image");
        assertFalse(vm.contains(image, "%3Ctext"));
        assertTrue(vm.contains(image, "'/%3E%3C/svg%3E"));
        assertFalse(vm.contains(image, "chaintraits"));
        assertFalse(vm.contains(image, "Pretrained"));
    }

    /// @dev Documentation fix 3: 1201 is an oracle trait, but a shared fact; `upgrade` says so, like a T3 spec.
    function test_upgradeRefusesTopWeightsAsASharedFact() public {
        fund(alice, PRICE);
        uint16[] memory ids = new uint16[](1);
        ids[0] = 1201;
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Registry.NotASharedFact.selector, 1201));
        registry.upgrade(ids, PRICE);
        // a direct-read id and an unregistered id keep NotAnOracleTrait
        ids[0] = 101;
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Registry.NotAnOracleTrait.selector, 101));
        registry.upgrade(ids, PRICE);
        ids[0] = 10001;
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Registry.NotAnOracleTrait.selector, 10001));
        registry.upgrade(ids, PRICE);
        // the shared-fact path still accepts 1201
        fund(alice, PRICE);
        vm.prank(alice);
        registry.requestSharedFact(1201, PRICE);
        assertEq(imd.balanceOf(address(registry)), 0);
    }

    /// @dev Every launched runtime stays under EIP-170 (sizes are recorded in test/NOTES.md).
    function test_composerStaysUnderTheSizeLimitWithHeadroom() public {
        assertLe(address(composer).code.length, 24_576, "Composer under EIP-170");
        assertLe(address(registry).code.length, 24_576, "Registry under EIP-170");
        assertLe(address(new Renderer()).code.length, 24_576, "Renderer under EIP-170");
    }
}
