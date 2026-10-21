// Round 2 (owner review 2026-10-18): one test per numbered item of the two IPFS continuation bodies.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { BUILT_BY_SWARM, NO_COIN, WHY_SWORN } from '../src/components';
import { CATALOG } from '../src/catalog';
import { DISCLAIMER_REASON, DISCLAIMER_TEXT, READ_FAILED, WRONG_CHAIN, plainGuard, sharedGuard, upgradeGuard, type Context, type Reads } from '../src/eligibility';
import { BANDS, bandOf, wholeEth } from '../src/pages';

const src=(name:string)=>readFileSync(new URL(`../src/${name}`,import.meta.url),'utf8');

test('item 1: hours.json carries per-hour ETH and the three bands equal the census figures',()=>{
 const census=JSON.parse(readFileSync(new URL('../public/data/hours.json',import.meta.url),'utf8'));
 assert.equal(census.hours.length,66);assert(census.hours.every((h:{wei:string})=>/^\d+$/.test(h.wei)));
 const [a,b,c]=BANDS.map(([,from,to])=>bandOf(census.hours,from,to));
 assert.deepEqual([a.deposits,a.contributors,wholeEth(a.wei)],[22395,15620,'114,291']);
 assert.deepEqual([b.deposits,b.contributors,wholeEth(b.wei)],[5073,3095,'12,846']);
 assert.deepEqual([c.deposits,c.contributors,wholeEth(c.wei)],[885,807,'994']);
 const all=bandOf(census.hours,0,65);assert.deepEqual([all.deposits,all.contributors,wholeEth(all.wei)],[28353,19522,'128,131']);
 assert.equal(all.wei,BigInt(census.wei));
 assert(src('pages.tsx').includes('Hour 24 is the cliff')&&src('pages.tsx').includes('Hour 65 holds the last deposit'));
});
test('items 2 to 4: the owner copy is word for word and the paraphrases are gone',()=>{
 assert.equal(WHY_SWORN,'WhitelistCurator.sol set out to curate a permissionless onchain allowlist of proven wallets, for mints, early access, airdrops or reputation, that a contract reads directly at mint time, with no merkle root and no snapshot. Its 66-hour game recorded 19,522 wallets that kept paying real gas, hour after hour, in a quiet market, and it left the reading of that record to builders. Sworn is built on it: it turns the record into facts any contract can check with hasTrait, so a mint or a grant can use the signal without indexing the list itself. Some facts are read live from the Curator, the rest are proven by the swarm, and anyone can add more.');
 assert.equal(BUILT_BY_SWARM,"The contracts were built, audited and deployed by Identity.md's swarm in paid jobs, and so was this site. The job records are public.");
 assert.equal(NO_COIN,'Sworn has no coin of its own; its only token is the card.');
 const pages=src('pages.tsx');const components=src('components.tsx');
 for(const gone of ['no Merkle root to publish','Contracts, evidence and this interface are public','Sworn was built through the IdentityMD contributor network','Sworn issues no coin'])assert(!pages.includes(gone)&&!components.includes(gone),`paraphrase still present: ${gone}`);
 // Landing and About both render WHY SWORN and BUILT BY THE SWARM; About renders NO COIN.
 assert.equal((pages.match(/<WhySworn\/>/g)??[]).length,2);assert.equal((pages.match(/\{BUILT_BY_SWARM\}/g)??[]).length,2);assert.equal((pages.match(/\{NO_COIN\}/g)??[]).length,1);
});
const reads=():Reads=>({verifiedIds:[],sharedVerified:false});
const ctx=(over:Partial<Context>={}):Context=>({connected:true,chainId:1,reads:reads(),failed:false,acknowledged:true,...over});
test('item 5: the oracle disclaimer gates paid upgrade and shared request, never the mint or the apply',()=>{
 assert.equal(DISCLAIMER_TEXT,'I understand: an oracle price is spent whatever the answer, and a missed answer refunds nothing.');
 const unchecked=ctx({acknowledged:false});
 assert.equal((upgradeGuard(unchecked,[701]) as {reason:string}).reason,DISCLAIMER_REASON);
 assert.equal((sharedGuard(unchecked) as {reason:string}).reason,DISCLAIMER_REASON);
 assert.deepEqual(plainGuard(unchecked),{ok:true});
 const claim=src('Claim.tsx');assert(claim.includes('id="oracle-disclaimer"')&&claim.includes('useState(false);const [eligTick'),'unchecked on load');
});
test('item 6: a payment choice precedes each of the four paying buttons in document order',()=>{
 const claim=src('Claim.tsx');
 const order=[...claim.matchAll(/<PaymentChoice [^>]*name="(\w+)"|>(Mint card|Prepare paid upgrade|Prepare shared request|Prepare spec registration)</g)].map(m=>m[1]??m[2]);
 assert.deepEqual(order,['mint','Mint card','upgrade','Prepare paid upgrade','shared','Prepare shared request','spec','Prepare spec registration']);
 assert(!claim.includes('name="payment"'),'the single choice above the flow is gone');
});
test('body 2, item 1: 25 single-trait cards and the empty card exist, rendered by the Renderer and recorded',()=>{
 const dir=new URL('../public/assets/traits/',import.meta.url);
 const files=readdirSync(dir).sort();
 assert.deepEqual(files,[...CATALOG.map(t=>`${t.id}.svg`),'empty.svg'].sort());
 for(const f of files){const size=statSync(new URL(f,dir)).size;assert(size>1000&&size<8000,`${f}: ${size} bytes`);assert(readFileSync(new URL(f,dir),'utf8').startsWith('<svg'));}
 const record=JSON.parse(readFileSync(new URL('../../docs/renderer-assets.json',import.meta.url),'utf8'));
 for(const t of CATALOG){const r=record.assets.find((r:{name:string})=>r.name===String(t.id));assert(r&&r.adapterCodeHash?.startsWith('0x')&&r.traits.length===1&&r.traits[0]===t.id,`record ${t.id}`);}
 assert(record.assets.find((r:{name:string;traits:number[]})=>r.name==='empty'&&r.traits.length===0));
 // The rare ids carry the white dot (Renderer._rare): their cards differ from a non-rare card of the same family by a dot element.
 const dot=(id:number)=>(readFileSync(new URL(`${id}.svg`,dir),'utf8').match(/<circle/g)??[]).length;
 for(const id of [202,801,901,1001,1101,1102,1103,1104,1201])assert(dot(id)>dot(101),`rare ${id} shows no extra dot`);
});
test('body 2, items 2 and 3: MiniCards sit beside the 01 direct select and each 02 oracle row, About and Fact vs artifact',()=>{
 const claim=src('Claim.tsx');const pages=src('pages.tsx');const components=src('components.tsx');
 assert(claim.includes('id="direct-id"') && claim.includes('<MiniCard id={Number(direct)}/>'));
 assert(/trait-picker[^]*?<MiniCard id=\{t\.id\}\/>/.test(claim));
 assert.equal((pages.match(/<CardPair\/>/g)??[]).length,2);
 assert(components.includes('on an empty card')&&components.includes('The card is the artifact. The fact belongs to the wallet'));
 const mini=components.slice(components.indexOf('export function MiniCard'),components.indexOf('export function CardPair'));assert(!mini.includes('fetch(')&&!mini.includes('withRpc')&&!components.includes('createPublicClient'),'no runtime render for a preview');
});
