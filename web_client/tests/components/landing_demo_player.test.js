import test from 'node:test';
import assert from 'node:assert/strict';
import { chooseVisiblePlayer, visibleRatio, initDemoPlayers } from '../../src/marketing/demo_player.js';

test('visible selection excludes paused/completed/error players and supports tall panels', () => {
  const ready = { ratio: .65 };
  assert.equal(chooseVisiblePlayer([{ratio:.9,manualPause:true},{ratio:1,ended:true},{ratio:.8,error:true},ready]), ready);
  assert.equal(chooseVisiblePlayer([{ratio:.49}]), null);
  assert.equal(visibleRatio({top:0,bottom:1600,left:0,right:800,height:1600,width:800},800,800),1);
});

class Element extends EventTarget {
  constructor() { super(); this.attrs = {}; this.textContent = ''; this.hidden = false; }
  setAttribute(k,v) { this.attrs[k] = v; }
  getAttribute(k) { return this.attrs[k]; }
  removeAttribute(k) { delete this.attrs[k]; }
  click() { this.dispatchEvent(new Event('click')); }
}
class Video extends Element {
  constructor() { super(); this.paused = true; this.currentTime = 0; this.loads = 0; }
  set src(value) { this.attrs.src = value; }
  get src() { return this.attrs.src; }
  load() { this.loads++; }
  async play() { this.paused = false; this.dispatchEvent(new Event('play')); }
  pause() { if (!this.paused) { this.paused = true; this.dispatchEvent(new Event('pause')); } }
}
function fixture({reduced=false,saver=false}={}) {
  const root = new Element(), win = new Element(), media = new Element();
  media.matches = reduced;
  win.matchMedia = () => media;
  win.navigator = {connection: Object.assign(new Element(),{saveData:saver})};
  win.innerHeight = 800; win.innerWidth = 1000;
  let pending;
  win.setTimeout = callback => { pending = callback; return 1; };
  root.defaultView = win; root.hidden = false;
  const stages = [0,1].map(index => {
    const stage = new Element();
    const variants = [{id:'build',src:'/build.mp4',poster:'/build.jpg',description:'Build',label:'Build',duration:12},{id:'style',src:'/style.mp4',poster:'/style.jpg',description:'Style',label:'Style',duration:8}];
    stage.dataset = {variants:JSON.stringify(index === 0 ? variants : variants.slice(0,1))};
    stage.video = new Video(); stage.button = new Element(); stage.fallback = new Element(); stage.title = new Element(); stage.download = new Element();
    stage.parentElement = {querySelector:()=>new Element()};
    stage.rect = {top:index*1000,bottom:index*1000+500,left:0,right:800,width:800,height:500};
    stage.getBoundingClientRect = () => stage.rect;
    stage.querySelector = selector => ({video:stage.video,'[data-playback-surface]':stage.button,'.media-fallback':stage.fallback,'.media-title':stage.title,'[data-media-download]':stage.download}[selector]);
    stage.querySelectorAll = () => [];
    return stage;
  });
  root.querySelectorAll = () => stages;
  const cleanup = initDemoPlayers(root);
  return {root,win,stages,cleanup,tick:()=>pending?.(),scroll:()=>win.dispatchEvent(new Event('scroll'))};
}

test('lazy sources, single playback, explicit pause survives visibility and variants, visible sequence advances and single clips repeat without visible controls', async () => {
  const f = fixture(); const [a,b] = f.stages;
  assert.equal(a.video.src,undefined); assert.equal(b.video.src,undefined);
  f.tick(); await Promise.resolve();
  assert.equal(a.video.paused,false); assert.equal(b.video.src,undefined);
  a.button.click(); f.scroll(); f.tick();
  assert.equal(a.video.paused,true);
  a.video.dispatchEvent(new Event('ended'));
  assert.equal(a.video.src,'/build.mp4','paused player does not advance its sequence');
  a.button.click(); await Promise.resolve(); assert.equal(a.video.src,'/build.mp4');
  a.video.pause(); a.video.dispatchEvent(new Event('ended')); await Promise.resolve();
  assert.equal(a.video.src,'/style.mp4','visible sequence advances without controls');
  assert.equal(a.video.loop,false);
  assert.equal(a.button.textContent,'','click surface has no visible label');
  b.rect = a.rect; a.rect = {...a.rect,top:-700,bottom:-200}; f.scroll(); f.tick(); await Promise.resolve();
  assert.equal(a.video.paused,true); assert.equal(b.video.paused,false);
  b.video.pause(); b.video.dispatchEvent(new Event('ended')); f.scroll(); f.tick();
  assert.equal(b.video.paused,false); assert.equal(b.video.loop,true);
  b.button.click(); assert.equal(b.video.paused,true);
  b.button.click(); await Promise.resolve(); assert.equal(b.video.paused,false);
  f.cleanup(); assert.equal(b.video.paused,true);
});

test('reduced motion and data saver wait for manual action; media errors keep fallback and allow retry', async () => {
  for (const option of [{reduced:true},{saver:true}]) {
    const f=fixture(option); const a=f.stages[0]; f.tick();
    assert.equal(a.video.src,undefined);
    a.button.click(); await Promise.resolve(); assert.equal(a.video.paused,false);
    a.video.dispatchEvent(new Event('error')); assert.equal(a.fallback.hidden,false); assert.equal(a.video.src,undefined);
    a.button.click(); await Promise.resolve(); assert.equal(a.fallback.hidden,true); assert.equal(a.video.paused,false);
    f.root.hidden=true; f.root.dispatchEvent(new Event('visibilitychange')); assert.equal(a.video.paused,true);
    f.cleanup();
  }
});
