import { createPublicClient, http, keccak256, parseAbi, encodeAbiParameters, parseAbiParameters, pad, encodeFunctionData, decodeFunctionResult, type Abi, type Address, type PublicClient, type Hex } from 'viem';
import { mainnet } from 'viem/chains';
import { A, address, registryAbi, rendererAbi, curatorAbi, erc20Abi, ACTION } from './config';
import { CATALOG, topOf } from './catalog';
import { decodeMetadata } from './format';

export class DeploymentMismatch extends Error {}
export class RpcUnavailable extends Error { constructor(){super('RPC unavailable. Choose another public RPC and retry.');} }
export type Reader = PublicClient;
export const rpcClient = (url:string) => createPublicClient({chain:mainnet,transport:http(url,{timeout:12000,retryCount:0,batch:{batchSize:12,wait:15}})}) as Reader;
export async function withRpc<T>(selected:string, run:(client:Reader)=>Promise<T>):Promise<T> {
 for (const url of [selected,...A.publicRpcs.filter(u=>u!==selected)]) {
  try {
   const client=rpcClient(url);
   if (await client.getChainId()!==1) continue;
   return await run(client);
  } catch(error) { if(error instanceof DeploymentMismatch) throw error; }
 }
 throw new RpcUnavailable();
}
export async function read<T>(client:Reader, target:Address, abi:Abi, functionName:string, args:readonly unknown[]=[],blockNumber?:bigint):Promise<T> {
 return client.readContract({address:target,abi,functionName,args,blockNumber}) as Promise<T>;
}
export const reg = <T>(c:Reader, fn:string,args:readonly unknown[]=[],blockNumber?:bigint) => read<T>(c,address('Registry'),registryAbi,fn,args,blockNumber);
export type Integrity = {block:bigint; getters:Record<string,string>; endpoint:string};
const integrityCache=new Map<string,{at:number;result:Integrity}>();
export async function integrity(client:Reader,force=false):Promise<Integrity> {
 const endpoint=client.transport.url??'';
 const cached=integrityCache.get(endpoint);
 if(!force&&cached&&Date.now()-cached.at<60000)return cached.result;
 const block=await client.getBlockNumber({cacheTime:0});
 const names=['curator','imd','intake','renderer','composer','burnExecutor','attester'];
 const expected=[A.WhitelistCurator,A.IMD,A.IntakeV2,A.Renderer,A.Composer,A.BurnExecutorV2,A.attester];
 const values=await Promise.all(names.map(fn=>reg<string>(client,fn,[],block)));
 names.forEach((fn,i)=>{if(values[i].toLowerCase()!==expected[i].toLowerCase()) throw new DeploymentMismatch(`${fn}() differs from site/addresses.json. Transactions are disabled.`);});
 await Promise.all((['Registry','Renderer','Composer'] as const).map(async name=>{
  const code=await client.getCode({address:address(name),blockNumber:block});
  if (!code || keccak256(code)!==A.runtimeHashes[name]) throw new DeploymentMismatch(`${name} deployed code differs from the launch source. Transactions are disabled.`);
 }));
 const result={block,getters:Object.fromEntries(names.map((fn,i)=>[fn,values[i]])),endpoint};
 integrityCache.set(endpoint,{at:Date.now(),result});return result;
}
const intakeAbi=parseAbi(['function priceOf(bytes32,address) view returns (uint256)']);
export const livePrice=(c:Reader,blockNumber?:bigint)=>read<bigint>(c,address('IntakeV2'),intakeAbi,'priceOf',[ACTION,address('IMD')],blockNumber);
export type Verified = {id:number; requestId:Hex;oracleRequestId:Hex;fromBlock:bigint;toBlock:bigint};
export type Snapshot = {
 wallet:Address;block:bigint;endpoint:string;traits:number[];specs:number[];tokenId:bigint;
 firstHour:bigint;joined:boolean;txCount:bigint;capital:bigint;points:bigint;
 price:bigint;image:string;rawMetadata:string;metadata:ReturnType<typeof decodeMetadata>['metadata'];
 verified:Verified[];pending:Record<number,Hex>;
};
export async function explore(selected:string,wallet:Address):Promise<Snapshot> {
 return withRpc(selected,async client=>{
  await integrity(client);
  const block=await client.getBlockNumber({cacheTime:0});
  const [truths,specs,tokenId,hour,txCount,capital,points,price] = await Promise.all([
   Promise.all(CATALOG.map(t=>reg<boolean>(client,'hasTrait',[wallet,t.id],block))),
   reg<readonly number[]>(client,'verifiedSpecsOf',[wallet],block),reg<bigint>(client,'tokenOf',[wallet],block),
   read<readonly [bigint,boolean]>(client,address('WhitelistCurator'),curatorAbi,'firstHourOf',[wallet],block),
   read<bigint>(client,address('WhitelistCurator'),curatorAbi,'txCountOf',[wallet],block),
   read<bigint>(client,address('WhitelistCurator'),curatorAbi,'contributedBy',[wallet],block),
   read<bigint>(client,address('WhitelistCurator'),curatorAbi,'pointsOf',[wallet],block),
   livePrice(client,block),
  ]);
  const traits=CATALOG.filter((_,i)=>truths[i]).map(t=>t.id);
  const oracle=CATALOG.filter(t=>t.id>=601);
  const [verified,pairs]=await Promise.all([
   Promise.all([...traits.filter(id=>id>=601),...specs].map(async id=>{
    const v=await reg<readonly [Hex,Hex,bigint,bigint]>(client,'verified',[wallet,id],block);
    return {id,requestId:v[0],oracleRequestId:v[1],fromBlock:v[2],toBlock:v[3]};
   })),
   Promise.all(oracle.map(async t=>[t.id,await reg<Hex>(client,'pendingOf',[wallet,t.id],block)] as const)),
  ]);
  const uri=tokenId!==0n ? await reg<string>(client,'tokenURI',[tokenId],block) : await previewWallet(client,wallet,block);
  const {metadata,raw}=decodeMetadata(uri);
  return {wallet,block,endpoint:client.transport.url??selected,traits,specs:[...specs],tokenId,firstHour:hour[0],joined:hour[1],txCount,capital,points,price,image:metadata.image,rawMetadata:raw,metadata,verified,pending:Object.fromEntries(pairs)};
 });
}
/** Renderer exposes tokenURIOf only. A read-only claimantOf override lets it draw
 * the wallet's real traits without minting. All other code and storage stay live.
 * Slot 15 is compiler-derived for this source (docs/preview.md).
 */
export async function previewWallet(client:Reader,wallet:Address,block:bigint){
 const next=await reg<bigint>(client,'totalSupply',[],block)+1n;
 const slot=keccak256(encodeAbiParameters(parseAbiParameters('uint256,uint256'),[next,15n]));
 const result=await client.call({to:address('Renderer'),data:encodeFunctionData({abi:rendererAbi,functionName:'tokenURIOf',args:[address('Registry'),next]}),blockNumber:block,gas:16000000n,stateOverride:[{address:address('Registry'),stateDiff:[{slot,value:pad(wallet,{size:32})}]}]});
 if(!result.data)throw new RpcUnavailable();
 return decodeFunctionResult({abi:rendererAbi,functionName:'tokenURIOf',data:result.data}) as string;
}
