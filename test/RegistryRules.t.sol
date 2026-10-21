// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {MockBurnExecutor} from "./mocks/MockBurnExecutor.sol";

import {Base} from "./Base.t.sol";
import {Registry} from "../src/Registry.sol";
import {IIntake} from "../src/interfaces/IIntake.sol";
import {Spec} from "../src/Types.sol";
import {MockIMD} from "./mocks/Mocks.sol";

/// @dev This deliberately non-view implementation proves the constructor uses STATICCALL.
contract WritingPriceIntake {
    uint256 public reads;

    function priceOf(bytes32, address) external returns (uint256) {
        reads++;
        return 0.5 ether;
    }
}

contract RegistryRulesTest is Base {
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function _deploy(address asset, address intake_) internal returns (Registry) {
        return
            new Registry(
                CURATOR_ADDR, asset, intake_, attester, address(renderer), address(composer), address(executor)
            );
    }

    function _member(address wallet) internal {
        curator.set(wallet, 1, true, 1, 1, 1);
    }

    function _one(uint16 id) internal pure returns (uint16[] memory ids) {
        ids = new uint16[](1);
        ids[0] = id;
    }

    function test_constructorRejectsZeroIntakePrice() public {
        intake.setPrice(0);
        vm.expectRevert("Intake price");
        _deploy(address(imd), address(intake));
    }

    function test_constructorRejectsPartiallyCodedDependencyFloor() public {
        address bare = makeAddr("empty dependency");
        address[3] memory coded = [CURATOR_ADDR, address(imd), address(intake)];
        for (uint256 i; i < coded.length; ++i) {
            address[3] memory args = [bare, bare, bare];
            args[i] = coded[i];
            // With only IDMD coded the Curator call has no return data; otherwise IDMD fails first.
            vm.expectRevert();
            new Registry(args[0], args[1], args[2], attester, address(renderer), address(composer), address(executor));
        }
    }

    function test_constructorRejectsEachSingleMistypedDependency() public {
        address bare = makeAddr("mistyped dependency");
        for (uint256 i; i < 3; ++i) {
            address[3] memory args = [CURATOR_ADDR, address(imd), address(intake)];
            args[i] = bare;
            vm.expectRevert();
            new Registry(args[0], args[1], args[2], attester, address(renderer), address(composer), address(executor));
        }
    }

    function test_constructorRejectsWrongAsset() public {
        MockIMD wrongAsset = new MockIMD();
        vm.expectRevert("Intake price");
        _deploy(address(wrongAsset), address(intake));
    }

    function test_constructorRejectsUnavailableIntake() public {
        vm.mockCallRevert(
            address(intake), abi.encodeCall(IIntake.priceOf, (registry.ACTION(), address(imd))), "unavailable"
        );
        vm.expectRevert(bytes("unavailable"));
        _deploy(address(imd), address(intake));
        vm.clearMockedCalls();
        vm.expectRevert();
        _deploy(address(imd), makeAddr("no Intake code"));
    }

    function test_constructorPriceCheckIsPassiveAndAcceptsAnyNonzeroPrice() public {
        WritingPriceIntake writing = new WritingPriceIntake();
        vm.expectRevert();
        _deploy(address(imd), address(writing));
        assertEq(writing.reads(), 0);
        intake.setPrice(1);
        Registry r = _deploy(address(imd), address(intake));
        assertEq(address(r.intake()), address(intake));
        assertEq(imd.balanceOf(address(r)), 0);
        assertEq(intake.nonce(), 0, "deployment must not create a request");
    }

    function test_specAndFirstClaimCostSixPointNineIMD() public {
        assertEq(registry.SPEC_FEE(), 6.4 ether);
        fund(alice, 6.9 ether);
        vm.prank(alice);
        imd.approve(address(registry), 6.4 ether);
        Spec memory s = t1Spec(CURATOR_ADDR, "Community");
        vm.prank(alice);
        uint16 id = registry.registerSpec(s, 0);
        assertEq(imd.balanceOf(address(registry)), 0);
        assertEq(imd.balanceOf(alice), 0.5 ether);
        assertEq(imd.allowance(alice, address(registry)), 0);
        vm.prank(alice);
        imd.approve(address(registry), PRICE);
        vm.prank(alice);
        registry.upgrade(_one(id), PRICE);
        assertEq(imd.balanceOf(alice), 0);
        assertEq(imd.balanceOf(address(intake)), PRICE);
        assertEq(imd.balanceOf(address(registry)), 0, "fees leave the Registry");
        assertTrue(registry.pendingOf(alice, id) != 0);
    }

    function test_specRequiresFullFeeAndAllowance() public {
        fund(alice, 6.4 ether - 1);
        Spec memory s = t1Spec(CURATOR_ADDR, "Community");
        vm.prank(alice);
        vm.expectRevert();
        registry.registerSpec(s, 0);
        assertEq(imd.balanceOf(address(registry)), 0);
        assertEq(registry.nextSpecId(), 10001);
        imd.mint(alice, 1);
        vm.prank(alice);
        imd.approve(address(registry), 6.4 ether - 1);
        vm.prank(alice);
        vm.expectRevert();
        registry.registerSpec(s, 0);
        assertEq(imd.balanceOf(address(registry)), 0);
        assertEq(registry.nextSpecId(), 10001);
        vm.prank(alice);
        imd.approve(address(registry), 6.4 ether);
        vm.prank(alice);
        assertEq(registry.registerSpec(s, 0), 10001);
    }
}
