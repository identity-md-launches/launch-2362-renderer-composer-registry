# Sworn: wallet facts

A Sworn card is a transferable portrait of its original claimant's facts. It is never an identity credential for a later holder. A wallet can mint once, and may request facts before or after minting. There is no owner, upgrade path, pause or privileged claim.

The thirteen direct Curator predicates describe a settled historical game. They read live until mint, then freeze in the card's bitset. Bit 20 is unused. Every other catalog fact requires an oracle answer. T1 counts logs, T2 sums fields, T3 ranks a shared list, T4 compares a historical call, T5 checks a historical account nonce, and T6 establishes Swarmed's seat-operation record. Community specs support T1 through T5. Names, arguments and signature grammar are bounded before any community registration.

Swarmed counts accepted feedback entries while the claimant held a seat, with an agent binding at or before each entry. Former and later holders can each establish their own record; neither consumes the other's eligibility. It counts entries, not unique job identifiers. The request fixes the historical window and the accepted entry keeps it. Missing archive data is no verdict, never evidence of falsehood.

A request pays the Intake and records the expected question hash and window. Intake delivers once under a 200,000-gas stipend. Registry authenticates sender, signature, panel, exact window, bounded dates, question and answer, clears pending state and either stores a fact or emits a miss. The callback never transfers funds. Shared answers store a list hash under the stipend; each member later applies that exact list. Partial lists are refused.

Mint costs 0.1 IMD and registration costs 6.4 IMD. Fees are forwarded to the BurnExecutor V2 for bridging and burning on Base. Personal and shared requests pay the live Intake price separately. No action in Registry accepts ETH. Its own payment flows leave no IMD balance behind; unsolicited token transfers to the address cannot be prevented or recovered.

An oracle request is not refundable. If its answer never arrives, a claimant may abandon a personal request strictly after 31 days; anyone may clear an expired shared request. The date bounds ensure no valid delivery and permitted abandonment share a second. A request id cannot overwrite another live request, and a late delivery cannot clear its successor. False or invalid answers allow another paid attempt.

Once accepted, a fact is permanent, including after its attestation expires. The design relies on the oracle's single signer, fixed protocol, evidence sources and availability. It offers neither cryptographic proof of off-chain truth nor administrative recovery. See DISCLOSURE.md and INTEGRATION.md for operational limits.
