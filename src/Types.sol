// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @notice A catalog or community spec (CATALOG.md section 5). Field order is the ABI; `evidence` is derived
///         from `kind` (chain for 1 to 4, panel for 5 and 6).
struct Spec {
    uint8 kind; // 1 T1 log-count, 2 T2 log-sum, 3 T3 log-rank (shared), 4 T4 call-compare, 5 T5 panel nonce, 6 catalog T6 operator
    address target; // T1 to T4, collection for T6; zero for T5
    string item; // closed event/function signature grammar, <= 256 bytes; empty for T5/T6
    string arg; // [A-Za-z0-9_], 1..32 bytes; T1/T2 the claimant argument, T3 the groupBy key; empty for T4/T5
    string fixedArg; // [A-Za-z0-9_], 0..32 bytes; empty = no second filter (T1/T2 only)
    uint256 fixedVal;
    string sumArg; // [A-Za-z0-9_], T2/T3 only, else empty
    uint8 op; // T4 only: 1 >=, 2 >, 3 <=, 4 <, 5 ==; else 0
    uint256 threshold; // T1/T2/T4/T5 >= 1; T3: head 1..32
    uint64 fromBlock;
    uint64 toBlock;
    string name; // [A-Za-z0-9 .-], 1..32 bytes
}

/// @notice One verified oracle trait with the evidence a third party needs to rerun it: only the fields
///         the metadata prints (V2 item 19 b). The spec body stays readable through `Registry.specOf(id)`.
///         Built by the registry for the renderer; never stored in this shape.
struct OracleMeta {
    uint16 traitId;
    uint8 kind; // the template: 1 to 6; the panel minima follow from it
    uint64 fromBlock;
    uint64 toBlock;
    address target;
    bytes32 requestId; // the Intake's id
    bytes32 oracleRequestId; // the plane's signed UUID
    string name;
}

/// @notice Everything the renderer needs for one card.
struct Card {
    uint256 tokenId;
    address claimant;
    uint16[13] top; // highest true catalog id per family, except lowest for family 11; index 0 = family 1, 0 = none
    uint16[] traits; // every true catalog id
    uint16[] community; // the first 32 verified community ids
    uint256 communityCount;
    OracleMeta[] oracle;
}
