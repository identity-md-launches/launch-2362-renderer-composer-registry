// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Base} from "./Base.t.sol";
import {Registry} from "../src/Registry.sol";
import {OracleAttestation} from "../src/interfaces/IOracleConsumer.sol";

/// @notice Stateful invariants 1, 2 and 9: the registry's IMD balance never decreases except through a
///         survive transfers. Handlers guard expected reverts (`fail_on_revert = true`).
contract Handler is Base {
    address[] internal actors;
    mapping(address => bytes32) public verifiedRid;

    constructor() {
        setUp();
        for (uint160 i = 1; i <= 4; ++i) {
            address a = address(0x1000 + i);
            actors.push(a);
            curator.set(a, i % 2, true, 1, 1, 1);
        }
        idmd.setOwner(1, actors[0]);
        idmd.setOwner(2, actors[1]);
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function mintCard(uint256 seed) external {
        address a = _actor(seed);
        if (registry.tokenOf(a) != 0) return;
        mint(a);
    }

    function transfer(uint256 seed, uint256 to) external {
        address a = _actor(seed);
        uint256 id = registry.tokenOf(a);
        if (id == 0 || registry.ownerOf(id) != a) return;
        vm.prank(a);
        registry.transferFrom(a, _actor(to), id);
    }

    function upgradeAndDeliver(uint256 seed, uint8 which) external {
        address a = _actor(seed);
        uint16 traitId = which % 2 == 0 ? 701 : 801;
        if (registry.pendingOf(a, traitId) != 0) return;
        (bytes32 rid,,,) = registry.verified(a, traitId);
        if (rid != 0) return;
        bytes32 id = ask(a, traitId);
        OracleAttestation memory at = attestationFor(id, word(1));
        deliver(id, at);
        verifiedRid[a] = id;
    }

    function actorAt(uint256 i) external view returns (address) {
        return actors[i];
    }

    function theRegistry() external view returns (Registry) {
        return registry;
    }
}

contract InvariantsTest is Test {
    function invariant_feesLeaveTheRegistry() public view {
        assertEq(registry.imd().balanceOf(address(registry)), 0);
    }
    Handler internal h;
    Registry internal registry;

    function setUp() public {
        h = new Handler();
        registry = h.theRegistry();
        targetContract(address(h));
        bytes4[] memory sel = new bytes4[](3);
        sel[0] = Handler.mintCard.selector;
        sel[1] = Handler.transfer.selector;
        sel[2] = Handler.upgradeAndDeliver.selector;
        targetSelector(FuzzSelector({addr: address(h), selectors: sel}));
    }

    function invariant_oneCardPerClaimantWithImmutableClaimant() public view {
        for (uint256 i; i < 4; ++i) {
            address a = h.actorAt(i);
            uint256 id = registry.tokenOf(a);
            if (id != 0) assertEq(registry.claimantOf(id), a);
            bytes32 rid = h.verifiedRid(a);
            if (rid != 0) {
                (bytes32 r,,,) = registry.verified(a, 701);
                (bytes32 r2,,,) = registry.verified(a, 801);
                assertTrue(r == rid || r2 == rid, "verified entry survives transfers");
            }
        }
    }
}
