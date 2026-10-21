// Optional live-network verification. No transaction leaves this local Anvil
// fork; only documented public contributors and the synthetic wallet are used.
import { spawn } from 'node:child_process';
import { writeFile, mkdir } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { encodeFunctionData, type Address } from 'viem';
import { A, SYNTHETIC, CONTRIBUTORS, registryAbi, address } from '../src/config.ts';
import { rpcClient, integrity, livePrice, explore, reg, type Reader } from '../src/chain.ts';
import { newJournal, runStep, friendlyError, type Plan } from '../src/flow.ts';
import { quoteExactImd } from '../src/swap.ts';
import type { Wallet } from '../src/wallet.ts';

const endpoint='http://127.0.0.1:18545';
const upstream=process.env.SWORN_FORK_RPC??A.publicRpcs[0];
const block=await rpcClient(upstream).getBlockNumber({cacheTime:0});
const processNode=spawn('anvil',['--fork-url',upstream,'--fork-block-number',String(block),'--port','18545','--chain-id','1','--accounts','0','--no-storage-caching','--no-fork-node-info','--silent'],{stdio:['ignore','ignore','pipe']});
let stderr='';processNode.stderr.on('data',d=>stderr+=String(d));
const session=new Map<string,string>();
Object.defineProperty(globalThis,'sessionStorage',{value:{getItem:(k:string)=>session.get(k)??null,setItem:(k:string,v:string)=>session.set(k,v),removeItem:(k:string)=>session.delete(k)}});
async function rpc(method:string,params:unknown[]=[]):Promise<unknown>{const response=await fetch(endpoint,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({jsonrpc:'2.0',id:1,method,params})});const j=await response.json();if(j.error)throw Error(JSON.stringify(j.error));return j.result;}
const results:{name:string;details:unknown}[]=[];
function passed(name:string,details:unknown){console.log('PASS',name,details);results.push({name,details});}
let client:Reader;
async function wallet(account:Address):Promise<Wallet>{await rpc('anvil_impersonateAccount',[account]);await rpc('anvil_setBalance',[account,'0x56bc75e2d63100000']);return {account,chainId:1,epoch:1,provider:{request:({method,params})=>method==='eth_accounts'?Promise.resolve([account]):rpc(method,(params??[]) as unknown[])}};}
async function execute(plan:Plan,w:Wallet,payment:'IMD'|'ETH'='ETH'){
 const j=newJournal(plan,payment);
 if(plan.amount>0n){
  if(payment==='ETH')await runStep(client,w,j,'swap',()=>{},await quoteExactImd(client,plan.amount));
  await runStep(client,w,j,'approve',()=>{});
 }
 const receipt=await runStep(client,w,j,'registry',()=>{});
 assert.equal(j.steps.registry?.state,'confirmed');
 return {j,receipt};
}
try{
 let ready=false;
 for(let i=0;i<100;i++){
  try{if(await rpc('eth_chainId')==='0x1'){ready=true;break;}}catch{}
  if(processNode.exitCode!==null)throw Error(stderr||'Anvil exited');
  await new Promise(r=>setTimeout(r,200));
 }
 assert(ready,'Anvil did not become ready');client=rpcClient(endpoint);await integrity(client);passed('launch code and getters on the local mainnet fork',{block:String(block)});
 const w=await wallet(SYNTHETIC);
 const preMint=await explore(endpoint,SYNTHETIC);assert.equal(preMint.tokenId,0n);assert(preMint.image.startsWith('data:image/svg+xml,'));passed('Explorer lookup before mint decodes a live Renderer preview',{traits:preMint.traits,tokenId:String(preMint.tokenId)});
 const amount=100000000000000000n;const q=await quoteExactImd(client,amount);const j=newJournal({key:'fork-mint',label:'Synthetic mint',data:encodeFunctionData({abi:registryAbi,functionName:'mintCard'}),amount},'ETH');
 const before=await client.getBalance({address:SYNTHETIC});
 const swapped=await runStep(client,w,j,'swap',()=>{},q);assert(swapped);
 const after=await client.getBalance({address:SYNTHETIC});
 const spent=before-after-swapped.gasUsed*swapped.effectiveGasPrice;
 assert(spent>0n&&spent<q.maxInput,'Unused ETH must be returned by the canonical router sweep');
 passed('one exact-output canonical Router swap, exact IMD receipt, unused ETH returned',{maximumWei:String(q.maxInput),actualWei:String(spent),returnedWei:String(q.maxInput-spent),exactImd:String(amount)});
 await runStep(client,w,j,'approve',()=>{});await runStep(client,w,j,'registry',()=>{});
 const minted=await explore(endpoint,SYNTHETIC);assert(minted.tokenId>0n);assert.equal(minted.metadata.name,`Sworn #${minted.tokenId}`);
 passed('exact approval and mint, Registry.tokenURI for a minted wallet',{tokenId:String(minted.tokenId),traits:minted.traits});
 const price=await livePrice(client);
 const upgrade=await execute({key:'fork-upgrade',label:'Synthetic panel request',data:encodeFunctionData({abi:registryAbi,functionName:'upgrade',args:[[1301],price]}),amount:price,maxPrice:price},w);
 assert(upgrade.j.outcomes?.some(v=>v.includes('1301 requested')));assert.equal(await reg<boolean>(client,'hasTrait',[SYNTHETIC,1301]),false);
 passed('paid panel request with live maxPrice; pending does not become a true fact',{price:String(price),outcomes:upgrade.j.outcomes});
 const spec={kind:5,target:A.poolKey.currency0,item:'',arg:'',fixedArg:'',fixedVal:0n,sumArg:'',op:0,threshold:20n,fromBlock:25769870n,toBlock:25769870n,name:'Synthetic nonce'};
 const registered=await execute({key:'fork-register',label:'Synthetic spec',data:encodeFunctionData({abi:registryAbi,functionName:'registerSpec',args:[spec,BigInt(await reg<number>(client,'nextSpecId'))]}),amount:6400000000000000000n,spec:true},w);
 assert(registered.j.registeredId&&registered.j.registeredId>=10001);passed('community registration derives id from its own SpecRegistered receipt',{traitId:registered.j.registeredId});
 const member=await wallet(CONTRIBUTORS[0].address as Address);const preview=await explore(endpoint,member.account);assert(preview.joined);assert.equal(preview.tokenId,0n);assert(preview.image.startsWith('data:image/svg+xml,'));
 passed('unminted public contributor gets a pure Renderer preview',{traits:preview.traits,tokenId:String(preview.tokenId)});
}finally{
 processNode.kill('SIGTERM');await new Promise<void>(r=>{if(processNode.exitCode!==null)r();else processNode.once('exit',()=>r());});
 await mkdir('test/scratch',{recursive:true});await writeFile('test/scratch/fork-results.json',JSON.stringify({upstream,block:String(block),localOnly:true,results},null,2)+'\n');
}
