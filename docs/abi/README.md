# Implementation ABIs

Registry.json, Composer.json and Renderer.json are the complete `abi` arrays from the pinned compiler artifacts under `out/<Contract>.sol/<Contract>.json`. Regenerate them after `forge build` with `python3 tools/export_abis.py`; use `--check` to verify committed copies. The two web ABI copies contain the same arrays. These are source ABIs, not a signed deployment handoff; the service supplies confirmed addresses and artifact linkage separately.

Renderer and Composer have no constructor arguments. Registry takes seven addresses in order: curator, imd, intake, attester, renderer, composer, burnExecutor. README.md supplies the approved mainnet values. No constructor is payable and none creates another contract.

Registry writes: mintCard(), upgrade(uint16[],uint256 maxPrice), registerSpec(Spec,uint256 expectedId), requestSharedFact(uint16,uint256 maxPrice), applySharedFact(uint16,address[]), abandon(bytes32), and standard ERC-721 transfer/approval functions. All Registry writes are nonpayable. Oracle callbacks onResult and onFailure accept only Intake as caller. Miss reasons and the canonical 15-field attestation are documented in INTEGRATION.md.

Credential reads: hasTrait, hasDirectTrait, traitsOf, verified, verifiedSpecsOf, claimantOf, tokenOf, frozenDirect, mintedAtBlock, totalSupply, pendingRequest, pendingOf, sharedPending and sharedFact. `verified` returns Intake id, oracle UUID and the accepted from/to window. `pendingRequest` retains its four-field public shape; the additional stored window is internal. specOf and composeBody expose the immutable rule/body; querying 601 before verification computes its next request window.

Composer views accept trusted inputs: validateSpec checks registration grammar and windows; compose builds the body and hash; catalogSpec returns catalog parameters; directSnapshot(wallet,curator) returns thirteen Curator bits. Kind 6 is catalog-only. Renderer exposes traitName and tokenURIOf(registry,tokenId); a caller-supplied rendering is not itself a credential.
