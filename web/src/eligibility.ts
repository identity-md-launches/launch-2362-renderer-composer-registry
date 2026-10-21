// Claim-guide guards: a button whose transaction the Registry would refuse is disabled, with the reason in words.
// A read that fails keeps the button disabled ("could not read, retry"); nothing is enabled by a default.
export type Guard = {ok:true} | {ok:false; reason:string};
export const OK:Guard = {ok:true};
export const WRONG_CHAIN = 'wrong chain';
export const READ_FAILED = 'could not read, retry';
export const DISCLAIMER_TEXT = 'I understand: an oracle price is spent whatever the answer, and a missed answer refunds nothing.';
export const DISCLAIMER_REASON = 'accept the oracle disclaimer first';

export type Reads = {verifiedIds:number[]; sharedVerified:boolean};
export type Context = {connected:boolean; chainId?:number; reads?:Reads; failed:boolean; loading?:boolean; acknowledged:boolean};
export const READING = 'reading eligibility…';


function base(c:Context):Guard|undefined {
 if(!c.connected)return undefined;
 if(c.chainId!==1)return {ok:false,reason:WRONG_CHAIN};
 if(c.failed)return {ok:false,reason:READ_FAILED};
 if(c.loading||!c.reads)return {ok:false,reason:READING};
 return undefined;
}
function oracleGate(c:Context):Guard|undefined {
 if(c.connected&&c.chainId!==1)return {ok:false,reason:WRONG_CHAIN};
 if(!c.acknowledged)return {ok:false,reason:DISCLAIMER_REASON};
 return base(c);
}
/** mintCard and applySharedFact: only the chain matters here; the flow re-checks AlreadyMinted before signing. */
export function plainGuard(c:Context):Guard {
 if(c.connected&&c.chainId!==1)return {ok:false,reason:WRONG_CHAIN};
 return OK;
}
/** upgrade(ids, maxPrice): refused when one selected id is already verified for the wallet. */
export function upgradeGuard(c:Context, selected:number[]):Guard {
 const first=oracleGate(c);if(first)return first;
 if(!c.connected)return OK;
 const done=selected.filter(id=>c.reads!.verifiedIds.includes(id));
 if(done.length)return {ok:false,reason:`already verified: ${done.join(', ')}`};
 return OK;
}
/** requestSharedFact(id, maxPrice): refused when the id is already verified for the wallet. */
export function sharedGuard(c:Context):Guard {
 const first=oracleGate(c);if(first)return first;
 if(!c.connected)return OK;
 if(c.reads!.sharedVerified)return {ok:false,reason:'already verified for this wallet'};
 return OK;
}
