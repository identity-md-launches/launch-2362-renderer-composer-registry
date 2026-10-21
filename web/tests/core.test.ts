import test from 'node:test';
import assert from 'node:assert/strict';
import { decodeAbiParameters, decodeFunctionData, encodeAbiParameters, encodeEventTopics, parseAbiParameters, parseAbiItem, type Address, type TransactionReceipt } from 'viem';
import { CATALOG, FAMILIES, CHAIN_IDS, isRare, topOf } from '../src/catalog';
import { A, SYNTHETIC } from '../src/config';
import { decodeMetadata, attestationUrl, number, units } from '../src/format';
import { receivedImd, registeredId, friendlyError } from '../src/flow';
import { assertWallet, type Provider } from '../src/wallet';
import { POOL_TYPE, poolId, routerAbi, slippageMaximum, swapCalldata } from '../src/swap';

test('the frozen catalog contains 25 unique ids and 13 final family names',()=>{
 assert.equal(CATALOG.length,25);assert.equal(new Set(CATALOG.map(t=>t.id)).size,25);assert.equal(FAMILIES.length,13);assert.equal(CHAIN_IDS.length,9);
 assert.deepEqual(CATALOG.filter(t=>isRare(t.id)).map(t=>t.id),[202,801,901,1001,1101,1102,1103,1104,1201]);
});
test('card summary uses highest tiers, except the lowest verified PID',()=>{
 const top=topOf([101,201,202,301,303,1105,1103,1101]);assert.equal(top[1],202);assert.equal(top[2],303);assert.equal(top[10],1101);assert.equal(top[5],0);
});
test('metadata integers retain exact decimal lexemes beyond 2^53 and at uint256 max',()=>{
 const exact=(2n**256n-1n).toString();const raw=`{"name":"Sworn #1","image":"data:image/svg+xml,%3Csvg%2F%3E","oracle":[{"fixedVal":9007199254740993,"threshold":${exact}}]}`;
 const uri='data:application/json;base64,'+btoa(raw);const result=decodeMetadata(uri);
 assert.equal(result.metadata.oracle![0].fixedVal,'9007199254740993');assert.equal(result.metadata.oracle![0].threshold,exact);assert.equal(result.raw,raw);
});
test('attestation links use the first sixteen bytes of oracleRequestId',()=>{
 assert.equal(attestationUrl('0x1234567890abcdef1234567890abcdef'+'aa'.repeat(16)),'https://api.imd.fun/oracle/requests/12345678-90ab-cdef-1234-567890abcdef/attestation');
 assert.equal(attestationUrl('0x'+'0'.repeat(64)),undefined);
});
test('amounts always format as en-US without floating-point conversion',()=>{
 assert.equal(number(12345678901234567890n),'12,345,678,901,234,567,890');assert.equal(units(1234500000000000000000n),'1,234.5');assert.equal(units(1n),'0.000000000000000001');
});
test('exact-output calldata pins route, recipients, output, slippage maximum and deadline',()=>{
 const now=1700000000000;const quote={amountOut:100000000000000000n,amountIn:101n,maxInput:103n,quotedAt:now,block:1n,poolId};
 assert.equal(slippageMaximum(101n),103n);
 const tx=swapCalldata(quote,SYNTHETIC,now);assert.equal(tx.to,A.UniversalRouter);assert.equal(tx.value,103n);assert.equal(tx.chainId,1);
 const decoded=decodeFunctionData({abi:routerAbi,data:tx.data});assert.equal(decoded.functionName,'execute');
 const [commands,inputs,deadline]=decoded.args as readonly [`0x${string}`,readonly `0x${string}`[],bigint];assert.equal(commands,'0x1004');assert.equal(deadline,1700000120n);
 const [actions,params]=decodeAbiParameters(parseAbiParameters('bytes,bytes[]'),inputs[0]);assert.equal(actions,'0x080c0e');
 const [swap]=decodeAbiParameters(parseAbiParameters(`(${POOL_TYPE} poolKey,bool zeroForOne,uint128 amountOut,uint128 amountInMaximum,bytes hookData)`),params[0]);
 assert.equal(swap.amountOut,quote.amountOut);assert.equal(swap.amountInMaximum,103n);assert.equal(swap.zeroForOne,true);assert.equal(swap.poolKey.currency1.toLowerCase(),A.IMD);assert.equal(swap.poolKey.hooks.toLowerCase(),A.CappedBurnHook);
 const [takeToken,takeTo,takeAmount]=decodeAbiParameters(parseAbiParameters('address,address,uint256'),params[2]);assert.equal(takeToken.toLowerCase(),A.IMD);assert.equal(takeTo.toLowerCase(),SYNTHETIC);assert.equal(takeAmount,quote.amountOut);
 const [refundToken,refundTo,minimum]=decodeAbiParameters(parseAbiParameters('address,address,uint256'),inputs[1]);assert.equal(refundToken,A.poolKey.currency0);assert.equal(refundTo.toLowerCase(),SYNTHETIC);assert.equal(minimum,0n);
 assert.throws(()=>swapCalldata(quote,SYNTHETIC,now+30001),/expired/);
 assert.throws(()=>swapCalldata({...quote,maxInput:104n},SYNTHETIC,now),/changed/);
});
const log=(address:string,topics:readonly string[],data:string)=>({address,topics,data}) as TransactionReceipt['logs'][number];
test('community id is taken only from this receipt and the connected registrant',()=>{
 const event=parseAbiItem('event SpecRegistered(uint16 indexed traitId,address indexed registrant)');
 const topics=encodeEventTopics({abi:[event],eventName:'SpecRegistered',args:{traitId:10042,registrant:SYNTHETIC}});
 const receipt={logs:[log(A.Registry,topics as string[],'0x')]};
 assert.equal(registeredId(receipt,SYNTHETIC),10042);
 assert.throws(()=>registeredId({logs:[log(A.IMD,topics as string[],'0x')]},SYNTHETIC),/does not contain/);
 assert.throws(()=>registeredId(receipt,A.Registry as Address),/does not contain/);
});
test('swap verification counts only transfers of IMD to the pinned recipient',()=>{
 const event=parseAbiItem('event Transfer(address indexed from,address indexed to,uint256 value)');
 const topics=encodeEventTopics({abi:[event],eventName:'Transfer',args:{from:A.PoolManager as Address,to:SYNTHETIC}});
 const data=encodeAbiParameters(parseAbiParameters('uint256'),[100n]);
 assert.equal(receivedImd({logs:[log(A.IMD,topics as string[],data),log(A.Registry,topics as string[],data)]},SYNTHETIC),100n);
});
test('wrong chain and changed account are rejected before any send',async()=>{
 const provider:Provider={request:async({method})=>method==='eth_chainId'?'0x89':[SYNTHETIC]};
 await assert.rejects(assertWallet({provider,account:SYNTHETIC,chainId:1,epoch:0}),/Wrong chain/);
 provider.request=async({method})=>method==='eth_chainId'?'0x1':[A.Registry];
 await assert.rejects(assertWallet({provider,account:SYNTHETIC,chainId:1,epoch:0}),/Account changed/);
});

test('current request errors explain how to retry',()=>{ for(const name of ['ZeroPrice','UnexpectedSpecId'])assert.notEqual(friendlyError(Error(name)),name); });
