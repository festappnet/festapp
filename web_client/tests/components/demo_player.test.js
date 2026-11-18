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

test('a manually started video keeps playing beside a more visible video', async t => {
 const card = '<div data-demo-player><video></video><button data-playback-surface></button><p class="media-fallback" hidden></p></div>';
 const dom = new JSDOM(card + card, { pretendToBeVisual: true });
 const win = dom.window;
 t.after(() => win.close());
 win.matchMedia = () => Object.assign(new win.EventTarget(), { matches: false });
 let measure;
 win.setTimeout = handler => { measure = handler; };
 win.clearTimeout = () => {};
 const [first, second] = Array.from(win.document.querySelectorAll('[data-demo-player]'));
 const layout = new Map([[first, 0], [second, -20]]);
 for (const [index, stage] of [first, second].entries()) {
   stage.dataset.variants = JSON.stringify([{ id: String(index), src: `/${index}.mp4`, width: 100, height: 100, description: 'Ukázka' }]);
   stage.getBoundingClientRect = () => ({ left: 0, right: 100, width: 100, top: layout.get(stage), bottom: layout.get(stage) + 100, height: 100 });
   const video = stage.querySelector('video');
   let paused = true;
   Object.defineProperty(video, 'paused', { get: () => paused });
   video.load = () => {};
   video.pause = () => { paused = true; };
   video.play = async () => { paused = false; };
 }
 t.after(initDemoPlayers(win.document));
 const firstVideo = first.querySelector('video');
 const secondVideo = second.querySelector('video');
 measure();
 assert.equal(firstVideo.paused, false);
 second.querySelector('button').click();
 measure();
 assert.equal(firstVideo.paused, true);
 assert.equal(secondVideo.paused, false);
 layout.set(second, -100);
 win.dispatchEvent(new win.Event('scroll'));
 measure();
 assert.equal(firstVideo.paused, false);
 assert.equal(secondVideo.paused, true);
});
