import test from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
import {initDemoPlayers} from '../../src/marketing/demo_player.js';

test('demo keeps mobile poster, aspect ratio and visible playback label in sync',async t=>{
 const dom=new JSDOM('<script type="application/json" id="marketing-ui">{"play":"Přehrát","pause":"Pozastavit","replay":"Znovu","retry":"Zkusit znovu"}</script><div data-demo-player><video></video><button data-playback-surface><span data-playback-label></span></button><p class="media-fallback" hidden></p></div>',{pretendToBeVisual:true});
 t.after(()=>dom.window.close());
 const win=dom.window,doc=win.document;
 const narrow=Object.assign(new win.EventTarget(),{matches:false});
 const motion=Object.assign(new win.EventTarget(),{matches:true});
 win.matchMedia=query=>query.includes('max-width')?narrow:motion;
 const stage=doc.querySelector('[data-demo-player]');
 stage.dataset.variants=JSON.stringify([{id:'form',src:'/desktop.mp4',poster:'/desktop.webp',width:1200,height:804,mobileSrc:'/mobile.mp4',mobilePoster:'/mobile.webp',mobileWidth:720,mobileHeight:638,description:'Formulář'}]);
 const video=stage.querySelector('video');let paused=true;
 Object.defineProperty(video,'paused',{get:()=>paused});
 video.pause=()=>{paused=true;};video.load=()=>{};video.play=async()=>{paused=false;};
 const cleanup=initDemoPlayers(doc);t.after(cleanup);
 narrow.matches=true;narrow.dispatchEvent(new win.Event('change'));
 assert.equal(video.getAttribute('poster'),'/mobile.webp');assert.equal(video.width,720);assert.equal(video.height,638);
 stage.querySelector('button').click();await new Promise(resolve=>setImmediate(resolve));
 assert.equal(video.getAttribute('src'),'/mobile.mp4');assert.equal(stage.querySelector('[data-playback-label]').textContent,'Pozastavit');
 narrow.matches=false;narrow.dispatchEvent(new win.Event('change'));
 assert.equal(video.getAttribute('poster'),'/desktop.webp');assert.equal(video.width,1200);assert.equal(video.getAttribute('src'),null);
 assert.equal(stage.querySelector('[data-playback-label]').textContent,'Přehrát');
});
