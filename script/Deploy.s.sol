// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {Registry} from "../src/Registry.sol";
import {Renderer} from "../src/Renderer.sol";
import {Composer} from "../src/Composer.sol";

/// @notice Deploys the renderer, the composer (both without arguments) and the registry with the four
///         static chain addresses, the burn executor and two helpers: the same shape as the launch-pipeline
///         input (three contracts, static constructor arguments, the helpers referenced backward).
/// @dev    No environment variable is read and nothing depends on the broadcaster: `deployForChain()`
///         selects Sepolia on 11155111 and mainnet constants on every other chain.
contract Deploy is Script {
    address public constant CURATOR = 0xcB0b0531e86A9aC36Fa865cA8e3dbccF047FDA91;
    address public constant IMD = 0xD34a99Bc0f67aE1bbd63C660e6d0b0dd03E263B7;
    address public constant INTAKE_V2 = 0xa43e6F75ee006411F79Ac1C84120606C2330DE82;
    address public constant ATTESTER = 0x5598Aa9146215Bc13eb26f2c692Ad1461Fd32982;
    address public constant BURN_EXECUTOR = 0xe29386719C155B6847aD5a4E97C6674f10ffc750;
    address public constant SEPOLIA_CURATOR = 0x0919ba50b206C3F31D516De818b1fBc7dA21653D;
    address public constant SEPOLIA_IMD = 0x44a1Cd38474FB1748400E7DEb5F8D786ccE3F89A;
    address public constant SEPOLIA_BURN_EXECUTOR = 0x097A19e0f021BBA5072701132625ad2401043A2E;

    function run() external returns (Registry registry) {
        vm.startBroadcast();
        registry = deployForChain();
        vm.stopBroadcast();
    }

    function deployForChain() public returns (Registry registry) {
        if (block.chainid == 11155111) {
            return deploy(SEPOLIA_CURATOR, SEPOLIA_IMD, INTAKE_V2, ATTESTER, SEPOLIA_BURN_EXECUTOR);
        }
        return deploy(CURATOR, IMD, INTAKE_V2, ATTESTER, BURN_EXECUTOR);
    }

    function deploy(address curator, address imd, address intake, address attester, address burnExecutor)
        public
        returns (Registry registry)
    {
        Renderer renderer = new Renderer();
        Composer composer = new Composer();
        registry = new Registry(curator, imd, intake, attester, address(renderer), address(composer), burnExecutor);
    }
}
