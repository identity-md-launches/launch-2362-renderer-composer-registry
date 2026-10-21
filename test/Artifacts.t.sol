// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
import {MockBurnExecutor} from "./mocks/MockBurnExecutor.sol";

import {Test} from "forge-std/Test.sol";
import {Registry} from "../src/Registry.sol";
import {Renderer} from "../src/Renderer.sol";
import {Composer} from "../src/Composer.sol";
import {MockCurator, MockIDMD, MockIMD, MockIntake} from "./mocks/Mocks.sol";
import {IWhitelistCurator} from "../src/interfaces/IWhitelistCurator.sol";
import {Deploy} from "../script/Deploy.s.sol";

/// @notice Launch discipline: no immutables (empty `immutableReferences` in every artifact), two
///         deployments with identical runtime code, EIP-170, the deploy script's constants.
contract ArtifactsTest is Test {
    MockIDMD internal idmd;
    MockBurnExecutor internal executor;

    function setUp() public {
        idmd = new MockIDMD();
        executor = new MockBurnExecutor();
    }

    function _immutableRefs(string memory artifact) internal view returns (string memory) {
        string memory j = vm.readFile(artifact);
        // solc omits `immutableReferences` when there is none; present, it must be an empty object
        if (!vm.keyExistsJson(j, ".deployedBytecode.immutableReferences")) return "";
        string[] memory keys = vm.parseJsonKeys(j, ".deployedBytecode.immutableReferences");
        return keys.length == 0 ? "" : keys[0];
    }

    function test_noImmutableReferencesInAnyArtifact() public view {
        assertEq(_immutableRefs("out/Registry.sol/Registry.json"), "", "Registry has immutables");
        assertEq(_immutableRefs("out/Renderer.sol/Renderer.json"), "", "Renderer has immutables");
        assertEq(_immutableRefs("out/Composer.sol/Composer.json"), "", "Composer has immutables");
    }

    function test_twoDeploymentsHaveIdenticalRuntimeCode() public {
        Renderer r1 = new Renderer();
        Renderer r2 = new Renderer();
        Composer c1 = new Composer();
        Composer c2 = new Composer();
        MockIMD imdMock = new MockIMD();
        Registry a = new Registry(
            address(new MockCurator()),
            address(imdMock),
            address(new MockIntake(address(imdMock))),
            address(5),
            address(r1),
            address(c1),
            address(executor)
        );
        MockIMD imdMock2 = new MockIMD();
        Registry b = new Registry(
            address(new MockCurator()),
            address(imdMock2),
            address(new MockIntake(address(imdMock2))),
            address(10),
            address(r2),
            address(c2),
            address(executor)
        );
        assertEq(address(a).code, address(b).code, "registry runtime differs");
        assertEq(address(r1).code, address(r2).code, "renderer runtime differs");
        assertEq(address(c1).code, address(c2).code, "composer runtime differs");
        assertLt(address(a).code.length, 24_576, "registry exceeds EIP-170");
        assertLe(address(r1).code.length, 24_576);
        assertLe(address(c1).code.length, 24_576);
        assertEq(address(a).code, vm.getDeployedCode("Registry.sol:Registry"), "runtime equals the artifact");
    }

    function test_constructorRejectsZeroAddressesAndStoresTheRest() public {
        Renderer r = new Renderer();
        Composer c = new Composer();
        MockIMD imd = new MockIMD();
        vm.expectRevert(Registry.ZeroAddress.selector);
        new Registry(address(0), address(3), address(4), address(5), address(r), address(c), address(executor));
        vm.expectRevert(Registry.ZeroAddress.selector);
        new Registry(address(1), address(3), address(4), address(5), address(0), address(c), address(executor));
        vm.warp(1_791_700_000);
        MockCurator curator = new MockCurator();
        MockIntake intake = new MockIntake(address(imd));
        Registry reg = new Registry(
            address(curator), address(imd), address(intake), address(5), address(r), address(c), address(executor)
        );
        assertEq(address(reg.curator()), address(curator));
        assertEq(address(reg.imd()), address(imd));
        assertEq(address(reg.intake()), address(intake));
        assertEq(reg.attester(), address(5));
        assertEq(address(reg.renderer()), address(r));
        assertEq(address(reg.composer()), address(c));
        assertGt(address(reg.burnExecutor()).code.length, 0);
        assertEq(reg.nextSpecId(), 10001);
        assertEq(reg.ACTION(), 0x6f7261636c652e72657175657374406f7261636c652d31000000000000000000);
    }

    function test_constructorRejectsUnsettledOrUnavailableCurator() public {
        Renderer r = new Renderer();
        Composer c = new Composer();
        MockCurator curator = new MockCurator();
        bytes memory settlementRead = abi.encodeCall(IWhitelistCurator.isSettled, ());
        vm.mockCall(address(curator), settlementRead, abi.encode(false));
        vm.expectRevert("Curator not settled");
        new Registry(address(curator), address(3), address(4), address(5), address(r), address(c), address(executor));
        vm.mockCallRevert(address(curator), settlementRead, "unavailable");
        vm.expectRevert(bytes("unavailable"));
        new Registry(address(curator), address(3), address(4), address(5), address(r), address(c), address(executor));
        vm.clearMockedCalls();
    }

    function test_constructorAcceptsUnavailableCuratorOnEmptyFloor() public {
        address bare = makeAddr("no curator code");
        Registry reg = new Registry(
            bare,
            address(3),
            address(4),
            address(5),
            address(new Renderer()),
            address(new Composer()),
            address(executor)
        );
        assertEq(address(reg.curator()), bare);
        assertGt(address(reg).code.length, 0);
    }

    function test_deployScriptUsesMainnetConstantsOnEveryOtherChain() public {
        Deploy d = new Deploy();
        assertEq(d.CURATOR(), 0xcB0b0531e86A9aC36Fa865cA8e3dbccF047FDA91);
        assertEq(d.IMD(), 0xD34a99Bc0f67aE1bbd63C660e6d0b0dd03E263B7);
        assertEq(d.INTAKE_V2(), 0xa43e6F75ee006411F79Ac1C84120606C2330DE82);
        assertEq(d.ATTESTER(), 0x5598Aa9146215Bc13eb26f2c692Ad1461Fd32982);
        assertEq(d.BURN_EXECUTOR(), 0xe29386719C155B6847aD5a4E97C6674f10ffc750);
        deployCodeTo("Mocks.sol:MockCurator", d.CURATOR());
        deployCodeTo("Mocks.sol:MockIntake", abi.encode(d.IMD()), d.INTAKE_V2());
        deployCodeTo("MockBurnExecutor.sol:MockBurnExecutor", d.BURN_EXECUTOR());
        deployCodeTo("MockBurnExecutor.sol:MockBurnExecutor", d.SEPOLIA_BURN_EXECUTOR());
        deployCodeTo("Mocks.sol:MockIMD", d.IMD());
        uint256[3] memory chains = [uint256(1), 4663, 31337];
        for (uint256 i; i < chains.length; ++i) {
            vm.chainId(chains[i]);
            Registry reg = d.deployForChain();
            _scriptSelection(reg, d.CURATOR(), d.IMD(), d.BURN_EXECUTOR());
        }
    }

    function test_deployScriptUsesSepoliaConstantsAndNonzeroExecutor() public {
        vm.chainId(11155111);
        Deploy d = new Deploy();
        assertEq(d.SEPOLIA_CURATOR(), 0x0919ba50b206C3F31D516De818b1fBc7dA21653D);
        assertEq(d.SEPOLIA_IMD(), 0x44a1Cd38474FB1748400E7DEb5F8D786ccE3F89A);
        assertEq(d.SEPOLIA_BURN_EXECUTOR(), 0x097A19e0f021BBA5072701132625ad2401043A2E);
        deployCodeTo("Mocks.sol:MockCurator", d.SEPOLIA_CURATOR());
        deployCodeTo("Mocks.sol:MockIMD", d.SEPOLIA_IMD());
        deployCodeTo("Mocks.sol:MockIntake", abi.encode(d.SEPOLIA_IMD()), d.INTAKE_V2());
        deployCodeTo("MockBurnExecutor.sol:MockBurnExecutor", d.BURN_EXECUTOR());
        deployCodeTo("MockBurnExecutor.sol:MockBurnExecutor", d.SEPOLIA_BURN_EXECUTOR());
        Registry reg = d.deployForChain();
        _scriptSelection(reg, d.SEPOLIA_CURATOR(), d.SEPOLIA_IMD(), d.SEPOLIA_BURN_EXECUTOR());
    }

    function _scriptSelection(Registry reg, address curator, address imd, address executor) internal view {
        assertEq(address(reg.curator()), curator);
        assertEq(address(reg.imd()), imd);
        assertEq(address(reg.intake()), 0xa43e6F75ee006411F79Ac1C84120606C2330DE82);
        assertEq(reg.attester(), 0x5598Aa9146215Bc13eb26f2c692Ad1461Fd32982);
        assertEq(address(reg.burnExecutor()), executor);
        assertTrue(address(reg.renderer()).code.length > 0);
        assertTrue(address(reg.composer()).code.length > 0);
        assertEq(address(reg).code, vm.getDeployedCode("Registry.sol:Registry"));
    }

    function test_noForbiddenOpcodesInRuntime() public {
        Renderer r = new Renderer();
        Composer c = new Composer();
        MockIMD imdMock = new MockIMD();
        Registry reg = new Registry(
            address(new MockCurator()),
            address(imdMock),
            address(new MockIntake(address(imdMock))),
            address(5),
            address(r),
            address(c),
            address(executor)
        );
        address[3] memory targets = [address(reg), address(r), address(c)];
        for (uint256 t; t < 3; ++t) {
            bytes memory code = targets[t].code;
            for (uint256 j; j < code.length; ++j) {
                uint8 op = uint8(code[j]);
                if (op >= 0x60 && op <= 0x7f) {
                    j += op - 0x5f;
                    continue;
                }
                assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden opcode");
            }
        }
    }
}
