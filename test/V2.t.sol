// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {MockBurnExecutor} from "./mocks/MockBurnExecutor.sol";

import {Base} from "./Base.t.sol";
import {Registry} from "../src/Registry.sol";
import {Composer} from "../src/Composer.sol";
import {OracleAttestation} from "../src/interfaces/IOracleConsumer.sol";
import {Spec} from "../src/Types.sol";

/// @notice The docs/V2.md items, one test each (test/NOTES.md maps the items).
contract V2Test is Base {
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public override {
        super.setUp();
        curator.set(alice, 1, true, 1, 1, 1);
    }

    function test_item2_zeroPriceReverts() public {
        imd.mint(address(registry), 10 ether);
        intake.setPrice(0);
        uint16[] memory ids = new uint16[](1);
        ids[0] = 701;
        fund(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(Registry.ZeroPrice.selector);
        registry.upgrade(ids, PRICE);
    }

    // item 5: abandon after 31 days, by the payer for a shared fact
    function test_item5_abandonSharedFactByAnyoneAfter31Days() public {
        fund(bob, PRICE);
        vm.prank(bob);
        registry.requestSharedFact(1201, PRICE);
        bytes32 shared = intake.lastId();
        bytes32 personal = ask(alice, 701);
        vm.warp(T0 + 15 days);
        vm.prank(alice);
        vm.expectRevert(Registry.TooEarly.selector);
        registry.abandon(shared);
        vm.warp(T0 + 32 days);
        vm.prank(alice);
        registry.abandon(shared);
        assertEq(registry.sharedPending(1201), bytes32(0));
        vm.prank(alice);
        registry.abandon(personal);
        assertEq(registry.pendingOf(alice, 701), bytes32(0));
    }

    // item 8 is not changed (see NOTES); item 9: expectedId
    function test_item9_expectedIdRefusesAFrontRun() public {
        Spec memory s = t1Spec(CURATOR_ADDR, "First");
        fund(alice, 3 * registry.SPEC_FEE());
        vm.prank(alice);
        assertEq(registry.registerSpec(s, 10001), 10001);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Registry.UnexpectedSpecId.selector, 10001, 10002));
        registry.registerSpec(s, 10001);
        vm.prank(alice);
        assertEq(registry.registerSpec(s, 0), 10002, "0 always registers");
    }

    // items 12, 13, 14: totalSupply; direct traits frozen at mint; the holder has no power
    function test_item13_directTraitsFrozenAtMintAndTransfersChangeNothing() public {
        curator.set(alice, 0, true, 10, 800 ether, 10_000);
        idmd.setBalance(alice, 1);
        uint256 id = mint(alice);
        assertEq(registry.totalSupply(), 1);
        assertFalse(registry.hasTrait(alice, 601));
        assertTrue(registry.hasTrait(alice, 202));
        curator.set(alice, 5, true, 0, 0, 0);
        idmd.setBalance(alice, 0);
        assertFalse(registry.hasTrait(alice, 601), "operator evidence requires an attestation");
        assertTrue(registry.hasTrait(alice, 202), "frozen");
        string memory before = registry.tokenURI(id);
        vm.prank(alice);
        registry.transferFrom(alice, bob, id);
        assertEq(registry.claimantOf(id), alice);
        assertEq(registry.tokenOf(alice), id);
        assertEq(registry.tokenURI(id), before, "a sale changes nothing");
        // the minter still upgrades its card; the buyer collects its own facts without a card
        bytes32 rid = ask(alice, 701);
        assertTrue(deliver(rid, attestationFor(rid, word(1))));
        assertTrue(registry.hasTrait(alice, 701));
        idmd.setBalance(bob, 1);
        assertFalse(registry.hasTrait(bob, 601), "no card, no snapshot");
        bytes32 rb = ask(bob, 801);
        assertTrue(deliver(rb, attestationFor(rb, word(1))));
        assertTrue(registry.hasTrait(bob, 801));
        uint256 bid = mint(bob);
        assertEq(registry.totalSupply(), 2);
        assertFalse(registry.hasTrait(bob, 601), "mint never grants an operator fact");
        assertEq(registry.frozenDirect(id) & (1 << 20), 0);
        assertTrue(bid != id);
    }

    // item 15: kind 3 asks 11 / 7
    function test_item15_kind3Panel() public {
        fund(bob, PRICE);
        vm.prank(bob);
        registry.requestSharedFact(1201, PRICE);
        bytes32 rid = intake.lastId();
        assertEq(vm.parseJsonUint(string(intake.bodyOf(rid)), ".panelSize"), 11);
        OracleAttestation memory a = attestationFor(rid, abi.encode(new address[](1)));
        a.panelSize = 5;
        a.quorum = 3;
        a.agreed = 3;
        vm.expectEmit(false, false, false, true, address(registry));
        emit Registry.Missed(rid, 1201, 5);
        assertTrue(deliver(rid, a));
    }

    // item 16: the finality margin
    function test_item16_finalityMargin() public {
        Spec memory s = t1Spec(CURATOR_ADDR, "Recent");
        s.toBlock = uint64(block.number - 1);
        s.fromBlock = s.toBlock - 7199;
        fund(alice, 2 * registry.SPEC_FEE());
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Composer.BadSpec.selector, "window"));
        registry.registerSpec(s, 0);
        s.toBlock = uint64(block.number - 64);
        s.fromBlock = s.toBlock - 7199;
        vm.prank(alice);
        assertEq(registry.registerSpec(s, 0), 10001);
    }

    // item 21: the constructor checks decimals and helper code
    function test_item21_constructorChecks() public {
        vm.mockCall(address(imd), abi.encodeWithSignature("decimals()"), abi.encode(uint8(6)));
        vm.expectRevert("IMD decimals");
        new Registry(
            CURATOR_ADDR,
            address(imd),
            address(intake),
            attester,
            address(renderer),
            address(composer),
            address(executor)
        );
        vm.clearMockedCalls();
        vm.expectRevert(Registry.DependencyHasNoCode.selector);
        new Registry(
            CURATOR_ADDR, address(imd), address(intake), attester, address(0xBEEF), address(composer), address(executor)
        );
    }
}
