// Production export at a subpath. Reads use the configured public RPC; SWORN_RPC
// may provide an operator transport locally. No mainnet transaction is sent.
import {createServer} from 'node:http';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import {resolve,extname,sep} from 'node:path';
import {pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
import {toFunctionSelector} from 'viem';
const {chromium}=await import(process.env.IMD_PLAYWRIGHT?pathToFileURL(process.env.IMD_PLAYWRIGHT).href:'playwright');
const root=resolve('dist'),out=resolve('test/scratch/live-browser');await mkdir(out,{recursive:true});
const config=JSON.parse(await readFile(resolve(root,'imd-deployment.json'),'utf8'));
const network=JSON.parse(await readFile('web/network.json','utf8'));
const upstream=process.env.SWORN_RPC??config.network.rpcUrls[0];
const server=createServer(async(req,res)=>{const path=decodeURIComponent((req.url??'').split('?')[0]);const file=resolve(root,path.replace(/^\/preview\//,''));if(!path.startsWith('/preview/')||!file.startsWith(root+sep)){res.writeHead(404);res.end();return;}try{const data=await readFile(file);res.setHeader('Content-Type',({'.html':'text/html','.js':'application/javascript','.css':'text/css','.svg':'image/svg+xml','.json':'application/json','.png':'image/png'})[extname(file)]??'text/plain');res.end(data);}catch{res.writeHead(404);res.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const url=`http://127.0.0.1:${server.address().port}/preview/index.html`;
const browser=await chromium.launch({headless:true});const results=[];const errors=[];
const publicRpc=url=>config.network.rpcUrls.some(r=>String(url).startsWith(r));
async function routeLive(context){await context.route(publicRpc,async route=>{const response=await fetch(upstream,{method:'POST',headers:{'Content-Type':'application/json'},body:route.request().postData()});await route.fulfill({status:response.status,contentType:'application/json',body:await response.text()});});}
async function unavailable(route){const body=route.request().postDataJSON();const calls=Array.isArray(body)?body:[body];const responses=calls.map(c=>({jsonrpc:'2.0',id:c.id,error:{code:-32000,message:'Deliberate unavailable-RPC test'}}));await route.fulfill({contentType:'application/json',body:JSON.stringify(Array.isArray(body)?responses:responses[0])});}
const account='0x200e710acaa6a93bbc77146026328c40f1d60fb1';
function record(name,details){results.push({name,passed:true,details});console.log('PASS',name);}
try{
 const context=await browser.newContext({viewport:{width:1280,height:900},locale:'fr-FR'});await routeLive(context);const page=await context.newPage();page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
 await page.goto(`${url}#/explorer?address=${account}`);await page.locator('.explorer-grid').waitFor({timeout:60000});await page.waitForFunction(()=>document.querySelector('.explorer-card img')?.naturalWidth>0);
 assert.equal(await page.getByRole('region',{name:'13-family wallet summary'}).locator('tbody tr').count(),13);assert.equal(await page.getByRole('region',{name:'Every hasTrait result'}).locator('tbody tr').count(),25);
 assert((await page.locator('.explorer-card figcaption').innerText()).includes('preview, no card minted'));
 assert((await page.locator('main').innerText()).includes('0.5 IMD'));record('Live public-contributor lookup: 25 hasTrait reads, 13 families, lossless metadata and deployed Renderer preview',{status:await page.locator('.read-status').innerText()});
 await page.screenshot({path:resolve(out,'explorer-live-1280.png')});await page.setViewportSize({width:390,height:844});await page.screenshot({path:resolve(out,'explorer-live-390.png')});
 const rows=await page.getByRole('region',{name:'Every hasTrait result'}).locator('tbody tr').allTextContents();assert(rows.slice(14).every(row=>row.includes('not claimed')&&!/\bfalse\b/.test(row)));record('Unclaimed oracle rows never imply a false verdict');
 await context.route(publicRpc,unavailable);await page.goto(`${url}#/explorer?address=0x000000000000000000000000000000000000c1a1`);await page.locator('.read-status').filter({hasText:'RPC unavailable'}).waitFor({timeout:30000});assert.equal(await page.locator('.explorer-grid').count(),0);await page.getByRole('button',{name:'Retry reads',exact:true}).click();await page.locator('.read-status').filter({hasText:'RPC unavailable'}).waitFor();record('RPC failure clears results and offers retry');await context.close();
 const walletContext=await browser.newContext({viewport:{width:390,height:844}});await routeLive(walletContext);
 await walletContext.addInitScript(({account})=>{
  window.__walletCalls=[];window.__walletChain=localStorage.getItem('test.wallet.chain')??'0x89';window.__reject=true;window.__added=false;
  const make=(name)=>{const events={};return {request:async({method,params})=>{window.__walletCalls.push({name,method,params});if(method==='wallet_requestPermissions')throw {code:4200,message:'Unsupported'};if(method==='eth_requestAccounts'){if(window.__reject)throw {code:4001,message:'User rejected'};localStorage.setItem('test.wallet.auth.'+name,'1');return [account];}if(method==='eth_accounts')return localStorage.getItem('test.wallet.auth.'+name)?[account]:[];if(method==='eth_chainId')return window.__walletChain;if(method==='wallet_switchEthereumChain'){if(!window.__added)throw {code:4902,message:'Unknown chain'};window.__walletChain=params[0].chainId;localStorage.setItem('test.wallet.chain',window.__walletChain);(events.chainChanged??[]).forEach(fn=>fn(window.__walletChain));return null;}if(method==='wallet_addEthereumChain'){window.__added=true;return null;}if(method==='wallet_revokePermissions')return null;if(method==='eth_sendTransaction')throw Error('No transaction may be sent by this test');throw Error('Unsupported '+method);},on:(event,fn)=>(events[event]??=[]).push(fn),removeListener:(event,fn)=>{events[event]=(events[event]??[]).filter(f=>f!==fn);}};};
  const announce=()=>['MetaMask test','Rabby test'].forEach((name,i)=>window.dispatchEvent(new CustomEvent('eip6963:announceProvider',{detail:{info:{uuid:`verified-test-provider-${i}`,name,rdns:`test.wallet${i}`,icon:'data:image/svg+xml,%3Csvg xmlns="http://www.w3.org/2000/svg"/%3E'},provider:providers[i]}})));
  const providers=[make('MetaMask test'),make('Rabby test')];window.addEventListener('eip6963:requestProvider',announce);announce();
 },{account});
 const w=await walletContext.newPage();w.on('pageerror',e=>errors.push(e.message));await w.goto(`${url}#/claim`);await w.getByRole('button',{name:'Connect',exact:true}).click();
 assert.equal(await w.getByRole('button',{name:'Browser wallet',exact:true}).count(),0);await w.getByRole('button',{name:'MetaMask test',exact:true}).click();await w.getByRole('dialog').getByText('Connection declined or unavailable.',{exact:false}).waitFor();record('EIP-6963 names both extensions, hides generic row, handles rejected connection');
 await w.evaluate(()=>{window.__reject=false;});await w.getByRole('button',{name:'Rabby test',exact:true}).click();await w.getByRole('button',{name:'Switch to Ethereum',exact:true}).waitFor();assert.equal(await w.getByRole('button',{name:'Mint card',exact:true}).isEnabled(),false);
 await w.getByRole('button',{name:'Switch to Ethereum',exact:true}).click();await w.getByRole('button',{name:/Disconnect$/}).waitFor();
 const calls=await w.evaluate(()=>window.__walletCalls);assert.deepEqual(calls.find(c=>c.method==='wallet_addEthereumChain').params,[network.walletAddChain]);assert.equal(calls.filter(c=>c.method==='eth_sendTransaction').length,0);
 record('Wrong chain blocks mint; switch falls back to exact wallet_addEthereumChain handoff');
 await w.reload();await w.getByRole('button',{name:/Disconnect$/}).waitFor();assert.equal(await w.evaluate(()=>window.__walletCalls.filter(c=>c.method==='eth_requestAccounts').length),0);record('Previously authorized wallet reconnects on reload without requesting a signature');
 await w.getByRole('button',{name:'Refresh live prices',exact:true}).click();await w.locator('#oracle-disclaimer').check();
 await w.getByRole('button',{name:/Disconnect$/}).click();await w.getByRole('button',{name:'Connect',exact:true}).waitFor();record('Disconnect clears connected controls');await walletContext.close();
 const mobile=await browser.newContext({viewport:{width:390,height:844},isMobile:true,userAgent:'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1'});await mobile.route(publicRpc,unavailable);const p=await mobile.newPage();await p.goto(`${url}#/claim`);await p.getByRole('button',{name:'Connect',exact:true}).click();for(const name of ['MetaMask','Coinbase Wallet','Rabby','Phantom'])assert.equal(await p.getByRole('link',{name:`Open in ${name}`,exact:true}).count(),1);assert.equal(await p.getByRole('button',{name:'Coinbase Smart Wallet',exact:true}).count(),1);assert.equal(await p.getByRole('button',{name:'Browser wallet',exact:true}).count(),0);await p.screenshot({path:resolve(out,'phone-wallet-picker-390.png')});record('Phone bottom sheet offers four in-wallet links and Coinbase Smart Wallet');await mobile.close();
 assert.deepEqual(errors,[]);record('Live pages and wallet interactions have no console or script errors');
}finally{await browser.close();await new Promise(r=>server.close(r));await writeFile(resolve(out,'results.json'),JSON.stringify({results,errors},null,2)+'\n');}
