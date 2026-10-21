// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Spec} from "./Types.sol";
import {IWhitelistCurator} from "./interfaces/IWhitelistCurator.sol";

interface ICatalogRegistry {
    function hasTrait(address wallet, uint16 traitId) external view returns (bool);
}

/// @notice Composes the six question templates of TEMPLATES.md into the Intake request body
///         (two-space indent, byte-exact against `templates/fixtures/`) and into the plane's
///         canonical question document (RFC 8785: sorted keys, no whitespace) whose keccak is the
///         attestation's `questionHash` (INTEGRATION.md section 4, check 7).
/// @dev    A separately deployed contract (no arguments, no storage, no immutables): the composed text
///         does not fit the registry's EIP-170 budget. All template text is ASCII and carries no `"` or `\`;
///         spec strings are charset-checked at registration, so no JSON escaping is ever needed here.
contract Composer {
    string public constant DEPOSITED =
        "event Deposited(address indexed contributor, uint256 indexed hour, uint256 amount, uint256 creditedDelta, uint256 weightAdded, uint256 newWeight, uint256 txCount, uint256 hourTotal, uint256 earlyBps)";
    string internal constant FIRST_DEPOSIT =
        "event FirstDeposit(address indexed contributor, uint256 indexed index, uint256 timestamp)";
    string internal constant HOUR_SAVED =
        "event HourSaved(address indexed savior, uint256 indexed hour, uint256 hourTotal)";

    string internal constant DEF_WINDOW = "The pinned window is the whole evidence; events outside it do not count.";
    string internal constant DEF_LOGS_HEAD =
        "eth_getLogs on the contract with topic0 = the event's signature hash and the indexed argument(s) as topics, over exactly the pinned window; or the equivalent explorer log query. ";
    string internal constant DEF_LOGS_TAIL =
        " matching logs; do not deduplicate by transaction. Block numbers are hex.";
    string internal constant DEF_T2_UNITS = "Raw integer units of the argument as emitted, e.g. wei for an ETH amount.";

    /// @notice The hash of the Curator deploy block, the only block hash a body ever carries (trait 1301).
    bytes32 internal constant B_DEPLOY_HASH = 0x43ac0aadac9b134a5e4555d28323431664fd77d74cd6a28cb4ca65e34ba72256;

    address internal constant MAINNET_CURATOR = 0xcB0b0531e86A9aC36Fa865cA8e3dbccF047FDA91;
    uint256 internal constant MERGE_BLOCK = 15_537_395;
    uint256 internal constant MERGE_TIME = 1_663_224_191;
    uint256 internal constant SLOT_SECONDS = 12;

    uint16 internal constant CHAIN_PANEL = 5;
    uint16 internal constant CHAIN_QUORUM = 3;
    uint16 internal constant PANEL_PANEL = 11;
    uint16 internal constant PANEL_QUORUM = 7;
    uint256 internal constant VALID_FOR_SECONDS = 2_592_000;
    /// @dev Blocks a kind 1 to 4 window must end behind the head at registration (two epochs).
    uint256 internal constant FINALITY = 64;

    /// @dev A composed question: text, sorted definition keys and values, and the fixed fields.
    struct Question {
        string question;
        string[] keys;
        string[] values;
        string answerType; // "uint256", "address[]" or "bool"
        bool panel; // evidence: panel (T5/T6) or chain
        uint256 head; // T3 only, else 0
        uint64 fromBlock;
        uint64 toBlock;
    }

    // ------------------------------------------------------------------ the catalog as specs

    uint64 internal constant B_DEPLOY = 0x189378e;
    uint64 internal constant B_FIRST1000 = 0x1893b91;
    uint64 internal constant B_H24 = 0x1895395;
    uint64 internal constant B_END = 0x18984a4;

    error NotACatalogOracleTrait(uint16 traitId);

    /// @notice A catalog oracle trait (601 to 1301) expressed as a Spec (CATALOG.md section 3), its
    ///         log questions targeting the registry's `curator` (the mainnet Curator on the launch).
    function catalogSpec(uint16 traitId, address curator) external view returns (Spec memory s) {
        s = _catalogSpec(traitId, curator);
        if (s.kind == 0) revert NotACatalogOracleTrait(traitId);
    }

    /// @dev `kind` 0 for an id that is not a catalog oracle trait.
    function _catalogSpec(uint16 traitId, address curator) internal view returns (Spec memory s) {
        s.target = curator;
        s.threshold = 1;
        s.fromBlock = B_DEPLOY;
        s.toBlock = B_END;
        if (traitId == 601) {
            s.kind = 6;
            s.target = 0x0000eC93127BAA929E58E97dd0095A2BFb38ec1D;
            s.threshold = 3;
            s.fromBlock = 25_090_085;
            s.toBlock = uint64(block.number - FINALITY);
            s.name = "Swarmed";
        } else if (traitId == 701) {
            s.kind = 1;
            s.item = DEPOSITED;
            s.arg = "contributor";
            s.fromBlock = B_H24;
            s.name = "Uptime";
        } else if (traitId == 801 || traitId == 901) {
            s.kind = 1;
            s.item = DEPOSITED;
            s.arg = "contributor";
            s.fixedArg = "hour";
            s.fixedVal = traitId == 801 ? 64 : 65;
            s.name = traitId == 801 ? "Holdout" : "Final Token";
        } else if (traitId == 1001) {
            s.kind = 1;
            s.item = HOUR_SAVED;
            s.arg = "savior";
            s.name = "Hotfix";
        } else if (traitId >= 1101 && traitId <= 1104) {
            s.kind = 1;
            s.item = FIRST_DEPOSIT;
            s.arg = "contributor";
            s.fixedArg = "index";
            s.fixedVal = traitId == 1101 ? 1 : traitId == 1102 ? 1000 : traitId == 1103 ? 10000 : 19522;
            s.name = traitId == 1101
                ? "PID #1"
                : traitId == 1102 ? "PID #1000" : traitId == 1103 ? "PID #10000" : "PID #19522";
        } else if (traitId == 1105) {
            s.kind = 1;
            s.item = FIRST_DEPOSIT;
            s.arg = "contributor";
            s.toBlock = B_FIRST1000;
            s.name = "First thousand";
        } else if (traitId == 1201) {
            s.kind = 3;
            s.item = DEPOSITED;
            s.arg = "contributor";
            s.sumArg = "weightAdded";
            s.threshold = 32;
            s.name = "Top Weights";
        } else if (traitId == 1301) {
            s.kind = 5;
            s.target = address(0);
            s.threshold = 20;
            s.toBlock = B_DEPLOY;
            s.name = "Pretrained";
        }
    }

    /// @notice Every direct trait true for a wallet now, as the `frozenDirect` word a mint stores:
    ///         bit `(family - 1) * 4 + tier - 1` per true direct id (101 is bit 0; bit 20 is unused).
    function directSnapshot(address wallet, IWhitelistCurator curator) external view returns (uint32 bits) {
        if (wallet == address(0)) return 0;
        (uint256 hour, bool joined) = curator.firstHourOf(wallet);
        if (joined) {
            bits = 1;
            if (hour <= 1) bits |= 1 << 4;
            if (hour == 0) bits |= 1 << 5;
        }
        uint256 n = curator.txCountOf(wallet);
        if (n >= 3) bits |= 1 << 8;
        if (n >= 5) bits |= 1 << 9;
        if (n >= 10) bits |= 1 << 10;
        n = curator.contributedBy(wallet);
        if (n >= 1 ether) bits |= 1 << 12;
        if (n >= 10 ether) bits |= 1 << 13;
        if (n >= 100 ether) bits |= 1 << 14;
        if (n >= 800 ether) bits |= 1 << 15;
        n = curator.pointsOf(wallet);
        if (n >= 1000) bits |= 1 << 16;
        if (n >= 3162) bits |= 1 << 17;
        if (n >= 10000) bits |= 1 << 18;
    }

    /// @notice Enumerates all true catalog ids in ascending order; community specs are excluded.
    /// @dev The registry supplies itself as the read source. Kept here for its EIP-170 headroom.
    function traitsOf(address registry, address wallet) external view returns (uint16[] memory ids) {
        uint16[25] memory all = _catalog();
        uint16[] memory tmp = new uint16[](25);
        uint256 n;
        for (uint256 i; i < 25; ++i) {
            if (ICatalogRegistry(registry).hasTrait(wallet, all[i])) tmp[n++] = all[i];
        }
        ids = new uint16[](n);
        for (uint256 i; i < n; ++i) {
            ids[i] = tmp[i];
        }
    }

    /// @dev The 25 catalog ids ascending (packed big-endian uint16); the first 13 are the direct ones.
    bytes internal constant CATALOG =
        hex"006500c900ca012d012e012f019101920193019401f501f601f7025902bd0321038503e9044d044e044f0450045104b10515";

    function _catalog() internal pure returns (uint16[25] memory ids) {
        bytes memory packed = CATALOG;
        for (uint256 i; i < 25; ++i) {
            ids[i] = (uint16(uint8(packed[2 * i])) << 8) | uint16(uint8(packed[2 * i + 1]));
        }
    }

    // ------------------------------------------------------------------ names and spec guards

    error BadSpec(string field);

    /// @notice The guards of CATALOG.md section 5; reverts `BadSpec(field)` on the first failing field.
    function validateSpec(Spec calldata s, uint256 blockNumber) external view {
        blockNumber = block.chainid == 1 ? block.number : mainnetHeightBound();
        if (s.kind < 1 || s.kind > 5) revert BadSpec("kind");
        bytes memory item = bytes(s.item);
        if (s.kind == 5) {
            if (s.target != address(0)) revert BadSpec("target");
            if (item.length != 0) revert BadSpec("item");
        } else {
            if (s.target == address(0)) revert BadSpec("target");
            if (item.length > 256) revert BadSpec("item");
            _validateItem(item, s.kind == 4);
        }
        bytes memory arg = bytes(s.arg);
        if (s.kind <= 3) {
            if (arg.length == 0) revert BadSpec("arg");
        } else if (arg.length != 0) {
            revert BadSpec("arg");
        }
        if (arg.length > 32 || !_charset(arg, 0)) revert BadSpec("arg");
        // Claimant/grouping fields must be indexed addresses in the declared signature.
        if (s.kind <= 3 && _field(item, arg, 2) == 0) revert BadSpec("arg");
        bytes memory fixedArg = bytes(s.fixedArg);
        if (fixedArg.length > 32 || !_charset(fixedArg, 0)) revert BadSpec("fixedArg");
        if (s.kind > 2 && (fixedArg.length != 0 || s.fixedVal != 0)) revert BadSpec("fixedArg");
        if (s.kind <= 2 && fixedArg.length == 0 && s.fixedVal != 0) revert BadSpec("fixedVal");
        if (fixedArg.length != 0 && _field(item, fixedArg, 1) == 0) revert BadSpec("fixedArg");
        bytes memory sumArg = bytes(s.sumArg);
        if (s.kind == 2 || s.kind == 3) {
            if (sumArg.length == 0 || sumArg.length > 32 || !_charset(sumArg, 0) || _field(item, sumArg, 0) == 0) {
                revert BadSpec("sumArg");
            }
        } else if (sumArg.length != 0) {
            revert BadSpec("sumArg");
        }
        if (s.kind == 4) {
            if (s.op < 1 || s.op > 5) revert BadSpec("op");
        } else if (s.op != 0) {
            revert BadSpec("op");
        }
        if (s.kind == 3) {
            if (s.threshold < 1 || s.threshold > 32) revert BadSpec("threshold");
        } else if (s.threshold < 1) {
            revert BadSpec("threshold");
        }
        if (s.kind == 5) {
            if (s.fromBlock != s.toBlock || uint256(s.toBlock) + 7200 > blockNumber) revert BadSpec("window");
        } else {
            // Finality margin: the window's last block is at least FINALITY blocks behind the head.
            if (
                s.toBlock < s.fromBlock || uint256(s.toBlock) - s.fromBlock + 1 < 7200
                    || uint256(s.toBlock) + FINALITY > blockNumber
            ) {
                revert BadSpec("window");
            }
        }
        bytes memory name = bytes(s.name);
        if (name.length < 1 || name.length > 32 || !_charset(name, 2)) revert BadSpec("name");
    }

    function mainnetHeightBound() public view returns (uint256) {
        if (block.timestamp <= MERGE_TIME) return MERGE_BLOCK;
        return MERGE_BLOCK + (block.timestamp - MERGE_TIME) / SLOT_SECONDS;
    }

    /// @dev Mode 0 (an argument): `[A-Za-z0-9_]`; mode 1 (an item): plus ` ,()[]`; mode 2 (a name):
    ///      `[A-Za-z0-9 .-]`.
    function _charset(bytes memory b, uint8 mode) internal pure returns (bool) {
        for (uint256 i; i < b.length; ++i) {
            bytes1 ch = b[i];
            bool ok = (ch >= "a" && ch <= "z") || (ch >= "A" && ch <= "Z") || (ch >= "0" && ch <= "9");
            if (!ok) {
                if (mode == 2) {
                    ok = ch == " " || ch == "." || ch == "-";
                } else if (mode == 1) {
                    ok = ch == "_" || ch == " " || ch == "," || ch == "(" || ch == ")" || ch == "[" || ch == "]";
                } else {
                    ok = ch == "_";
                }
            }
            if (!ok) return false;
        }
        return true;
    }

    /// @dev Require an existing field (0), an indexed field (1), or an indexed address (2).
    ///      Returns 1 for a data field, or its one-based topic position for an indexed field.
    ///      Input has already passed the closed grammar parser; an absent/mismatched field returns 0.
    function _field(bytes memory item, bytes memory arg, uint8 requirement) internal pure returns (uint256 k) {
        uint256 n = item.length;
        uint256 i;
        while (i < n && item[i] != "(") ++i;
        if (i == n) return 0;
        ++i;
        while (i < n) {
            bool topic;
            bool isAddress;
            bool named;
            uint256 words;
            while (i < n && item[i] != "," && item[i] != ")") {
                if (item[i] == " ") {
                    ++i;
                    continue;
                }
                uint256 start = i;
                while (i < n && item[i] != " " && item[i] != "," && item[i] != ")") ++i;
                if (words == 0) isAddress = _is(item, start, i, "address");
                else if (_is(item, start, i, "indexed")) topic = true;
                else named = _is(item, start, i, arg);
                ++words;
            }
            if (topic) ++k;
            if (named) return requirement == 0 ? 1 : topic && (requirement == 1 || isAddress) ? k : 0;
            if (i == n || item[i] == ")") return 0;
            ++i;
        }
    }

    /// @dev A closed grammar, with exact separators and bounded identifiers; prose cannot be an item.
    function _validateItem(bytes memory b, bool fn) internal pure {
        uint256 i = fn ? 9 : 6;
        if (b.length <= i || !_is(b, 0, i, fn ? bytes("function ") : bytes("event "))) revert BadSpec("item");
        i = _identifier(b, i);
        if (fn) {
            if (!_is(b, i, b.length, "(address) view returns (uint256)")) revert BadSpec("item");
            return;
        }
        if (i >= b.length || b[i++] != "(") revert BadSpec("item");
        if (i < b.length && b[i] == ")") {
            if (i + 1 != b.length) revert BadSpec("item");
            return;
        }
        while (i < b.length) {
            uint256 start = i;
            while (i < b.length && b[i] != " ") ++i;
            if (!_type(b, start, i) || i == b.length) revert BadSpec("item");
            ++i;
            if (i + 8 <= b.length && _is(b, i, i + 8, "indexed ")) i += 8;
            i = _identifier(b, i);
            if (i < b.length && b[i] == ")" && i + 1 == b.length) return;
            if (i + 2 >= b.length || b[i] != "," || b[i + 1] != " ") revert BadSpec("item");
            i += 2;
        }
        revert BadSpec("item");
    }

    function _identifier(bytes memory b, uint256 i) internal pure returns (uint256) {
        uint256 start = i;
        while (i < b.length) {
            bytes1 c = b[i];
            if (!((c >= "A" && c <= "Z") || (c >= "a" && c <= "z") || c == "_" || (i > start && c >= "0" && c <= "9"))) break;
            ++i;
        }
        if (i == start || i - start > 32) revert BadSpec("item");
        return i;
    }

    function _type(bytes memory b, uint256 start, uint256 end) internal pure returns (bool) {
        if (end >= start + 2 && b[end - 2] == "[" && b[end - 1] == "]") end -= 2;
        if (
            _is(b, start, end, "address") || _is(b, start, end, "bool") || _is(b, start, end, "string")
                || _is(b, start, end, "bytes")
        ) return true;
        bool byteType;
        if (end > start + 5 && _is(b, start, start + 5, "bytes")) {
            start += 5;
            byteType = true;
        } else if (end > start + 4 && _is(b, start, start + 4, "uint")) {
            start += 4;
        } else if (end > start + 3 && _is(b, start, start + 3, "int")) {
            start += 3;
        } else {
            return false;
        }
        if (b[start] == "0" || end - start > 3) return false;
        uint256 n;
        for (; start < end; ++start) {
            if (b[start] < "0" || b[start] > "9") return false;
            n = n * 10 + uint8(b[start]) - 48;
        }
        return byteType ? n >= 1 && n <= 32 : n >= 8 && n <= 256 && n % 8 == 0;
    }

    function _is(bytes memory b, uint256 start, uint256 end, bytes memory word) internal pure returns (bool equal) {
        if (end - start != word.length) return false;
        assembly ("memory-safe") {
            equal := eq(keccak256(add(add(b, 32), start), sub(end, start)), keccak256(add(word, 32), mload(word)))
        }
    }

    // ------------------------------------------------------------------ public shape

    /// @notice Composes the body and the plane's `questionHash` for a trait and a claimant: a catalog id's
    ///         spec is built here from `curator` (`s` is ignored), a community id's is `s`. Trait 1301's T5
    ///         parenthesis names the Curator deploy block.
    function compose(uint16 traitId, Spec memory s, address claimant, address consumer, address curator)
        external
        view
        returns (bytes memory body, bytes32 questionHash)
    {
        if (traitId < 10001) {
            s = _catalogSpec(traitId, curator);
            if (s.kind == 0) revert NotACatalogOracleTrait(traitId);
        }
        // The door's bounds (question <= 1000, each value at most 512 characters) hold by construction: validateSpec caps
        // `item` at 256 and the other strings at 32 bytes, and the longest template text (T3) stays under them.
        bytes memory text = _expand();
        Question memory q =
            s.kind == 6 ? operatorQuestion(s, claimant, text) : question(s, claimant, traitId == 1301, text);
        body = encodeBody(q, consumer, text);
        questionHash = keccak256(canonical(q, text));
    }

    // ------------------------------------------------------------------ the six templates

    function question(Spec memory s, address claimant, bool catalogNonce, bytes memory text)
        internal
        pure
        returns (Question memory q)
    {
        string[16] memory v;
        string memory a = Strings.toHexString(claimant);
        string memory c = Strings.toHexString(s.target);
        string memory from = hexMin(s.fromBlock);
        string memory to = hexMin(s.toBlock);
        string memory n = Strings.toString(s.threshold);
        q.fromBlock = s.fromBlock;
        q.toBlock = s.toBlock;
        if (s.kind == 1 || s.kind == 2) {
            q.answerType = "uint256";
            v[0] = string(s.fixedArg);
            v[1] = string(Strings.toString(s.fixedVal));

            string memory filter =
                bytes(s.fixedArg).length == 0 ? "" : _render(" and whose indexed ~A argument equals ~B", v);
            v[0] = string(from);
            v[1] = string(to);

            string memory head = _render(_text(text, 0, 107), v);
            if (s.kind == 1) {
                v[0] = string(head);
                v[1] = string(s.item);
                v[2] = string(c);
                v[3] = string(s.arg);
                v[4] = string(a);
                v[5] = string(filter);

                q.question = _render(_text(text, 107, 156), v);
                q.keys = new string[](2);
                q.values = new string[](2);
                q.keys[0] = "method";
                v[0] = string(DEF_LOGS_HEAD);
                v[1] = string(DEF_LOGS_TAIL);

                q.values[0] = _render("~ACount~B", v);
                q.keys[1] = "window";
                q.values[1] = DEF_WINDOW;
            } else {
                v[0] = string(head);
                v[1] = string(s.sumArg);
                v[2] = string(s.item);
                v[3] = string(c);
                v[4] = string(s.arg);
                v[5] = string(a);
                v[6] = string(filter);

                q.question = _render(_text(text, 263, 221), v);
                q.keys = new string[](3);
                q.values = new string[](3);
                q.keys[0] = "method";
                v[0] = string(DEF_LOGS_HEAD);
                v[1] = string(DEF_LOGS_TAIL);

                q.values[0] = _render("~ASum the named argument of~B", v);
                q.keys[1] = "units";
                q.values[1] = DEF_T2_UNITS;
                q.keys[2] = "window";
                q.values[2] = DEF_WINDOW;
            }
        } else if (s.kind == 3) {
            q.answerType = "address[]";
            q.head = s.threshold;
            // the grouping key's 1-based position among the event's indexed parameters (V2 item 18)
            string memory k = Strings.toString(_field(bytes(s.item), bytes(s.arg), 2));
            v[0] = string(from);
            v[1] = string(to);
            v[2] = string(s.sumArg);
            v[3] = string(s.item);
            v[4] = string(c);
            v[5] = string(s.arg);
            v[6] = string(k);
            v[7] = string(n);

            q.question = _render(_text(text, 484, 357), v);
            q.keys = new string[](1);
            q.values = new string[](1);
            q.keys[0] = "method";
            v[0] = string(s.arg);
            v[1] = string(k);
            v[2] = string(s.sumArg);
            v[3] = string(n);

            q.values[0] = _render(_text(text, 841, 381), v);
        } else if (s.kind == 4) {
            q.answerType = "bool";
            string memory op = opText(s.op);
            v[0] = string(to);
            v[1] = string(s.item);
            v[2] = string(c);
            v[3] = string(op);
            v[4] = string(n);
            v[5] = string(a);

            q.question = _render(_text(text, 1222, 192), v);
            q.keys = new string[](1);
            q.values = new string[](1);
            q.keys[0] = "method";
            v[0] = string(a);
            v[1] = string(to);
            v[2] = string(n);
            v[3] = string(op);

            q.values[0] = _render(_text(text, 1414, 225), v);
        } else {
            q.answerType = "bool";
            q.panel = true;
            string memory b = Strings.toString(s.toBlock);
            string memory nh = hexMin(s.threshold);
            v[0] = string(to);
            v[1] = string(Strings.toHexString(uint256(B_DEPLOY_HASH), 32));
            v[2] = string(Strings.toHexString(MAINNET_CURATOR));
            v[3] = string(to);

            string memory paren = catalogNonce ? _render(_text(text, 1639, 89), v) : _render(_text(text, 1728, 45), v);
            v[0] = string(b);
            v[1] = string(paren);
            v[2] = string(a);
            v[3] = string(n);

            q.question = _render(_text(text, 1773, 241), v);
            q.keys = new string[](4);
            q.values = new string[](4);
            q.keys[0] = "false";
            v[0] = string(to);
            v[1] = string(n);
            v[2] = string(nh);

            q.values[0] = _render(_text(text, 2014, 208), v);
            q.keys[1] = "method";
            v[0] = string(a);
            v[1] = string(to);

            q.values[1] = _render(_text(text, 2222, 394), v);
            q.keys[2] = "true";
            v[0] = string(to);
            v[1] = string(n);
            v[2] = string(nh);

            q.values[2] = _render(_text(text, 2616, 107), v);
            q.keys[3] = "window";
            v[0] = string(b);

            q.values[3] = _render(_text(text, 2723, 144), v);
        }
    }

    /// @dev The approved operator recipe, catalog-only. Body order follows the eight specified keys.
    function operatorQuestion(Spec memory s, address claimant, bytes memory text)
        internal
        pure
        returns (Question memory q)
    {
        string[16] memory v;
        string memory a = Strings.toHexString(claimant);
        string memory to = Strings.toString(s.toBlock);
        q.answerType = "bool";
        q.panel = true;
        q.fromBlock = s.fromBlock;
        q.toBlock = s.toBlock;
        v[0] = string(to);
        v[1] = string(a);

        q.question = _render(_text(text, 2867, 178), v);
        q.keys = new string[](8);
        q.values = new string[](8);
        q.keys[0] = "method";
        v[0] = string(to);

        q.values[0] = _render(_text(text, 3045, 315), v);
        q.keys[1] = "seats";
        v[0] = string(to);
        v[1] = string(a);

        q.values[1] = _render(_text(text, 3360, 451), v);
        q.keys[2] = "agent";
        q.values[2] = _text(text, 3811, 429);
        q.keys[3] = "accepted";
        q.values[3] = _text(text, 4240, 493);
        q.keys[4] = "answer";
        q.values[4] = _text(text, 4733, 216);
        q.keys[5] = "true";
        q.values[5] = _text(text, 4949, 89);
        q.keys[6] = "false";
        q.values[6] = _text(text, 5038, 204);
        q.keys[7] = "window";
        v[0] = string(to);

        q.values[7] = _render(_text(text, 5242, 145), v);
    }

    function opText(uint8 op) internal pure returns (string memory) {
        if (op == 1) return ">=";
        if (op == 2) return ">";
        if (op == 3) return "<=";
        if (op == 4) return "<";
        return "==";
    }

    // ------------------------------------------------------------------ serialisation

    /// @notice The request body: sorted keys, two-space indent, no trailing newline.
    function encodeBody(Question memory q, address consumer, bytes memory text) internal view returns (bytes memory) {
        string[16] memory v;
        v[0] = q.answerType;
        v[1] = Strings.toString(block.chainid);
        v[2] = Strings.toHexString(consumer);
        v[3] = _definitions(q, true);
        v[4] = q.panel ? "panel" : "chain";
        v[5] = q.head == 0 ? "" : string.concat("  \"head\": ", Strings.toString(q.head), ",\n");
        bool large = q.panel || q.head != 0;
        v[6] = large ? "11" : "5";
        v[7] = q.question;
        v[8] = large ? "7" : "3";
        v[9] = Strings.toString(VALID_FOR_SECONDS);
        v[10] = Strings.toString(q.fromBlock);
        v[11] = Strings.toString(q.toBlock);
        return bytes(_render(_text(text, 5387, 307), v));
    }

    /// @notice RFC 8785 question document, with lexicographically sorted definition keys.
    function canonical(Question memory q, bytes memory text) internal pure returns (bytes memory) {
        string[16] memory v;
        v[0] = q.answerType;
        v[1] = _definitions(q, false);
        v[2] = q.panel ? ',"evidence":"panel"' : "";
        v[3] = q.head == 0 ? "" : string.concat(',"head":', Strings.toString(q.head));
        v[4] = q.question;
        v[5] = Strings.toString(q.fromBlock);
        v[6] = Strings.toString(q.toBlock);
        return bytes(_render(_text(text, 5694, 115), v));
    }

    function _definitions(Question memory q, bool pretty) internal pure returns (string memory) {
        bytes memory out;
        for (uint256 i; i < q.keys.length; ++i) {
            uint256 j = !pretty && q.keys.length == 8 ? uint8(bytes8(0x0302040600010507)[i]) : i;
            out = bytes.concat(
                out,
                i == 0 ? bytes("") : pretty ? bytes(",\n") : bytes(","),
                pretty ? bytes('    "') : bytes('"'),
                bytes(q.keys[j]),
                pretty ? bytes('": "') : bytes('":"'),
                bytes(q.values[j]),
                '"'
            );
        }
        return string(out);
    }

    /// @notice Lowercase `0x` hex without leading zeros (`20` -> `0x14`, `0` -> `0x0`).
    function hexMin(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0x0";
        uint256 n;
        for (uint256 t = v; t != 0; t >>= 4) {
            n++;
        }
        bytes memory b = new bytes(n + 2);
        b[0] = "0";
        b[1] = "x";
        for (uint256 i = n + 1; i > 1; --i) {
            uint8 d = uint8(v & 0xf);
            b[i] = bytes1(d < 10 ? 48 + d : 87 + d);
            v >>= 4;
        }
        return string(b);
    }

    /// @dev Interpolate named slots in static ASCII templates with a single shared copy loop.
    function _render(string memory pattern, string[16] memory values) internal pure returns (string memory) {
        uint256 size = bytes(pattern).length;
        assembly ("memory-safe") {
            let p := add(pattern, 32)
            let end := add(p, mload(pattern))
            for {} lt(p, end) { p := add(p, 1) } {
                if eq(byte(0, mload(p)), 126) {
                    p := add(p, 1)
                    let value := mload(add(values, mul(sub(byte(0, mload(p)), 65), 32)))
                    size := add(sub(size, 2), mload(value))
                }
            }
        }
        bytes memory out = new bytes(size);
        assembly ("memory-safe") {
            let p := add(pattern, 32)
            let end := add(p, mload(pattern))
            let dst := add(out, 32)
            for {} lt(p, end) { p := add(p, 1) } {
                let ch := byte(0, mload(p))
                switch eq(ch, 126)
                case 0 {
                    mstore8(dst, ch)
                    dst := add(dst, 1)
                }
                default {
                    p := add(p, 1)
                    let value := mload(add(values, mul(sub(byte(0, mload(p)), 65), 32)))
                    mcopy(dst, add(value, 32), mload(value))
                    dst := add(dst, mload(value))
                }
            }
        }
        return string(out);
    }
    // Generated by tools/gen_composer_text.py from templates/composer-text.json.
    bytes internal constant TEXT =
        hex"57697468696e20746865207265717565737427732070696e6e656420626c6f636b2077696e646f77202866726f6d42800012057e4120746f20746f80000e07422c20626f746820696e636c757369766529206f6e20457468657265756d206d61696e6e65742c207e41636f756e7480006c05607e4260206576656e747320656d697474656420627980001b05636f6e7472616374207e432077686f736520696e6465786564207e4420617267756d656e7420657175616c73207e457e462e20416e7377657280003e07756e74206173206f6e6520696e74656765723b20618000210630206966206e6f207375636880007e06206578697374732e7e4173756d800041057e428000650a6f6680012d074380012d224480012d104580012d12467e4780012d0d73756d80012b0f2080030c0780003b0827732072617720756e69747320286e6f20646563696d616c73206170706c6965642980015d238003646b8002460943800246134480024622452067726f757080001b0a80024f09468000510a28746f706963207e4780005b086c6f67292c206e6576657220627920612064617461206669656c642e20526574757280017e067e48206b6579732077697468800039066172676573742073756d732c2064657363656e64696e672062792073756d2c207469657380005305646472657373206180002209286c6f7765726361736520686578292e6574685f6765744c6f6773206f7665722065786163746c8001460680026d07800267063b8001640680016211418001620c8001560627732080016c07422c20616e800107083a206c6566742d706164203132207a65726f20627974657380020513776f72643b800317057e4320696e80044e0a3b20736f72748001741220616e6420627265616b80017d0980016a0a800207113b80041206646520706f736974696f6e73206265796f6e64207e442c206167726565800152056973206f800305066669727374207e442e20416e20656e74727920746861800022056e6f748001660b20283132206c656180011d058001650b20697320612077726f6e6780057c072e41800856066c6173748005520780041a078005701180056a0880055a094180054a17646f657380004305766965772066756e6374696f6e8009390680005d0780092a0c7280046606612076616c7565207e44207e4520666f80076806800151087e463f80077f09727565206f722066616c73652e4f6e65206574685f63616c6c80005e088000730980052e057e41206180011006800425096180016c087e4220286865782c80024005276c61746573742780015705616e20656e64706f696e7480004706686973746f726963616c2073746174653b20636f6d7061726580022e066177800909098001510780014f068001030643207573696e6780033c06206e756c6c2c207072756e6564206f7280007909207265616480034e062065766964656e63652e28686578207e412c8001320768617368207e423b8000760580001306696e20776869638007180657686974656c69737443757261746f72800c150e6173206465706c6f79656429800059064480004a06800400127370656327738003760729417480036911800243084180066305778002640863800c48066e6f6e6365206f668003420a432c20617380021d0780092606800779075472616e73618003320543800d04067480055806800061052c206174206c656180057a053f20546869732061736b732061626f7580053d0680007407277380007607800b3207636861696e80032d068000531080062f058000400569747320748001010a80036707792e80045e05206f6e6c7920696680040e2280015807732061800e48088002200b62656c6f7780046c057e43292e20496620796f7520636f756c6480010a05800377057468658000560c800046052c207772697465206e6f80072f073b80092607800d39078001250666726f6d2061800450072c80045e05800456112e43616c6c80027118287e412c207e422980060c058002230c8006122e2c20652e672e2068747470733a2f2f7270632e6d657680004f0565722e696f206f7280001d096574682e647270632e6f72673b206369746580005d0a616e642063616c6c2e205080062309756e617661696c61626c6580006d0972726f7273206f728001720628666c617368626f74732c20317270632c20636c6f7564666c6172652c207075626c69636e6f64652920617280025205800662083a2075736520616e6f746865728001631f2e204578706c6f72800907058004350a6c69737473800058078005130680050906616e64800016098007510980094006800459338000720c800465126f668006290b80046b07546865800b37086980071f0673696e676c800839087e413b206974206669786573800843078006340c746f80043b062049800c630a2074696d652072616e67652c80015f0580066905757272800e7c0580042f0629800707088000340680072205800c6d06557020746f8001330b800c3e15698000550677616c6c6580014b056f706572800744056e204964656e746974794d4420736580075405726f75676880017a0a3320616363657074656480002c092e6d6420737761726d206a6f62800168056c652069742068656c648008150673656174800c5f17466f75722073746570732c20657865637574656420696e206f726465728015020870726f6365647572653a80004b05732028737465702031292c206167800219058000100532292c80011e0a8000130633292c80074c088000110634292e204576657279800c0c096f66800a7a12617263686976801168057380030605800331067580025f0e801472092e204180081e117061727469616c206c6f6780006b052c206f7280050e11800a6108800444062c800d1b0f3a80091e108012440880023b0653800204052c800213068001560880087b05666572801630052c20746f2c20746f6b656e49643b20616c6c801353082980011805800d0a078003750b636f6c6c6580060206307830303030654339333132374241413932394535384539376464303039354132424662333865633144800a210680021706323530393030383520746f207e4180187907800020056f7220746f206973207e422e20506572800118082c206120686f6c80124b05696e74657276616c2072756e7380003706800f070a6f66800724086680003e058005460c2880177e0b80001a07800e6d0d6e65787480003c0a80001505617480010206206177617980006c06697420286578800049083b20616e8001120a7374696c6c206f70656e206174207e4120656e647380000b078004090b53616d652d80007b0680006f088009390680055105800f17066c6f678003080680034306322c80074306678019000580016605736561742e20546865204167656e74426f756e642875696e74323536801716098000310549642c2075696e7438800017097374616e646172642c80101a0980001a0880016f054380112f07800037063235368003080b80003007726567697374657265644279800429058001160580142e066170746572203078646531353241664237646235333733463334383736453134393966624438393341383264443333368019510780007a0c801c7406800327088004720b80096f0580010d068000240e80020f06416e80076e07697320626f7580002d0580001f0980042d1369747380023f0b800571066e2e20418000300680067f086120626980186506686180067e0580006406800e24056f756e74800a640568696e6780032d06338008630b6a6f6273800326064e6577466565646261636b80023006801c08073020307836613461363137343335313963396436343861313465363439336634376462653366663161613239653737383563393663383332366132303565353866656263298018310a7075746180022a058003220672792030783830303462616131376335356138383138396165313336623138326535666461313964653962363380070b078001180632800d2f08626174636880035105623664306131383762303530666135626230623837303333613230336633376265636634613737352c800049077365636f6e64801b4a0a2028801a030520333220746f2036332980205b083180003208800319066c69657320696e73696465800b5c0580015d0780074806277380080b118006120b800e11068001480c31801a7105800418088004150b800c7507206174206f72206265666f80184807801d3a0680010b052e20456163688021150680071305800c6d06801b780580036d063480071a07800e5d06800d3a0677686580157e06656e7472696580011f05800c6b06802063056d6564801e6407800b0f05800e45078009280968656c800c24056d626572800e550b3b80146a0780122305776973652e2080172a068000650780142e0664697374696e6374800479053b20618001360580030e1780101c07318005451080121d0d636f6d706c65748016180d800d3008732065737461626c6973800f7e0d80017608756e6480242a076d6574686f648017500f80005a28666580247106616e80005c1c2049662061800f3109800e6a0c2c800e68098015440e8017592c6e20696e80013009801311058013570e80042d0573800d5a10800b74098012661480137711801049098014000c80031b05800841068013620868801d21098010190c2e7b0a20202280013b0654797065223a20227e41222c0a202022800051054964223a2031800010066f6e73756d6572223a207b0a20208000220d7e422c80001306766572696679696e67800b14088000520543220a20207d80004605646566696e80223506800049057e4480001b0980111e088000330545222c0a7e4620202270616e656c53697a65223a207e478000290580215f05696f6e800029054880012e0671756f72756d223a207e4980001005768001380976616c6964466f725380054a0573223a207e4a800019058002030680014f0a80280909223a207e4b8001510780223407223a207e4c0a20207d0a7d7b8002300d80022f0580020a0a312c8001620e7b7e427d7e437e442c8001350b80015d05227680002d05800104087b80007e0c7e462c8000780a7e477d7d";

    /// @dev Lossless static ASCII text, expanded once per composition. A marker (128) introduces
    ///      a base-128 distance and a length; copies may overlap, exactly as an LZ back-reference.
    function _expand() internal pure returns (bytes memory out) {
        bytes memory packed = TEXT;
        out = new bytes(5809);
        assembly ("memory-safe") {
            let p := add(packed, 32)
            let end := add(p, mload(packed))
            let dst := add(out, 32)
            for {} lt(p, end) {} {
                let c := byte(0, mload(p))
                p := add(p, 1)
                switch lt(c, 128)
                case 1 {
                    mstore8(dst, c)
                    dst := add(dst, 1)
                }
                default {
                    let distance := add(mul(byte(0, mload(p)), 128), byte(1, mload(p)))
                    let copyEnd := add(dst, byte(2, mload(p)))
                    p := add(p, 3)
                    for {} lt(dst, copyEnd) { dst := add(dst, 1) } {
                        mstore8(dst, byte(0, mload(sub(dst, distance))))
                    }
                }
            }
        }
    }

    function _text(bytes memory text, uint256 start, uint256 length) internal pure returns (string memory) {
        bytes memory out = new bytes(length);
        assembly ("memory-safe") { mcopy(add(out, 32), add(add(text, 32), start), length) }
        return string(out);
    }
}
