// Round 3 (owner review 2026-10-19): the shared round-2 rows F-18.17, 18, 19/20/21, 22, 27/28, 29, 30, 31.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { BUILDERS_BRIDGE, BUILDERS_LINES, CLASS_CARDS, FLOW, PROOF_OF_SWEAR, STORIES } from '../src/components';
import { CLASS_SEGMENTS, COMMUNITY_SEGMENT, SWARM_LINKS } from '../src/pages';
import { WHY_ANSWER, WHY_QUESTION } from '../src/Claim';
import { CATALOG } from '../src/catalog';

const src=(name:string)=>readFileSync(new URL(`../src/${name}`,import.meta.url),'utf8');

test('F-18.29 / F-18.30: four class cards replace the stat cards; HOW IT WORKS is told for a wallet and for a curator',()=>{
 assert.deepEqual(CLASS_CARDS.map(c=>c.cls),['direct','chain-proven','shared','panel']);
 assert(PROOF_OF_SWEAR.startsWith('Proof of swear:'));
 assert.equal(STORIES.length,2);assert(STORIES[0].title.includes('for a wallet')&&STORIES[1].title.includes('for a curator'));
 for(const s of STORIES)assert.equal(s.steps.length,3);
 const pages=src('pages.tsx');assert(!pages.includes('className="stats"'),'the stat cards are gone');assert(pages.includes('<ClassCards/>')&&pages.includes('<Stories/>'));
});
test('F-18.27 / F-18.28: larger landing prose; the builders part of the contract comment follows WHY SWORN',()=>{
 const css=src('styles.css');assert.match(css,/\.intro-copy p, \.measure \{ font-size: 15px/);
 assert.deepEqual(BUILDERS_LINES,[32,53]);
 const excerpt=JSON.parse(readFileSync(new URL('../public/data/curator-source.json',import.meta.url),'utf8'));
 const lines=excerpt.lines.filter((l:{line:number})=>l.line>=32&&l.line<=53);
 assert.equal(lines.length,22);assert(lines[0].text.includes('does not pretend to solve sybil resistance'));assert(lines[lines.length-1].text.includes('not in this contract'));
 assert(src('pages.tsx').includes('<WhySworn/><BuildersExcerpt/>'));assert(BUILDERS_BRIDGE.length>0);
});
test('F-18.31: the IMD explorer links sit under "Built by the swarm"',()=>{
 assert.equal(SWARM_LINKS.length,3);assert(SWARM_LINKS.every(([,href])=>href.startsWith('https://explorer.imd.fun')));
 assert(SWARM_LINKS.some(([,h])=>h.includes('c3792acf'))&&SWARM_LINKS.some(([,h])=>h.includes('53f5fb2b')));
 const pages=src('pages.tsx');assert(pages.indexOf('{BUILT_BY_SWARM}')<pages.indexOf('SWARM_LINKS.map'));
});
test('F-18.17: the catalog is one segment per class, each with meaning, how it is sworn, how you get it, cost, risk and a claim link; then a community segment with a placeholder',()=>{
 assert.deepEqual(CLASS_SEGMENTS.map(s=>s.cls),['direct','chain-proven','shared','panel']);
 for(const s of CLASS_SEGMENTS){for(const k of ['meaning','sworn','get','cost','risk','step'] as const)assert(s[k].length>10,`${s.cls}.${k}`);assert.match(s.link,/^#\/claim#step-0[1-4]$/);}
 assert.equal(CLASS_SEGMENTS.reduce((n,s)=>n+CATALOG.filter(t=>t.evidence===s.cls).length,0),25,'every catalog row lands in exactly one segment');
 assert.match(COMMUNITY_SEGMENT.link,/#step-03$/);const pages=src('pages.tsx');assert(pages.includes('placeholder-row')&&pages.includes('Read registered community specs by id'));
 assert(src('Claim.tsx').includes('id={`step-${n}`}'),'the claim steps carry the anchors the catalog links to');
});
test('F-18.18: the claim guide keeps the explanation and flow after the first-screen mint',()=>{
 assert.equal(WHY_QUESTION,'Why do I need to buy traits for a card I already minted?');assert(WHY_ANSWER.startsWith('You do not.'));
 assert.equal(FLOW.length,2);assert.equal(FLOW[0].length,3);assert.equal(FLOW[1].length,4);
 const claim=src('Claim.tsx');assert(claim.indexOf('<Section title={WHY_QUESTION}')>claim.indexOf('<div className="mint-block">'));assert(claim.includes('<FlowChart/>'));
});
test('F-18.19/20/21: steps 01, 02 and 03 each carry who, cost, risk and who benefits',()=>{
 const claim=src('Claim.tsx');
 const boxes=[...claim.matchAll(/<InfoBox who=/g)].length;assert.equal(boxes,3);
 for(const step of ['01','02','03']){const i=claim.indexOf(`<ClaimStep number="${step}"`);const j=claim.indexOf('<ClaimStep number=',i+10);assert(claim.slice(i,j<0?undefined:j).includes('<InfoBox who='),`step ${step}`);}
});
test('F-18.22: the oracle picker is a table with headers, the preview centred in the middle column, and the curation note',()=>{
 const claim=src('Claim.tsx');
 const headers=[...claim.matchAll(/<th(?: className="preview-cell")?>([^<]+)<\/th>/g)].map(m=>m[1]);
 assert.deepEqual(headers.slice(0,5),['Select','Fact','Preview on an empty card','What it adds to the card','Who benefits']);
 assert(claim.includes('<td className="preview-cell"><MiniCard id={t.id}/></td>'));
 assert.match(src('styles.css'),/\.trait-picker td\.preview-cell, \.trait-picker th\.preview-cell \{ text-align: center/);
 assert(claim.includes('only facts minted onchain count'));
});
