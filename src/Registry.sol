// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {IWhitelistCurator} from "./interfaces/IWhitelistCurator.sol";
import {IIntake} from "./interfaces/IIntake.sol";
import {IOracleConsumer, OracleAttestation} from "./interfaces/IOracleConsumer.sol";
import {Spec} from "./Types.sol";
import {Composer} from "./Composer.sol";
import {Renderer} from "./Renderer.sol";

/// @title Sworn registry
/// @notice Ownerless, non-upgradeable ERC-721: one card per wallet, traits as facts about the wallet
///         that minted it. Direct-read traits are evaluated from the settled WhitelistCurator: live for a wallet without a card, frozen at mint for a wallet with one. Oracle
///         traits are stored per (claimant, traitId) after an attestation signed by the IMD oracle passes
///         every check of INTEGRATION.md section 4 inside `onResult`.
/// @dev    No owner, pause, upgrade, fee switch, `receive`, `fallback`, `immutable` or `tx.origin`.
///         All seven dependency addresses are ordinary storage. Renderer, Composer and BurnExecutor
///         must have code. The empty dependency floor skips the three passive external reads only.
///         Holding a card gives no power over it and takes none away from the holder: every mutating
///         entry point acts on `msg.sender`'s own wallet facts, nothing is keyed by the token.
contract Registry is ERC721, IERC4906, ReentrancyGuard, IOracleConsumer {
    using SafeERC20 for IERC20;

    // ------------------------------------------------------------------ types

    struct Pending {
        address claimant; // zero for a shared fact
        uint16 traitId; // or the fact id
        uint64 requestedAt;
        bytes32 questionHash;
        uint64 fromBlock;
        uint64 toBlock;
    }

    /// @dev Only the living operator window needs storage; other windows are immutable.
    struct VerifiedEntry {
        bytes32 requestId;
        bytes32 oracleRequestId;
        uint64 fromBlock;
        uint64 toBlock;
    }

    struct SharedFact {
        bytes32 requestId;
        bytes32 answerHash;
        bytes32 oracleRequestId;
        uint16 length;
    }

    // ------------------------------------------------------------------ constants (CATALOG.md)

    bytes32 public constant ACTION = bytes32("oracle.request@oracle-1");
    uint256 public constant MINT_FEE = 0.1 ether;
    uint256 public constant SPEC_FEE = 6.4 ether;
    uint256 internal constant ABANDON_AFTER = 31 days;
    uint256 internal constant ISSUE_WINDOW = 1 days;
    uint256 internal constant VALID_FOR_SECONDS = 30 days;
    uint256 internal constant QUESTION_CHAIN_ID = 1;
    uint16 internal constant FIRST_SPEC_ID = 10001;

    uint64 internal constant B_DEPLOY = 0x189378e;
    uint64 internal constant B_FIRST1000 = 0x1893b91;
    uint64 internal constant B_H24 = 0x1895395;
    uint64 internal constant B_END = 0x18984a4;
    uint16 internal constant CHAIN_PANEL = 5;
    uint16 internal constant CHAIN_QUORUM = 3;
    uint16 internal constant PANEL_PANEL = 11;
    uint16 internal constant PANEL_QUORUM = 7;

    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 internal constant NAME_HASH = keccak256("IdentityMD Oracle");
    bytes32 internal constant VERSION_HASH = keccak256("2");
    bytes32 internal constant ATTESTATION_TYPEHASH = keccak256(
        "OracleAttestation(bytes32 requestId,uint256 chainId,bytes32 questionHash,uint8 answerType,bytes answer,uint256 figure,uint64 fromBlock,uint64 toBlock,bytes32 blockHash,bytes32 panelJobId,uint16 panelSize,uint16 quorum,uint16 agreed,uint64 issuedAt,uint64 expiresAt)"
    );
    uint64 internal constant ISSUED_AT_TOLERANCE = 1 hours;

    // ------------------------------------------------------------------ storage (no immutables)

    IWhitelistCurator public curator;
    IERC20 public imd;
    IIntake public intake;
    address public attester;
    Renderer public renderer;
    Composer public composer;
    address public burnExecutor;

    uint256 internal _nextTokenId;
    mapping(address => uint256) public tokenOf;
    mapping(uint256 => address) public claimantOf;
    mapping(uint256 => uint64) public mintedAtBlock;
    /// @notice The direct traits true at mint, one bit per direct trait: bit `(family - 1) * 4 + tier - 1`
    ///         (101 is bit 0, 303 bit 10; bit 20 is unused). A card's direct traits never change afterwards.
    mapping(uint256 => uint32) public frozenDirect;

    mapping(bytes32 => Pending) internal _pending;
    mapping(address => mapping(uint16 => bytes32)) public pendingOf;
    mapping(uint16 => bytes32) public sharedPending;
    mapping(address => mapping(uint16 => VerifiedEntry)) internal _verified;
    mapping(address => uint16[]) internal _specsOf;
    mapping(uint16 => SharedFact) internal _shared;

    mapping(uint16 => Spec) internal _specs;
    uint16 public nextSpecId;

    // ------------------------------------------------------------------ events

    event CardMinted(address indexed claimant, uint256 indexed tokenId);
    event TraitRequested(address indexed claimant, uint16 indexed traitId, bytes32 requestId, bytes32 questionHash);
    event Verified(address indexed claimant, uint16 indexed traitId, bytes32 requestId, bytes32 oracleRequestId);
    event Missed(bytes32 requestId, uint16 traitId, uint8 reason);
    event NoVerdict(bytes32 requestId, uint16 traitId, uint8 status, bytes32 reason, uint16 agreed, uint16 answered);
    event Abandoned(bytes32 requestId);
    event SpecRegistered(uint16 indexed traitId, address indexed registrant);
    event SharedFactStored(uint16 indexed factId, bytes32 requestId, uint16 length);
    // ------------------------------------------------------------------ errors

    error ZeroAddress();
    error AlreadyMinted(address claimant);
    error NotIntake();
    error NoTraits();
    error NotAnOracleTrait(uint16 traitId);
    error NotASharedFact(uint16 traitId);
    error AlreadyVerified(address claimant, uint16 traitId);
    error AlreadyPending(address claimant, uint16 traitId);
    error PriceAboveMax(uint256 price, uint256 maxPrice);
    error ZeroPrice();
    error NotPending(bytes32 requestId);
    error TooEarly();
    error NotClaimant();
    error FactAlreadyStored(uint16 factId);
    error FactNotStored(uint16 factId);
    error ListMismatch();
    error NotInList();
    error NoCard(uint256 tokenId);
    error UnexpectedSpecId(uint256 expected, uint256 next);
    error ExecutorHasNoCode();
    error DependencyHasNoCode();
    error RequestIdTaken(bytes32 requestId);

    // ------------------------------------------------------------------ constructor

    /// @param curator_ WhitelistCurator 0xcb0b0531e86a9ac36fa865ca8e3dbccf047fda91
    /// @param imd_ IMD token 0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7
    /// @param intake_ IMD Intake v2 0xa43e6f75ee006411f79ac1c84120606c2330de82
    /// @param attester_ oracle attester 0x5598aa9146215bc13eb26f2c692ad1461fd32982
    /// @param renderer_ the `Renderer` (no constructor arguments, no storage), deployed first
    /// @param composer_ the `Composer` (no constructor arguments, no storage), deployed first
    /// @param burnExecutor_ IMD BurnExecutor V2; fees are forwarded for bridging and burning on Base.
    /// @dev Renderer and Composer are deployed first. A floor with no Curator, IMD or Intake code
    ///      skips settlement, decimals and price reads; the three code checks always apply.
    constructor(
        address curator_,
        address imd_,
        address intake_,
        address attester_,
        address renderer_,
        address composer_,
        address burnExecutor_
    ) ERC721("Sworn", "SWORN") {
        if (
            curator_ == address(0) || imd_ == address(0) || intake_ == address(0) || attester_ == address(0)
                || renderer_ == address(0) || composer_ == address(0) || burnExecutor_ == address(0)
        ) revert ZeroAddress();
        if (renderer_.code.length == 0 || composer_.code.length == 0) revert DependencyHasNoCode();
        if (burnExecutor_.code.length == 0) revert ExecutorHasNoCode();
        curator = IWhitelistCurator(curator_);
        bool floor = curator_.code.length == 0 && imd_.code.length == 0 && intake_.code.length == 0;
        if (!floor) {
            require(curator.isSettled(), "Curator not settled");
            require(IERC20Metadata(imd_).decimals() == 18, "IMD decimals");
            require(IIntake(intake_).priceOf(ACTION, imd_) != 0, "Intake price");
        }
        imd = IERC20(imd_);
        intake = IIntake(intake_);
        attester = attester_;
        renderer = Renderer(renderer_);
        composer = Composer(composer_);
        burnExecutor = burnExecutor_;
        nextSpecId = FIRST_SPEC_ID;
    }

    // ------------------------------------------------------------------ cards

    /// @notice Mints once per wallet; 0.1 IMD is forwarded to the BurnExecutor for bridging and
    ///         burning on Base. The thirteen Curator-read traits are frozen on the card.
    function mintCard() external nonReentrant returns (uint256 tokenId) {
        if (tokenOf[msg.sender] != 0) revert AlreadyMinted(msg.sender);
        imd.safeTransferFrom(msg.sender, burnExecutor, MINT_FEE);
        tokenId = ++_nextTokenId;
        tokenOf[msg.sender] = tokenId;
        claimantOf[tokenId] = msg.sender;
        mintedAtBlock[tokenId] = uint64(block.number);
        frozenDirect[tokenId] = composer.directSnapshot(msg.sender, curator);
        _mint(msg.sender, tokenId);
        emit CardMinted(msg.sender, tokenId);
    }

    /// @notice Cards minted so far; none is ever burned.
    function totalSupply() external view returns (uint256) {
        return _nextTokenId;
    }

    /// @notice The card's metadata, drawn by the renderer from this registry's public reads
    ///         (`claimantOf`, `traitsOf`, `verifiedSpecsOf`, `verified` and `specOf`).
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (claimantOf[tokenId] == address(0)) revert NoCard(tokenId);
        return renderer.tokenURIOf(address(this), tokenId);
    }

    /// @dev ERC-4906: marketplaces refresh the card on every transfer.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address from) {
        from = super._update(to, tokenId, auth);
        if (from != address(0)) emit MetadataUpdate(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, IERC165) returns (bool) {
        return interfaceId == bytes4(0x49064906) || super.supportsInterface(interfaceId);
    }

    // ------------------------------------------------------------------ traits

    /// @notice The credential: for a direct-read trait the card's snapshot when the wallet minted one,
    ///         else the live rule; the `verified` entry otherwise. Needs no card.
    ///         Unknown ids and the zero address are false, never a revert.
    function hasTrait(address wallet, uint16 traitId) public view returns (bool) {
        if (wallet == address(0)) return false;
        if (_isDirect(traitId)) return hasDirectTrait(wallet, traitId);
        return _verified[wallet][traitId].requestId != 0;
    }

    /// @notice A direct trait: frozen at mint for a wallet with a card, live for one without
    ///         False for a non-direct id, including the oracle trait 601 (Swarmed).
    function hasDirectTrait(address wallet, uint16 traitId) public view returns (bool) {
        if (!_isDirect(traitId)) return false;
        uint256 tokenId = tokenOf[wallet];
        if (tokenId != 0) return frozenDirect[tokenId] & (1 << ((traitId / 100 - 1) * 4 + traitId % 100 - 1)) != 0;
        return composer.directSnapshot(wallet, curator) & (1 << ((traitId / 100 - 1) * 4 + traitId % 100 - 1)) != 0;
    }

    /// @notice The catalog ids (all tiers) that are true for a wallet, ascending; no community specs.
    function traitsOf(address wallet) public view returns (uint16[] memory ids) {
        return composer.traitsOf(address(this), wallet);
    }

    function verifiedSpecsOf(address wallet) external view returns (uint16[] memory) {
        return _specsOf[wallet];
    }

    function verified(address claimant, uint16 traitId)
        external
        view
        returns (bytes32 requestId, bytes32 oracleRequestId, uint64 fromBlock, uint64 toBlock)
    {
        VerifiedEntry storage v = _verified[claimant][traitId];
        if (v.requestId == 0) return (0, 0, 0, 0);
        if (traitId == 601) return (v.requestId, v.oracleRequestId, v.fromBlock, v.toBlock);
        (, fromBlock, toBlock,) = _rule(traitId);
        return (v.requestId, v.oracleRequestId, fromBlock, toBlock);
    }

    /// @notice The name table (CATALOG.md section 7); a spec's name for community ids.
    function traitName(uint16 traitId) external view returns (string memory) {
        if (traitId >= FIRST_SPEC_ID) {
            if (_specs[traitId].kind == 0) revert NotAnOracleTrait(traitId);
            return _specs[traitId].name;
        }
        return renderer.traitName(traitId);
    }

    function _answerTypeOf(uint8 kind) internal pure returns (uint8) {
        if (kind == 1 || kind == 2) return 3;
        if (kind == 3) return 4;
        return 0;
    }

    /// @dev Kinds 1, 2 and 4 ask a 5 / 3 panel; kinds 3, 5 and 6 ask 11 / 7.
    function _panelOf(uint8 kind) internal pure returns (uint16, uint16) {
        return kind == 3 || kind == 5 || kind == 6 ? (PANEL_PANEL, PANEL_QUORUM) : (CHAIN_PANEL, CHAIN_QUORUM);
    }

    function _isDirect(uint16 id) internal pure returns (bool) {
        return id == 101 || id == 201 || id == 202 || (id >= 301 && id <= 303) || (id >= 401 && id <= 404)
            || (id >= 501 && id <= 503);
    }

    function _isCatalogChain(uint16 id) internal pure returns (bool) {
        return id == 701 || id == 801 || id == 901 || id == 1001 || (id >= 1101 && id <= 1105);
    }

    // ------------------------------------------------------------------ catalog as specs

    /// @notice The catalog oracle trait (601 to 1301) or the community spec behind an id, as a Spec.
    /// @dev A catalog id's spec is the Composer's answer returned as it came (no decode and re-encode here).
    function specOf(uint16 traitId) external view returns (Spec memory s) {
        if (traitId >= FIRST_SPEC_ID) return _spec(traitId);
        bytes memory ret = _catalogSpecRaw(traitId);
        assembly ("memory-safe") {
            return(add(ret, 0x20), mload(ret))
        }
    }

    /// @notice The exact body and the plane's `questionHash` for a trait and a claimant; free to call.
    function composeBody(uint16 traitId, address claimant)
        public
        view
        returns (bytes memory body, bytes32 questionHash)
    {
        Spec memory s;
        if (traitId >= FIRST_SPEC_ID) s = _spec(traitId);
        else _checkCatalogOracle(traitId);
        return composer.compose(traitId, s, claimant, address(this), address(curator));
    }

    function _spec(uint16 traitId) internal view returns (Spec memory s) {
        s = _specs[traitId];
        if (s.kind == 0) revert NotAnOracleTrait(traitId);
    }

    function _checkCatalogOracle(uint16 traitId) internal pure {
        if (!_isCatalogChain(traitId) && traitId != 1201 && traitId != 1301 && traitId != 601) {
            revert NotAnOracleTrait(traitId);
        }
    }

    /// @dev The ABI-encoded `Spec` of a catalog oracle trait, straight from the Composer.
    function _catalogSpecRaw(uint16 traitId) internal view returns (bytes memory ret) {
        _checkCatalogOracle(traitId);
        bool ok;
        (ok, ret) = address(composer).staticcall(abi.encodeCall(composer.catalogSpec, (traitId, address(curator))));
        if (!ok) revert NotAnOracleTrait(traitId);
    }

    // ------------------------------------------------------------------ upgrades (claimant pays)

    /// @notice k oracle requests for the caller, k x `priceOf`, each at most `maxPrice`.
    function upgrade(uint16[] calldata traitIds, uint256 maxPrice) external nonReentrant {
        uint256 k = traitIds.length;
        if (k == 0) revert NoTraits();
        uint256 price = _price(maxPrice);
        imd.safeTransferFrom(msg.sender, address(this), price * k);
        for (uint256 i; i < k; ++i) {
            uint16 id = traitIds[i];
            if (_isDirect(id)) revert NotAnOracleTrait(id);
            if (id == 1201) revert NotASharedFact(id);
            if (id >= FIRST_SPEC_ID) {
                uint8 kind = _specs[id].kind;
                if (kind == 0) revert NotAnOracleTrait(id);
                if (kind == 3) revert NotASharedFact(id);
            } else if (!_isCatalogChain(id) && id != 1301 && id != 601) {
                revert NotAnOracleTrait(id);
            }
            _request(msg.sender, id, price);
        }
    }

    /// @notice Releases an unanswered pair strictly after 31 days. Shared facts can be abandoned
    ///         by anyone; personal requests only by their claimant. Oracle prices are not refundable.
    function abandon(bytes32 requestId) external {
        Pending memory p = _pending[requestId];
        if (p.requestedAt == 0) revert NotPending(requestId);
        if (block.timestamp <= uint256(p.requestedAt) + ABANDON_AFTER) revert TooEarly();
        if (p.claimant != address(0) && msg.sender != p.claimant) revert NotClaimant();
        _clear(requestId, p);
        emit Abandoned(requestId);
    }

    function pendingRequest(bytes32 requestId)
        external
        view
        returns (address claimant, uint16 traitId, uint64 requestedAt, bytes32 questionHash)
    {
        Pending storage p = _pending[requestId];
        return (p.claimant, p.traitId, p.requestedAt, p.questionHash);
    }

    function _price(uint256 maxPrice) internal view returns (uint256 price) {
        price = intake.priceOf(ACTION, address(imd));
        if (price == 0) revert ZeroPrice();
        if (price > maxPrice) revert PriceAboveMax(price, maxPrice);
    }

    /// @dev Composes, pays the Intake from the registry's balance (already pulled from the caller) and
    ///      records the pending pair. `claimant == address(0)` is a shared fact paid by `msg.sender`.
    ///      Intake v2 pulls the fee inside `request` (`_collect`, `safeTransferFrom` in the same call), so
    ///      each call's `forceApprove` is consumed before the next one is set.
    function _request(address claimant, uint16 traitId, uint256 price) internal returns (bytes32 requestId) {
        if (claimant != address(0)) {
            if (_verified[claimant][traitId].requestId != 0) revert AlreadyVerified(claimant, traitId);
            if (pendingOf[claimant][traitId] != 0) revert AlreadyPending(claimant, traitId);
        } else {
            if (_shared[traitId].requestId != 0) revert FactAlreadyStored(traitId);
            if (sharedPending[traitId] != 0) revert AlreadyPending(claimant, traitId);
        }
        (bytes memory body, bytes32 qh) = composeBody(traitId, claimant);
        imd.forceApprove(address(intake), price);
        requestId = intake.requestWithFailure(
            ACTION,
            body,
            IIntake.Callback(address(this), this.onResult.selector),
            this.onFailure.selector,
            address(imd),
            price
        );
        if (_pending[requestId].requestedAt != 0) revert RequestIdTaken(requestId);
        (, uint64 fromBlock, uint64 toBlock,) = _rule(traitId);
        _pending[requestId] = Pending(claimant, traitId, uint64(block.timestamp), qh, fromBlock, toBlock);
        if (claimant != address(0)) pendingOf[claimant][traitId] = requestId;
        else sharedPending[traitId] = requestId;
        emit TraitRequested(claimant, traitId, requestId, qh);
    }

    /// @dev Clears a pending record and its reverse index only if the index still names this request.
    function _clear(bytes32 requestId, Pending memory p) internal {
        delete _pending[requestId];
        if (p.claimant != address(0)) {
            if (pendingOf[p.claimant][p.traitId] == requestId) delete pendingOf[p.claimant][p.traitId];
        } else if (sharedPending[p.traitId] == requestId) {
            delete sharedPending[p.traitId];
        }
    }

    // ------------------------------------------------------------------ Intake callbacks

    /// @notice Intake v2 `complete`, status 0. Never reverts on an envelope that decodes: every failed
    ///         check is a `Missed(requestId, traitId, reason)` and clears the pair.
    /// @dev    Clears first, then checks: the Intake completes a request exactly once and records a
    ///         callback revert as not delivered, so a retained record could only lock the pair until
    ///         `abandon`. A `Missed` request is over; its claimant may request again at once, and a
    ///         replay of a consumed attestation misses with reason 1.
    function onResult(bytes32 requestId, OracleAttestation calldata a, bytes calldata signature) external override {
        if (msg.sender != address(intake)) revert NotIntake();
        Pending memory p = _pending[requestId];
        if (p.requestedAt == 0) {
            emit Missed(requestId, 0, 1);
            return;
        }
        _clear(requestId, p);
        (uint8 kind,,, uint256 threshold) = _rule(p.traitId);
        uint8 reason = _check(p, a, signature, kind);
        if (reason == 0) reason = _decodeAndJudge(a, kind, threshold, p.claimant == address(0));
        if (reason != 0) {
            emit Missed(requestId, p.traitId, reason);
            return;
        }
        if (p.claimant == address(0)) {
            uint16 n = uint16(uint256(bytes32(a.answer[32:64])));
            _shared[p.traitId] = SharedFact(requestId, keccak256(a.answer), a.requestId, n);
            emit SharedFactStored(p.traitId, requestId, n);
            return;
        }
        _mark(p.claimant, p.traitId, requestId, a.requestId);
        if (p.traitId == 601) {
            _verified[p.claimant][601].fromBlock = p.fromBlock;
            _verified[p.claimant][601].toBlock = p.toBlock;
        }
    }

    /// @notice Intake v2 `complete`, status 1 (refused) or 2 (no verdict). Unsigned and Intake-attributed:
    ///         the plane documents no failure signature, so none is verified; the call clears the pair
    ///         and stores nothing, on a call from the Intake only.
    function onFailure(bytes32 requestId, uint8 status, bytes32 reason, uint16 agreed, uint16 answered, bytes calldata)
        external
        override
    {
        if (msg.sender != address(intake)) revert NotIntake();
        Pending memory p = _pending[requestId];
        if (p.requestedAt == 0) {
            emit Missed(requestId, 0, 1);
            return;
        }
        _clear(requestId, p);
        emit NoVerdict(requestId, p.traitId, status, reason, agreed, answered);
    }

    /// @dev The template's kind, canonical window and threshold for a pending trait or fact id.
    function _rule(uint16 traitId)
        internal
        view
        returns (uint8 kind, uint64 fromBlock, uint64 toBlock, uint256 threshold)
    {
        if (traitId >= FIRST_SPEC_ID) {
            Spec storage s = _specs[traitId];
            return (s.kind, s.fromBlock, s.toBlock, s.threshold);
        }
        if (traitId == 601) return (6, 25_090_085, uint64(block.number - 64), 3);
        if (traitId == 701) return (1, B_H24, B_END, 1);
        if (traitId == 1105) return (1, B_DEPLOY, B_FIRST1000, 1);
        if (traitId == 1201) return (3, B_DEPLOY, B_END, 32);
        if (traitId == 1301) return (5, B_DEPLOY, B_DEPLOY, 20);
        return (1, B_DEPLOY, B_END, 1);
    }

    /// @dev Bound calldata before any dynamic copy or hash, then validate in INTEGRATION.md order.
    function _check(Pending memory p, OracleAttestation calldata a, bytes calldata signature, uint8 kind)
        internal
        view
        returns (uint8)
    {
        if (signature.length != 65) return 2;
        if (a.answer.length > 2112 || (kind != 3 && a.answer.length != 32)) return 9;
        if (a.chainId != QUESTION_CHAIN_ID) return 3;
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly ("memory-safe") {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }
        (address signer, ECDSA.RecoverError err,) = ECDSA.tryRecover(attestationDigest(a), v, r, s);
        if (err != ECDSA.RecoverError.NoError || signer == address(0) || signer != attester) return 2;
        if (a.answerType != _answerTypeOf(kind)) return 4;
        (uint16 panelSize, uint16 quorum) = _panelOf(kind);
        if (a.agreed < a.quorum || a.quorum < quorum || a.panelSize < panelSize) return 5;
        if (a.fromBlock != p.fromBlock || a.toBlock != p.toBlock) return 6;
        if (
            block.timestamp > a.expiresAt || a.issuedAt > block.timestamp + ISSUED_AT_TOLERANCE
                || a.issuedAt < p.requestedAt || uint256(a.issuedAt) > uint256(p.requestedAt) + ISSUE_WINDOW
                || uint256(a.expiresAt) > uint256(a.issuedAt) + VALID_FOR_SECONDS
        ) return 7;
        if (a.questionHash != p.questionHash) return 10;
        return 0;
    }

    /// @dev Check 8: decode defensively, then the rule. Returns 9 (decode), 8 (rule false) or 0. A kind-3
    ///      answer is a complete list of exactly `threshold` (the head) addresses or it is a decode miss.
    function _decodeAndJudge(OracleAttestation calldata a, uint8 kind, uint256 threshold, bool shared)
        internal
        pure
        returns (uint8)
    {
        bytes calldata ans = a.answer;
        if (kind == 3) {
            if (!shared) return 9; // a T3 id never reaches a personal pending record
            if (ans.length < 64) return 9;
            if (uint256(bytes32(ans[0:32])) != 0x20) return 9;
            // V2 item 8: exactly `head` addresses (32 for 1201, the spec's threshold for a community T3).
            uint256 n = uint256(bytes32(ans[32:64]));
            if (n != threshold || ans.length != 64 + 32 * n) return 9;
            for (uint256 i; i < n; ++i) {
                if (uint256(bytes32(ans[64 + 32 * i:96 + 32 * i])) >> 160 != 0) return 9;
            }
            return 0;
        }
        // _check already required exactly one word for bool and uint256 kinds.
        uint256 word = uint256(bytes32(ans[0:32]));
        if (kind == 1 || kind == 2) return word >= threshold ? 0 : 8;
        if (word > 1) return 9;
        return word == 1 ? 0 : 8;
    }

    function _mark(address claimant, uint16 traitId, bytes32 requestId, bytes32 oracleRequestId) internal {
        _verified[claimant][traitId] = VerifiedEntry(requestId, oracleRequestId, 0, 0);
        if (traitId >= FIRST_SPEC_ID) _specsOf[claimant].push(traitId);
        emit Verified(claimant, traitId, requestId, oracleRequestId);
        uint256 tokenId = tokenOf[claimant];
        if (tokenId != 0) emit MetadataUpdate(tokenId);
    }

    /// @notice The EIP-712 digest this registry verifies: domain name "IdentityMD Oracle", version "2",
    ///         this chain, this registry as `verifyingContract`. Computed every time; no immutables.
    function attestationDigest(OracleAttestation calldata a) public view returns (bytes32) {
        bytes32 domainSeparator =
            keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, block.chainid, address(this)));
        bytes32 structHash = keccak256(
            bytes.concat(
                abi.encode(
                    ATTESTATION_TYPEHASH,
                    a.requestId,
                    a.chainId,
                    a.questionHash,
                    a.answerType,
                    keccak256(a.answer),
                    a.figure,
                    a.fromBlock
                ),
                abi.encode(
                    a.toBlock, a.blockHash, a.panelJobId, a.panelSize, a.quorum, a.agreed, a.issuedAt, a.expiresAt
                )
            )
        );
        return MessageHashUtils.toTypedDataHash(domainSeparator, structHash);
    }

    // ------------------------------------------------------------------ community specs

    /// @notice Registers an immutable community spec: 6.4 IMD forwarded to the BurnExecutor for bridging and burning on Base; ids from 10001.
    /// @param expectedId the id the caller expects (what `nextSpecId` read); 0 to take whatever is next.
    function registerSpec(Spec calldata spec, uint256 expectedId) external nonReentrant returns (uint16 traitId) {
        traitId = nextSpecId;
        if (expectedId != 0 && expectedId != traitId) revert UnexpectedSpecId(expectedId, traitId);
        composer.validateSpec(spec, block.number);
        imd.safeTransferFrom(msg.sender, burnExecutor, SPEC_FEE);
        nextSpecId = traitId + 1;
        _specs[traitId] = spec;
        emit SpecRegistered(traitId, msg.sender);
    }

    // ------------------------------------------------------------------ shared facts

    /// @notice One chain-proven question for a T3 id, paid once by the caller; no claimant.
    function requestSharedFact(uint16 factId, uint256 maxPrice) external nonReentrant {
        if (_kindOf(factId) != 3) revert NotASharedFact(factId);
        uint256 price = _price(maxPrice);
        imd.safeTransferFrom(msg.sender, address(this), price);
        _request(address(0), factId, price);
    }

    /// @notice Marks `msg.sender` for a stored fact if the supplied list hashes to the stored answer and
    ///         contains the caller (the list is exactly `head` long). Gas only; once per claimant and fact.
    function applySharedFact(uint16 factId, address[] calldata list) external {
        SharedFact storage f = _shared[factId];
        if (f.requestId == 0) revert FactNotStored(factId);
        if (keccak256(abi.encode(list)) != f.answerHash) revert ListMismatch();
        if (_verified[msg.sender][factId].requestId != 0) revert AlreadyVerified(msg.sender, factId);
        // a stored list is exactly `head` long (V2 item 8), so the whole of it counts
        bool found;
        for (uint256 i; i < f.length; ++i) {
            if (list[i] == msg.sender) {
                found = true;
                break;
            }
        }
        if (!found) revert NotInList();
        _mark(msg.sender, factId, f.requestId, f.oracleRequestId);
    }

    function sharedFact(uint16 factId) external view returns (bytes32 requestId, bytes32 answerHash, uint16 length) {
        SharedFact storage f = _shared[factId];
        return (f.requestId, f.answerHash, f.length);
    }

    function _kindOf(uint16 id) internal view returns (uint8) {
        if (id == 1201) return 3;
        if (id >= FIRST_SPEC_ID) return _specs[id].kind;
        return 0;
    }
}
