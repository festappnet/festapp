import {register} from 'node:module';register('../css_loader.mjs',import.meta.url);
import test from 'node:test';import assert from 'node:assert/strict';
import {ScannerFeedback} from '../../src/components/scan/scanner_feedback.js';
import {scanResult} from '../../src/components/scan/scan_result.js';
import {AppConfig} from '../../src/app_config.js';
const {ScanPage}=await import('../../src/components/scan/scan_page.js');
test('Web Audio produces distinct success, acceptance and error tones after a user gesture',async()=>{
 const frequencies=[];
 class Context{state='suspended';currentTime=0;destination={};async resume(){this.state='running';}async close(){this.state='closed';}createOscillator(){const o={frequency:{value:0},connect(){},disconnect(){},start(){frequencies.push(o.frequency.value);},stop(){}};return o;}createGain(){return {gain:{setValueAtTime(){},linearRampToValueAtTime(){},exponentialRampToValueAtTime(){}},connect(){},disconnect(){}};}}
 const sound=new ScannerFeedback({AudioContext:Context});sound.play('good');assert.deepEqual(frequencies,[]);
 await sound.unlock();sound.play('good');sound.play('accepted');sound.play('error');
 assert.deepEqual(frequencies,[880,880,1175,220,165]);sound.enabled=false;sound.play('error');assert.equal(frequencies.length,5);sound.dispose();
});
test('confirmation advances after a short delay, never on pending or mixed errors, with no repeated beeps',t=>{
 t.mock.timers.enable({apis:['setTimeout']});
 const accepted={state:'accepted',operation:{payload:{operation_id:'one'},receipt:{outcome:'accepted'}}},sounds=[];
 const page=Object.create(ScanPage.prototype);let controllers=[accepted],advances=0;
 page.controllers=()=>controllers;page.sound={play:kind=>sounds.push(kind)};page.feedbackStates=new WeakMap();page.route={page:'scan'};page.nextScan=()=>{advances++;};
 page.feedback(accepted);page.feedback(accepted);assert.deepEqual(sounds,['accepted']);
 t.mock.timers.tick(1199);assert.equal(advances,0);t.mock.timers.tick(1);assert.equal(advances,1);
 const pending={state:'pending'},bad={state:'error',error:'not_found'};
 controllers=[pending];page.feedback(pending);t.mock.timers.tick(3000);assert.equal(advances,1);
 controllers=[accepted,bad];page.feedback(bad);t.mock.timers.tick(3000);assert.equal(advances,1);assert.equal(sounds.at(-1),'error');
});
test('password reset requires app support, server capability and an online ticket',()=>{
 const previous=Object.getOwnPropertyDescriptor(globalThis,'navigator'),supported=AppConfig.isAppSupported;
 Object.defineProperty(globalThis,'navigator',{configurable:true,value:{onLine:true}});
 try{
  const ticket={source:'online',can_reset_password:true,products:[],fields:[],state:'sent',symbol:'DEMO'};
  AppConfig.isAppSupported=true;assert.match(scanResult({state:'result',ticket},true),/data-reset/);
  assert.doesNotMatch(scanResult({state:'result',ticket:{...ticket,can_reset_password:false}},true),/data-reset/);
  assert.doesNotMatch(scanResult({state:'result',ticket:{...ticket,source:'offline'}},true),/data-reset/);
  AppConfig.isAppSupported=false;assert.doesNotMatch(scanResult({state:'result',ticket},true),/data-reset/);
  assert.doesNotMatch(scanResult({state:'accepted',ticket,operation:{receipt:{committed_at:'2026-10-18T18:00:08Z'}}},true),/committed_at|2026-10-18|6:00:08/);
 }finally{AppConfig.isAppSupported=supported;Object.defineProperty(globalThis,'navigator',previous);}
});
