// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @notice Passive coded destination for fee-forwarding tests. Bridging is a separate operation.
contract MockBurnExecutor {
    function previewBridge() external pure returns (uint256, uint256, uint256) {
        return (0, 0, 0);
    }
}
