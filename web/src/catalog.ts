export type Evidence = 'direct' | 'chain-proven' | 'shared' | 'panel';
export type Trait = {id:number; family:number; name:string; evidence:Evidence; rule:string; window:string; population:string; getter:string};
export const FAMILIES = ['Spawned','Zero-Shot','Hopper','Bullfrog','Benchmarked','Swarmed','Uptime','Holdout','Final Token','Hotfix','PID','Top Weights','Pretrained'];
const t = (id:number,name:string,evidence:Evidence,rule:string,window:string,population:string,getter:string):Trait => ({id,family:Math.floor(id/100),name,evidence,rule,window,population,getter});
export const CATALOG: Trait[] = [
 t(101,'Spawned','direct','firstHourOf(A).hasJoined','live','19,522','firstHourOf'),
 t(201,'Zero-Shot, hour <= 1','direct','hasJoined && hour <= 1','live','516','firstHourOf'),
 t(202,'Zero-Shot, hour 0','direct','hasJoined && hour == 0','live','96','firstHourOf'),
 ...[3,5,10].map((n,i)=>t(301+i,`Hopper >= ${n}`,'direct',`txCountOf(A) >= ${n}`,'live','view; <= 2,037 repeat depositors','txCountOf')),
 ...[1,10,100,800].map((n,i)=>t(401+i,`Bullfrog >= ${n} ETH`,'direct',`contributedBy(A) >= ${n} ETH; largest single send`,'live','15,576-wallet sample; median 0.45 ETH','contributedBy')),
 ...['1,000','3,162','10,000'].map((n,i)=>t(501+i,`Benchmarked >= ${n}`,'direct',`pointsOf(A) >= ${n}`,'live','read from view; no frozen count','pointsOf')),
 t(601,'Swarmed','panel','operated a seat through 3 accepted swarm jobs','25,090,085 to request block minus 64','847 qualifying agents measured 2026-10-21','verified'),
 t(701,'Uptime','chain-proven','Deposited(contributor = A), count >= 1','W_JUDGED','3,936','verified'),
 t(801,'Holdout','chain-proven','Deposited(contributor = A, hour = 64)','W_LIFE','7','verified'),
 t(901,'Final Token','chain-proven','Deposited(contributor = A, hour = 65)','W_LIFE','1','verified'),
 t(1001,'Hotfix','chain-proven','HourSaved(savior = A), count >= 1','W_LIFE','33','verified'),
 ...[1,1000,10000,19522].map((n,i)=>t(1101+i,`PID #${n.toLocaleString('en-US')}`,'chain-proven',`FirstDeposit(contributor = A, index = ${n.toLocaleString('en-US')})`,'W_LIFE','1 each','verified')),
 t(1105,'First thousand','chain-proven','FirstDeposit(contributor = A), count >= 1','W_FIRST1000','1,000','verified'),
 t(1201,'Top Weights','shared','Top 32 contributors by summed weightAdded','W_LIFE','32','verified / sharedFact'),
 t(1301,'Pretrained','panel','Account nonce >= 20 at launch block','W_DEPLOY','4,765 contributors','verified'),
];
export const ORACLE_IDS = CATALOG.filter(t=>t.id>=601).map(t=>t.id);
export const CHAIN_IDS = CATALOG.filter(t=>t.evidence==='chain-proven').map(t=>t.id);
export const isRare = (id:number) => [202,801,901,1001,1201].includes(id) || (id>=1101 && id<=1104);
export const topOf = (ids:number[]) => FAMILIES.map((_,i)=>{
 const family = ids.filter(id=>Math.floor(id/100)===i+1);
 return family.length ? (i===10 ? Math.min(...family) : Math.max(...family)) : 0;
});
export const WINDOWS = [
 ['W_LIFE','25,769,870','25,789,604','19,735','0x189378e','0x18984a4'],
 ['W_JUDGED','25,777,045','25,789,604','12,560','0x1895395','0x18984a4'],
 ['W_FIRST1000','25,769,870','25,770,897','1,028','0x189378e','0x1893b91'],
 ['W_DEPLOY','25,769,870','25,769,870','1','0x189378e','0x189378e'],
];
