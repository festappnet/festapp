import test from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
import {ThemeService} from '../../src/services/theme_service.js';
import {AppConfig} from '../../src/app_config.js';

test('manual theme controls both page and native controls independently of the OS', t=>{
 const dom=new JSDOM('<!doctype html><body><input type="checkbox"><select><option>Theme</option></select></body>',{url:'https://fixture.invalid'});
 const previous=Object.fromEntries(['window','document','localStorage'].map(key=>[key,globalThis[key]]));
 Object.assign(globalThis,{window:dom.window,document:dom.window.document,localStorage:dom.window.localStorage});
 let osDark=true;
 dom.window.matchMedia=()=>({matches:osDark,addEventListener(){},removeEventListener(){}});
 t.after(()=>{Object.assign(globalThis,previous);ThemeService._mediaQueryListener=null;dom.window.close();});
 localStorage.setItem(AppConfig.Keys.theme,'light');
 ThemeService.init();
 assert.equal(document.body.classList.contains('dark-mode'),false);
 assert.equal(document.body.style.colorScheme,'light');
 ThemeService.setMode('dark');
 assert.equal(document.body.classList.contains('dark-mode'),true);
 assert.equal(document.body.style.colorScheme,'dark');
 ThemeService.setMode('light');
 assert.equal(document.body.style.colorScheme,'light');
 ThemeService.setMode('auto');
 assert.equal(document.body.style.colorScheme,'dark');
 osDark=false;ThemeService.setMode('auto');
 assert.equal(document.body.classList.contains('dark-mode'),false);
 assert.equal(document.body.style.colorScheme,'light');
 // The preference changed in the other public tab, not in this document.
 localStorage.setItem(AppConfig.Keys.theme,'dark');
 dom.window.dispatchEvent(new dom.window.StorageEvent('storage',{key:AppConfig.Keys.theme,newValue:'dark',storageArea:localStorage}));
 assert.equal(document.body.classList.contains('dark-mode'),true);
 assert.equal(document.body.style.colorScheme,'dark');
 localStorage.setItem(AppConfig.Keys.theme,'light');
 dom.window.dispatchEvent(new dom.window.PageTransitionEvent('pageshow',{persisted:true}));
 assert.equal(document.body.classList.contains('dark-mode'),false);
 assert.equal(document.body.style.colorScheme,'light');
});


test('public client inherits an existing admin light preference instead of the dark OS', t=>{
 const dom=new JSDOM('<!doctype html><body></body>',{url:'https://fixture.invalid'});
 const previous=Object.fromEntries(['window','document','localStorage'].map(key=>[key,globalThis[key]]));
 Object.assign(globalThis,{window:dom.window,document:dom.window.document,localStorage:dom.window.localStorage});
 dom.window.matchMedia=()=>({matches:true,addEventListener(){},removeEventListener(){}});
 t.after(()=>{Object.assign(globalThis,previous);ThemeService._mediaQueryListener=null;ThemeService._lastFormModel=null;dom.window.close();});
 localStorage.setItem('adaptive_theme_preferences',JSON.stringify(JSON.stringify({theme_mode:0,default_theme_mode:0})));
 ThemeService.init();
 assert.equal(ThemeService.currentMode,'light');
 assert.equal(document.body.classList.contains('dark-mode'),false);
 assert.equal(localStorage.getItem(AppConfig.Keys.theme),'light');
 ThemeService.setMode('auto');
 assert.equal(localStorage.getItem(AppConfig.Keys.theme),'auto');
 ThemeService.init();
 assert.equal(ThemeService.currentMode,'auto');
 assert.equal(document.body.classList.contains('dark-mode'),true);
 localStorage.setItem(AppConfig.Keys.theme,'light');
 window.dispatchEvent(new window.Event('focus'));
 assert.equal(ThemeService.currentMode,'light');
 assert.equal(document.body.classList.contains('dark-mode'),false);
});
