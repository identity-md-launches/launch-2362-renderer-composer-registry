import test from 'node:test';
import assert from 'node:assert/strict';
import { encodeAbiParameters, encodeFunctionData, encodeEventTopics, parseAbiItem, parseAbiParameters, type Address, type Hex } from 'viem';
import { A, SYNTHETIC, registryAbi } from '../src/config';
import { type Reader } from '../src/chain';
import { confirmStep, loadJournal, newJournal, runStep, validateIntent, type Journal } from '../src/flow';
import type { Wallet } from '../src/wallet';
import { poolId } from '../src/swap';
import runtime from './fixtures/runtime.json';

const hash=(n:string)=>('0x'+n.repeat(64)) as Hex;
const mintData=encodeFunctionData({abi:registryAbi,functionName:'mintCard'});
const amount=100000000000000000n;
function mock(){
 const memory=new Map<string,string>();Object.defineProperty(globalThis,'sessionStorage',{configurable:true,value:{getItem:(k:string)=>memory.get(k)??null,setItem:(k:string,v:string)=>memory.set(k,v),removeItem:(k:string)=>memory.delete(k)}});
 const state={sent:0,reject:false,broadcastUnknown:false,wait:'success',amount:0n,fee:100n,failPreview:false,allowance:amount,tokenId:0n,verified:false,pending:hash('0'),logs:[] as unknown[],abortDuringEstimate:undefined as (()=>void)|undefined};
 let transaction={from:SYNTHETIC,to:A.IMD as Address,input:'0x' as Hex,value:0n};
 const controller=new AbortController();
 const wallet:Wallet={account:SYNTHETIC,chainId:1,epoch:1,signal:controller.signal,provider:{request:async({method,params})=>{
  if(method==='eth_chainId')return '0x1';if(method==='eth_accounts')return [SYNTHETIC];
  if(method==='eth_sendTransaction'){
   state.sent++;
   if(state.reject)throw Object.assign(Error('User rejected'),{code:4001});
   if(state.broadcastUnknown)throw Error('Network disconnected after broadcast');
   const tx=(params as {to:Address;data:Hex;value:Hex}[])[0];transaction={from:SYNTHETIC,to:tx.to,input:tx.data,value:BigInt(tx.value)};return hash('1');
  }
  throw Error(`Unexpected wallet method ${method}`);
 }}};
 const getters:Record<string,string>={curator:A.WhitelistCurator,imd:A.IMD,intake:A.IntakeV2,renderer:A.Renderer,composer:A.Composer,burnExecutor:A.BurnExecutorV2,attester:A.attester};
 const client={
  transport:{url:'test:synthetic-transport'},getBlockNumber:async()=>26217852n,
  getCode:async({address}:{address:string})=>{const name=(['Registry','Renderer','Composer'] as const).find(n=>A[n]===address.toLowerCase());if(!name)throw Error('Unexpected code address');return runtime[name];},
  readContract:async({functionName}:{functionName:string})=>functionName in getters?getters[functionName]:functionName==='balanceOf'?10n**19n:functionName==='allowance'?state.allowance:functionName==='priceOf'?500000000000000000n:functionName==='tokenOf'?state.tokenId:functionName==='hasTrait'?state.verified:functionName==='pendingOf'?state.pending:0n,
  call:async({to}:{to:string})=>{
   return {data:'0x'};
  },
  simulateContract:async()=>({}),estimateGas:async()=>{state.abortDuringEstimate?.();return 200000n;},
  waitForTransactionReceipt:async({onReplaced}:{onReplaced?:(value:unknown)=>void})=>{
   if(state.wait==='timeout')throw Error('Timed out waiting for a receipt');
   const receipt={status:state.wait==='reverted'?'reverted':'success',transactionHash:hash(state.wait==='repriced'||state.wait==='cancelled'?'2':'1'),logs:state.logs};
   if(state.wait==='repriced'||state.wait==='cancelled'){
    if(state.wait==='cancelled')transaction={...transaction,to:SYNTHETIC,input:'0x'};
    onReplaced?.({reason:state.wait==='cancelled'?'cancelled':'repriced',transactionReceipt:receipt});
   }
   return receipt;
  },
  getTransaction:async()=>transaction,
 } as unknown as Reader;
 const journal=newJournal({key:'mint',label:'Synthetic test mint',data:mintData,amount},'IMD');
 return {client,wallet,journal,state,memory,controller};
}
test('stored intent cannot change the exact approval amount or Registry operation',()=>{
 const {journal}=mock();validateIntent(journal);
 assert.throws(()=>validateIntent({...journal,amount:'100000000000000001'}),/does not match/);
 assert.throws(()=>validateIntent({...journal,data:encodeFunctionData({abi:registryAbi,functionName:'abandon',args:[hash('0')]})}),/Unsupported/);
});
test('an existing card stops before an approval or an ETH swap',async()=>{
 for(const phase of ['approve','swap'] as const){const m=mock();m.state.tokenId=1n;const j=newJournal({key:'mint',label:'Synthetic mint',data:mintData,amount},phase==='swap'?'ETH':'IMD');await assert.rejects(runStep(m.client,m.wallet,j,phase,()=>{}),/AlreadyMinted/);assert.equal(m.state.sent,0);}
});
test('verified or pending facts stop before buying IMD',async()=>{
 for(const pending of [false,true]){const m=mock();m.state.verified=!pending;m.state.pending=pending?hash('3'):hash('0');const price=500000000000000000n;const j=newJournal({key:'paid',label:'Synthetic request',data:encodeFunctionData({abi:registryAbi,functionName:'upgrade',args:[[1301],price]}),amount:price,maxPrice:price},'ETH');await assert.rejects(runStep(m.client,m.wallet,j,'swap',()=>{}),pending?/AlreadyPending/:/AlreadyVerified/);assert.equal(m.state.sent,0);}
});
test('wallet rejection is resumable and does not send a Registry call',async()=>{
 const m=mock();m.state.reject=true;
 await assert.rejects(runStep(m.client,m.wallet,m.journal,'approve',()=>{}),/rejected/);
 assert.equal(m.state.sent,1);assert.equal(m.journal.steps.approve?.state,'rejected');assert.equal(m.journal.steps.registry,undefined);
 m.state.reject=false;await runStep(m.client,m.wallet,m.journal,'approve',()=>{});assert.equal(m.journal.steps.approve?.state,'confirmed');
});
test('pending receipt survives reload and checking it sends no second transaction',async()=>{
 const m=mock();m.state.wait='timeout';await assert.rejects(runStep(m.client,m.wallet,m.journal,'approve',()=>{}),/Timed out/);
 const restored=loadJournal()!;assert.equal(restored.steps.approve?.state,'pending');assert.equal(m.state.sent,1);
 m.state.wait='success';await runStep(m.client,m.wallet,restored,'approve',()=>{});assert.equal(m.state.sent,1);assert.equal(restored.steps.approve?.state,'confirmed');
 assert(!JSON.stringify(restored).includes(SYNTHETIC),'The journal stores no wallet identity or connection');
});
test('an unknown broadcast is never repeated after reload',async()=>{
 const m=mock();m.state.broadcastUnknown=true;
 const journal=newJournal({key:'mint',label:'Synthetic ETH mint',data:mintData,amount},'ETH');
 const quote={amountOut:amount,amountIn:100n,maxInput:101n,quotedAt:Date.now(),block:26217852n,poolId};
 await assert.rejects(runStep(m.client,m.wallet,journal,'swap',()=>{},quote),/Network disconnected/);
 const restored=loadJournal()!;assert.equal(restored.steps.swap?.state,'unknown');
 await assert.rejects(runStep(m.client,m.wallet,restored,'swap',()=>{}),/may already have been broadcast/);assert.equal(m.state.sent,1);
});
test('a repriced transaction is confirmed from the replacement receipt',async()=>{
 const m=mock();m.state.wait='repriced';await runStep(m.client,m.wallet,m.journal,'approve',()=>{});
 assert.equal(m.journal.steps.approve?.state,'confirmed');assert.equal(m.journal.steps.approve?.hash,hash('2'));
});
test('a cancellation is a failed step and cannot advance to the Registry',async()=>{
 const m=mock();m.state.wait='cancelled';await assert.rejects(runStep(m.client,m.wallet,m.journal,'approve',()=>{}),/replacement changed/);
 assert.equal(m.journal.steps.approve?.state,'failed');assert.equal(m.journal.steps.registry,undefined);
});
test('a reverted transaction never advances',async()=>{
 const m=mock();m.state.wait='reverted';await assert.rejects(runStep(m.client,m.wallet,m.journal,'approve',()=>{}),/failed onchain/);
 assert.equal(m.journal.steps.approve?.state,'failed');assert.equal(m.journal.steps.registry,undefined);
});
test('a wallet change during estimation drops the stale transaction before signing',async()=>{
 const m=mock();m.state.abortDuringEstimate=()=>m.controller.abort();
 await assert.rejects(runStep(m.client,m.wallet,m.journal,'approve',()=>{}),/Wallet session changed/);assert.equal(m.state.sent,0);
});
test('a Registry call cannot pass an unconfirmed approval',async()=>{
 const m=mock();await assert.rejects(runStep(m.client,m.wallet,m.journal,'registry',()=>{}),/Confirm the exact approval receipt first/);assert.equal(m.state.sent,0);
});
test('a changed live oracle price stops the flow before buying or approving',async()=>{
 const m=mock();const price=400000000000000000n;
 const j=newJournal({key:'paid',label:'Synthetic upgrade',data:encodeFunctionData({abi:registryAbi,functionName:'upgrade',args:[[1301],price]}),amount:price,maxPrice:price},'ETH');
 await assert.rejects(runStep(m.client,m.wallet,j,'swap',()=>{}),/oracle price changed/);assert.equal(m.state.sent,0);
});

test('Registry payment uses zero native value',async()=>{const m=mock();await runStep(m.client,m.wallet,m.journal,'approve',()=>{});await runStep(m.client,m.wallet,m.journal,'registry',()=>{});assert.equal(m.journal.steps.registry?.value,'0');});
