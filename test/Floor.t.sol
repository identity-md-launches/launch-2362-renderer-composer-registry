// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Registry} from "../src/Registry.sol";

/// @notice The launch factory supplies creation code, then constructor arguments, to CREATE2.
contract FloorProbe {
    function deployAll(bytes memory rendererCode, bytes memory composerCode, bytes memory registryCode)
        external
        returns (address renderer, address composer, address registry)
    {
        renderer = _deploy(rendererCode, bytes32("Renderer"));
        composer = _deploy(composerCode, bytes32("Composer"));
        registry = _deploy(registryCode, bytes32("Registry"));
    }

    function _deploy(bytes memory initCode, bytes32 salt) internal returns (address deployed) {
        assembly ("memory-safe") {
            deployed := create2(0, add(initCode, 32), mload(initCode), salt)
            if iszero(deployed) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
    }
}

/// @notice Both launch parameter sets deploy with coded helpers/executor and three absent read dependencies.
contract FloorTest is Test {
    function test_mainnetReadDependencyFloorWithCodedExecutor() public {
        vm.chainId(1);
        _floor(
            0xcB0b0531e86A9aC36Fa865cA8e3dbccF047FDA91,
            0xD34a99Bc0f67aE1bbd63C660e6d0b0dd03E263B7,
            0xe29386719C155B6847aD5a4E97C6674f10ffc750
        );
    }

    function test_sepoliaReadDependencyFloorWithCodedExecutor() public {
        vm.chainId(11155111);
        _floor(
            0x0919ba50b206C3F31D516De818b1fBc7dA21653D,
            0x44a1Cd38474FB1748400E7DEb5F8D786ccE3F89A,
            0x097A19e0f021BBA5072701132625ad2401043A2E
        );
    }

    function _floor(address curator, address imd, address executor) internal {
        FloorProbe probe = new FloorProbe();
        bytes memory rendererCode = vm.getCode("Renderer.sol:Renderer");
        bytes memory composerCode = vm.getCode("Composer.sol:Composer");
        address[7] memory args = [
            curator,
            imd,
            0xa43e6F75ee006411F79Ac1C84120606C2330DE82,
            0x5598Aa9146215Bc13eb26f2c692Ad1461Fd32982,
            _predict(address(probe), bytes32("Renderer"), rendererCode),
            _predict(address(probe), bytes32("Composer"), composerCode),
            executor
        ];
        for (uint256 i; i < 4; ++i) {
            assertEq(args[i].code.length, 0, "dependency floor must be empty");
        }
        vm.etch(executor, hex"00"); // the approved constructor always requires a coded executor
        bytes memory registryCode = bytes.concat(
            vm.getCode("Registry.sol:Registry"),
            abi.encode(args[0], args[1], args[2], args[3], args[4], args[5], args[6])
        );
        address predictedRegistry = _predict(address(probe), bytes32("Registry"), registryCode);
        assertLe(rendererCode.length, 49_152, "Renderer init code exceeds EIP-3860");
        assertLe(composerCode.length, 49_152, "Composer init code exceeds EIP-3860");
        assertLe(registryCode.length, 49_152, "Registry init code exceeds EIP-3860");
        uint64 nonceBefore = vm.getNonce(address(probe));
        // A funded probe proves that construction leaves its ETH untouched.
        vm.deal(address(probe), 1 ether);
        (address deployedRenderer, address deployedComposer, address deployed) =
            probe.deployAll(rendererCode, composerCode, registryCode);
        assertEq(vm.getNonce(address(probe)), nonceBefore + 3, "factory must create exactly three contracts");
        assertEq(address(probe).balance, 1 ether, "factory sent ETH");
        assertEq(deployedRenderer, args[4]);
        assertEq(deployedComposer, args[5]);
        assertEq(deployed, predictedRegistry);
        for (uint256 i; i < args.length; ++i) {
            assertEq(args[i].balance, 0, "dependency received ETH");
        }
        assertEq(deployed.balance, 0, "Registry received ETH");
        assertEq(vm.getNonce(deployedRenderer), 1, "Renderer constructor created a contract");
        assertEq(vm.getNonce(deployedComposer), 1, "Composer constructor created a contract");
        assertEq(vm.getNonce(deployed), 1, "Registry constructor created a contract");
        _runtime(args[4]);
        _runtime(args[5]);
        _runtime(deployed);
        Registry registry = Registry(deployed);
        assertEq(address(registry.curator()), args[0]);
        assertEq(address(registry.imd()), args[1]);
        assertEq(address(registry.intake()), args[2]);
        assertEq(registry.attester(), args[3]);
        assertEq(address(registry.renderer()), args[4]);
        assertEq(address(registry.composer()), args[5]);
        assertEq(address(registry.burnExecutor()), args[6]);
        assertEq(registry.name(), "Sworn");
        assertEq(registry.symbol(), "SWORN");
        assertEq(registry.nextSpecId(), 10001);
    }

    function _predict(address factory, bytes32 salt, bytes memory initCode) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), factory, salt, keccak256(initCode))))));
    }

    function _runtime(address target) internal view {
        bytes memory code = target.code;
        assertGt(code.length, 0, "deployment has no runtime");
        assertLe(code.length, 24_576, "runtime exceeds EIP-170");
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf2 && op != 0xf4 && op != 0xff, "forbidden runtime opcode");
        }
        (bool ownerExists, bytes memory ownerData) = target.staticcall(abi.encodeWithSignature("owner()"));
        (bool adminExists, bytes memory adminData) = target.staticcall(abi.encodeWithSignature("admin()"));
        assertFalse(ownerExists, "owner() exists");
        assertFalse(adminExists, "admin() exists");
        assertEq(ownerData.length, 0);
        assertEq(adminData.length, 0);
    }
}
