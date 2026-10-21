import { decodeEventLog, decodeFunctionData, encodeFunctionData, parseAbiItem, type Address, type Hex, type TransactionReceipt } from 'viem';
import { A, address, registryAbi, erc20Abi, deployment } from './config';
import { assertWallet, send, type Wallet } from './wallet';
import { reg, read, integrity, livePrice, type Reader } from './chain';
import { quoteExactImd, swapCalldata, type SwapQuote } from './swap';
import { units } from './format';
import { CHAIN_IDS } from './catalog';

export type Plan={key:string;label:string;data:Hex;amount:bigint;maxPrice?:bigint;spec?:boolean;shared?:boolean};
export type Phase='swap'|'approve'|'registry';
export type StepState='ready'|'awaiting wallet'|'pending'|'confirmed'|'rejected'|'failed'|'replaced'|'unknown';
export type Journal={version:1;deploymentId:string;key:string;label:string;data:Hex;amount:string;maxPrice?:string;spec?:boolean;payment:'IMD'|'ETH';steps:Partial<Record<Phase,{state:StepState;hash?:Hex;data?:Hex;to?:Address;value?:string}>>;registeredId?:number;outcomes?:string[]};
const JOURNAL_KEY='sworn.transaction.'+deployment.launchId;
export function loadJournal():Journal|undefined {
 try {
  const v=JSON.parse(sessionStorage.getItem(JOURNAL_KEY)??'null');
  if(v?.version!==1||v.deploymentId!==deployment.launchId||!['IMD','ETH'].includes(v.payment)||!/^\d+$/.test(v.amount)||!/^0x[0-9a-fA-F]+$/.test(v.data)||!v.steps)return;
  const decoded=decodeFunctionData({abi:registryAbi,data:v.data});
  if(!['mintCard','upgrade','registerSpec','requestSharedFact','applySharedFact'].includes(decoded.functionName))return;
  return v as Journal;
 }catch{return;}
}
export function saveJournal(j:Journal){sessionStorage.setItem(JOURNAL_KEY,JSON.stringify(j));}
export function clearJournal(){sessionStorage.removeItem(JOURNAL_KEY);}
export function newJournal(plan:Plan,payment:'IMD'|'ETH'):Journal {return {version:1,deploymentId:deployment.launchId,key:plan.key,label:plan.label,data:plan.data,amount:plan.amount.toString(),maxPrice:plan.maxPrice?.toString(),spec:plan.spec,payment,steps:{}};}
export function validateIntent(journal:Journal){
 const call=decodeFunctionData({abi:registryAbi,data:journal.data});
 const args=call.args as readonly unknown[]|undefined;
 let amount:bigint;let maxPrice:bigint|undefined;let spec=false;
 if(journal.deploymentId!==deployment.launchId)throw new Error('Stored flow belongs to another deployment.');
 if(call.functionName==='mintCard')amount=100000000000000000n;
 else if(call.functionName==='registerSpec'){amount=6400000000000000000n;spec=true;}
 else if(call.functionName==='upgrade'){maxPrice=args![1] as bigint;amount=BigInt((args![0] as unknown[]).length)*maxPrice;}
 else if(call.functionName==='requestSharedFact'){maxPrice=args![1] as bigint;amount=maxPrice;}
 else if(call.functionName==='applySharedFact')amount=0n;
 else throw new Error('Unsupported Registry operation in the recovered flow.');
 if(BigInt(journal.amount)!==amount || (journal.maxPrice===undefined?undefined:BigInt(journal.maxPrice))!==maxPrice || !!journal.spec!==spec)throw new Error('The stored intent does not match its Registry calldata. Review the flow before signing.');
}
async function checkEligibility(client:Reader,wallet:Wallet,journal:Journal){
 const call=decodeFunctionData({abi:registryAbi,data:journal.data});
 const args=call.args as readonly unknown[]|undefined;
 if(call.functionName==='mintCard'){
  if(await reg<bigint>(client,'tokenOf',[wallet.account])!==0n)throw new Error('AlreadyMinted');
 }else if(call.functionName==='upgrade'){
  for(const id of args![0] as number[]){
   if(id<10001&&!CHAIN_IDS.includes(id)&&id!==1301&&id!==601)throw new Error('Choose a catalog chain id, 601, 1301 or a personal community spec. Shared facts use request/apply.');
   if(id>=10001){const spec=await reg<{kind:number}>(client,'specOf',[id]);if(![1,2,4,5].includes(spec.kind))throw new Error('Shared community specs use the shared request/apply procedure.');}
   const [verified,pending]=await Promise.all([reg<boolean>(client,'hasTrait',[wallet.account,id]),reg<Hex>(client,'pendingOf',[wallet.account,id])]);
   if(verified)throw new Error('AlreadyVerified');
   if(!/^0x0+$/.test(pending))throw new Error('AlreadyPending');
  }
 }else if(call.functionName==='registerSpec'){
  const expected=args![1] as bigint;const next=await reg<number>(client,'nextSpecId');if(BigInt(next)!==expected)throw new Error('UnexpectedSpecId');
 }else if(call.functionName==='requestSharedFact'){
  const id=args![0] as number;
  if(id!==1201){const spec=await reg<{kind:number}>(client,'specOf',[id]);if(spec.kind!==3)throw new Error('This community spec is personal. Use a paid upgrade.');}
  const [fact,pending]=await Promise.all([reg<readonly[Hex,Hex,number]>(client,'sharedFact',[id]),reg<Hex>(client,'sharedPending',[id])]);
  if(!/^0x0+$/.test(fact[0]))throw new Error('This shared fact is already stored. Apply the attested list for gas.');
  if(!/^0x0+$/.test(pending))throw new Error('AlreadyPending');
 }
}
const registeredEvent=parseAbiItem('event SpecRegistered(uint16 indexed traitId,address indexed registrant)');
export function registeredId(receipt:Pick<TransactionReceipt,'logs'>,registrant:Address) {
 const ids:number[]=[];
 for(const log of receipt.logs){
  if(log.address.toLowerCase()!==A.Registry)continue;
  try {const e=decodeEventLog({abi:[registeredEvent],data:log.data,topics:log.topics});if(e.args.registrant.toLowerCase()===registrant.toLowerCase())ids.push(e.args.traitId);}catch{/* Other registry event. */}
 }
 if(ids.length!==1)throw new Error('This receipt does not contain one SpecRegistered event for this wallet.');
 return ids[0];
}
export function receivedImd(receipt:Pick<TransactionReceipt,'logs'>,recipient:Address) {
 let amount=0n;
 for(const log of receipt.logs){
  if(log.address.toLowerCase()!==A.IMD)continue;
  try {const e=decodeEventLog({abi:erc20Abi,eventName:'Transfer',data:log.data,topics:log.topics});if(e.eventName==='Transfer' && e.args.to?.toLowerCase()===recipient.toLowerCase())amount+=e.args.value??0n;}catch{/* Non-transfer event. */}
 }
 return amount;
}
export function friendlyError(error:unknown) {
 const raw=error instanceof Error ? error.message : String(error);
 const cases:[string,string][]=[
  ['ZeroPrice','The live Intake price is zero. Requests are unavailable until it changes.'],
  ['UnexpectedSpecId','Another registration took the reviewed id. Prepare the spec again to review the next id.'],
  ['AlreadyPending','This trait already has a pending request. Check it in Explorer.'],
  ['AlreadyVerified','This fact is already verified. Check it in Explorer.'],
  ['AlreadyMinted','This wallet already minted its card. Open Explorer.'],
  ['PriceAboveMax','The oracle price changed. Refresh prices and prepare a new request.'],
  ['BadSpec','The spec does not meet the template rules. Check its name, ABI item, exact threshold and historical window, then try again.'],
  ['NotASharedFact','This id is not a shared fact. Use a paid upgrade for community kinds 1, 2, 4 and 5.'],
  ['NotInList','The connected wallet is not in the attested head of this shared list. Check the original answer.'],
  ['4001','Transaction rejected in the wallet. You can try this step again.'],
  ['User rejected','Transaction rejected in the wallet. You can try this step again.'],
  ['insufficient funds','Insufficient funds for the amount and gas. Add funds or choose a different payment method.'],
 ];
 return cases.find(([key])=>raw.includes(key))?.[1] ?? (raw.length>240 ? raw.slice(0,240) : raw);
}
type Update=(j:Journal,message?:string)=>void;
export async function confirmStep(client:Reader,wallet:Wallet,journal:Journal,phase:Phase,update:Update) {
 const entry=journal.steps[phase];
 if(!entry?.hash)throw new Error('No transaction hash is known. Check wallet activity and recover its hash. This flow will not repeat a swap.');
 const receipt=await client.waitForTransactionReceipt({hash:entry.hash,confirmations:1,timeout:45000,onReplaced(replacement){
  entry.hash=replacement.transactionReceipt.transactionHash;
  entry.state=replacement.reason==='cancelled' ? 'failed' : 'replaced';
  saveJournal(journal);update({...journal},replacement.reason==='cancelled'?'Transaction cancelled.':'Replacement detected. Checking its calldata.');
 }});
 await assertWallet(wallet);
 const tx=await client.getTransaction({hash:receipt.transactionHash});
 if(tx.from.toLowerCase()!==wallet.account.toLowerCase())throw new Error('Receipt belongs to another account. Reconnect its original wallet to continue. No next step was sent.');
 if(tx.to?.toLowerCase()!==entry.to?.toLowerCase() || tx.input!==entry.data || tx.value!==BigInt(entry.value??'0')){entry.state='failed';saveJournal(journal);update({...journal});throw new Error('The confirmed replacement changed the transaction. No next step was sent. Review wallet activity before clearing this flow.');}
 if(receipt.status!=='success'){entry.state='failed';saveJournal(journal);update({...journal});throw new Error('Transaction failed onchain. No next step was sent.');}
 if(phase==='swap' && receivedImd(receipt,wallet.account)!==BigInt(journal.amount))throw new Error('Exact IMD receipt check failed. No approval or Registry call was sent.');
 if(phase==='approve'){
  const allowance=await read<bigint>(client,address('IMD'),erc20Abi,'allowance',[wallet.account,address('Registry')]);
  if(allowance!==BigInt(journal.amount))throw new Error('Exact allowance check failed. No Registry call was sent.');
 }
 if(phase==='registry'){
  if(journal.spec)journal.registeredId=registeredId(receipt,wallet.account);
  journal.outcomes=[];
  for(const log of receipt.logs){
   if(log.address.toLowerCase()!==A.Registry)continue;
   try{
    const decoded=decodeEventLog({abi:registryAbi,data:log.data,topics:log.topics});const args=decoded.args as unknown as Record<string,unknown>;
    if(decoded.eventName==='CardMinted')journal.outcomes.push(`Card minted: token ${String(args.tokenId)}. Open Explorer to read its live metadata.`);
    if(decoded.eventName==='TraitRequested')journal.outcomes.push(`Trait ${String(args.traitId)} requested. The oracle verdict is pending.`);
   }catch{/* Unrelated or unsupported event. */}
  }
 }
 entry.state='confirmed';saveJournal(journal);update({...journal},phase==='registry'?'Registry transaction confirmed. Read the receipt outcomes below.':'Receipt confirmed. Continue to the next step.');
 return receipt;
}
export async function runStep(client:Reader,wallet:Wallet,journal:Journal,phase:Phase,update:Update,quote?:SwapQuote) {
 validateIntent(journal);
 await assertWallet(wallet);await integrity(client,true);
 if(journal.steps[phase]?.state==='confirmed')throw new Error('This step is already confirmed.');
 if(journal.steps[phase]?.hash)return confirmStep(client,wallet,journal,phase,update);
 if(journal.steps[phase]?.state==='awaiting wallet' || journal.steps[phase]?.state==='unknown')throw new Error('This transaction may already have been broadcast. Recover its hash before continuing.');
 const amount=BigInt(journal.amount);
 // Re-read preceding receipts after reload or reconnect; a stored status is not evidence.
 if(phase!=='swap' && journal.payment==='ETH' && amount>0n && journal.steps.swap?.state==='confirmed')await confirmStep(client,wallet,journal,'swap',update);
 if(phase==='registry' && amount>0n && journal.steps.approve?.state==='confirmed')await confirmStep(client,wallet,journal,'approve',update);
 if(journal.maxPrice && await livePrice(client)!==BigInt(journal.maxPrice))throw new Error('The oracle price changed. Prepare a new flow with the exact current IMD amount. Confirmed swaps are never repeated automatically.');
 if(phase==='swap'||phase==='approve')await checkEligibility(client,wallet,journal);
 let tx:{to:Address;data:Hex;value?:bigint;gas?:bigint};
 if(phase==='swap'){
  if(journal.payment!=='ETH' || amount===0n)throw new Error('No swap is needed.');
  const q=quote??await quoteExactImd(client,amount);
  if(q.amountOut!==amount)throw new Error('The selected operation changed. Prepare the flow again.');
  tx=swapCalldata(q,wallet.account);
 } else if(phase==='approve'){
  if(journal.payment==='ETH' && journal.steps.swap?.state!=='confirmed')throw new Error('Confirm the swap receipt first.');
  const balance=await read<bigint>(client,address('IMD'),erc20Abi,'balanceOf',[wallet.account]);
  if(balance<amount)throw new Error('Insufficient IMD. Fund the wallet or prepare a pay-with-ETH flow.');
  tx={to:address('IMD'),data:encodeFunctionData({abi:erc20Abi,functionName:'approve',args:[address('Registry'),amount]})};
 } else {
  if(amount>0n && journal.steps.approve?.state!=='confirmed')throw new Error('Confirm the exact approval receipt first.');
  tx={to:address('Registry'),data:journal.data,value:0n};
 }
 await assertWallet(wallet);
 // Simulate precisely what the wallet will be asked to sign before opening it.
 if(tx.to.toLowerCase()===A.Registry){
  const decoded=decodeFunctionData({abi:registryAbi,data:tx.data});
  await client.simulateContract({account:wallet.account,address:tx.to,abi:registryAbi,functionName:decoded.functionName,args:decoded.args,value:tx.value??0n});
 }else await client.call({account:wallet.account,to:tx.to,data:tx.data,value:tx.value??0n});
 const estimated=await client.estimateGas({account:wallet.account,to:tx.to,data:tx.data,value:tx.value??0n});
 tx.gas=(estimated*125n+99n)/100n;
 await assertWallet(wallet);
 const entry={state:'awaiting wallet' as StepState,to:tx.to,data:tx.data,value:(tx.value??0n).toString()};
 journal.steps[phase]=entry;saveJournal(journal);update({...journal},'Review the transaction in your wallet.');
 try {
  const hash=await send(wallet,tx);
  Object.assign(entry,{hash,state:'pending'});saveJournal(journal);update({...journal},'Transaction pending. Wait for its receipt before continuing.');
  return await confirmStep(client,wallet,journal,phase,update);
 } catch(error) {
  if(!('hash' in entry)){
   const code=(error as {code?:number}).code;
   entry.state=code===4001 || /reject|denied/i.test(String(error)) ? 'rejected' : 'unknown';
   saveJournal(journal);update({...journal});
  }
  throw error;
 }
}
