import test from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
import {ThemeService} from '../../src/services/theme_service.js';
import {FormModel} from '../../src/components/forms/form_models.js';
import {AppConfig} from '../../src/app_config.js';
import {SettingsWidget} from '../../src/components/forms/widgets/settings_widget.js';

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
 ThemeService.applyThemeFromModel(new FormModel({data:{design:{theme_mode:'system'}}}));
 assert.equal(document.body.style.colorScheme,'light');
 ThemeService.clearFormTheme();
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


test('per-form appearance inherits personal preference, locks explicit modes and restores portal colors', t=>{
 const dom=new JSDOM('<!doctype html><body></body>',{url:'https://fixture.invalid'});
 const previous=Object.fromEntries(['window','document','localStorage'].map(key=>[key,globalThis[key]]));
 Object.assign(globalThis,{window:dom.window,document:dom.window.document,localStorage:dom.window.localStorage});
 let osDark=true, onChange;
 dom.window.matchMedia=()=>({matches:osDark,addEventListener(type,fn){onChange=fn;}});
 ThemeService._lastFormModel=null;ThemeService._mediaQueryListener=null;ThemeService._formStyleSnapshot=null;
 t.after(()=>{Object.assign(globalThis,previous);ThemeService._mediaQueryListener=null;ThemeService._lastFormModel=null;ThemeService._formStyleSnapshot=null;dom.window.close();});
 localStorage.setItem(AppConfig.Keys.theme,'light');ThemeService.init();
 document.body.style.setProperty('--primary-color','#abcdef');
 const form=mode=>new FormModel({data:{design:{primary_color:'#123456',...(mode?{theme_mode:mode}:{})}}});
 ThemeService.applyThemeFromModel(form());
 assert.equal(document.body.style.colorScheme,'light');
 const lightColor=document.body.style.getPropertyValue('--primary-color');
 osDark=false;onChange({matches:false});
 assert.equal(document.body.style.colorScheme,'light');
 assert.equal(document.body.style.getPropertyValue('--primary-color'),lightColor);
 ThemeService.setMode('auto');
 osDark=true;onChange({matches:true});
 assert.equal(document.body.style.colorScheme,'dark');
 assert.notEqual(document.body.style.getPropertyValue('--primary-color'),lightColor);
 ThemeService.applyThemeFromModel(form('dark'));
 assert.equal(document.body.style.colorScheme,'dark');
 osDark=true;onChange({matches:true});
 ThemeService.applyThemeFromModel(form('light'));
 assert.equal(document.body.style.colorScheme,'light');
 window.dispatchEvent(new window.Event('focus'));
 assert.equal(document.body.style.colorScheme,'light');
 osDark=false;onChange({matches:false});
 assert.equal(document.body.style.colorScheme,'light');
 ThemeService.setMode('light');
 ThemeService.applyThemeFromModel(form('system'));
 osDark=true;onChange({matches:true});
 assert.equal(document.body.style.colorScheme,'light');
 assert.equal(localStorage.getItem(AppConfig.Keys.theme),'light');
 ThemeService.clearFormTheme();
 assert.equal(document.body.style.colorScheme,'light');
 assert.equal(document.body.style.getPropertyValue('--primary-color'),'#abcdef');
 assert.equal(ThemeService._lastFormModel,null);
});

for (const personal of ['light','dark','auto']) {
 for (const formMode of ['system','light','dark']) {
  for (const osDark of [false,true]) {
   test(`form appearance priority: personal=${personal}, form=${formMode}, darkOS=${osDark}`,t=>{
    const dom=new JSDOM('<!doctype html><body></body>',{url:'https://fixture.invalid'});
    const previous=Object.fromEntries(['window','document','localStorage'].map(key=>[key,globalThis[key]]));
    Object.assign(globalThis,{window:dom.window,document:dom.window.document,localStorage:dom.window.localStorage});
    window.matchMedia=()=>({matches:osDark,addEventListener(){}});
    ThemeService._lastFormModel=null;ThemeService._mediaQueryListener=null;ThemeService._formStyleSnapshot=null;
    t.after(()=>{Object.assign(globalThis,previous);ThemeService._lastFormModel=null;ThemeService._mediaQueryListener=null;ThemeService._formStyleSnapshot=null;dom.window.close();});
    localStorage.setItem(AppConfig.Keys.theme,personal);
    ThemeService.init();
    ThemeService.applyThemeFromModel(new FormModel({data:{design:{theme_mode:formMode}}}));
    const effective=formMode==='system'?personal:formMode;
    const expected=effective==='auto'?(osDark?'dark':'light'):effective;
    assert.equal(document.body.style.colorScheme,expected);
    assert.equal(document.documentElement.style.colorScheme,expected);
    assert.equal(document.body.classList.contains('dark-mode'),expected==='dark');
    assert.equal(localStorage.getItem(AppConfig.Keys.theme),personal,'form appearance never replaces personal preference');
    ThemeService.clearFormTheme();
    assert.equal(document.body.style.colorScheme,personal==='auto'?(osDark?'dark':'light'):personal);
   });
  }
 }
}

test('system form follows cross-tab personal changes and uses OS only in auto',t=>{
 const dom=new JSDOM('<!doctype html><body></body>',{url:'https://fixture.invalid'});
 const previous=Object.fromEntries(['window','document','localStorage'].map(key=>[key,globalThis[key]]));
 Object.assign(globalThis,{window:dom.window,document:dom.window.document,localStorage:dom.window.localStorage});
 let osDark=true,onChange;
 window.matchMedia=()=>({get matches(){return osDark;},addEventListener(type,fn){onChange=fn;}});
 ThemeService._lastFormModel=null;ThemeService._mediaQueryListener=null;ThemeService._formStyleSnapshot=null;
 t.after(()=>{Object.assign(globalThis,previous);ThemeService._lastFormModel=null;ThemeService._mediaQueryListener=null;ThemeService._formStyleSnapshot=null;dom.window.close();});
 localStorage.setItem(AppConfig.Keys.theme,'light');ThemeService.init();
 ThemeService.applyThemeFromModel(new FormModel({data:{design:{theme_mode:'system',primary_color:'#123456'}}}));
 assert.equal(document.body.style.colorScheme,'light');
 const lightAccent=document.body.style.getPropertyValue('--primary-color');
 osDark=false;onChange({matches:false});
 localStorage.setItem(AppConfig.Keys.theme,'dark');
 window.dispatchEvent(new window.StorageEvent('storage',{key:AppConfig.Keys.theme,newValue:'dark'}));
 assert.equal(document.body.style.colorScheme,'dark');
 assert.notEqual(document.body.style.getPropertyValue('--primary-color'),lightAccent);
 ThemeService.setMode('auto');
 assert.equal(document.body.style.colorScheme,'light');
 osDark=true;onChange({matches:true});
 assert.equal(document.body.style.colorScheme,'dark');
});

for (const formMode of ['system','light','dark']) {
 test(`public form settings reflect inherited preference or locked ${formMode} design`,t=>{
  const dom=new JSDOM('<!doctype html><body></body>',{url:'https://fixture.invalid'});
  const previous=Object.fromEntries(['window','document','localStorage'].map(key=>[key,globalThis[key]]));
  Object.assign(globalThis,{window:dom.window,document:dom.window.document,localStorage:dom.window.localStorage});
  window.matchMedia=()=>({matches:true,addEventListener(){}});
  ThemeService._lastFormModel=null;ThemeService._mediaQueryListener=null;ThemeService._formStyleSnapshot=null;
  t.after(()=>{Object.assign(globalThis,previous);ThemeService._lastFormModel=null;ThemeService._mediaQueryListener=null;ThemeService._formStyleSnapshot=null;dom.window.close();});
  localStorage.setItem(AppConfig.Keys.theme,'light');ThemeService.init();
  ThemeService.applyThemeFromModel(new FormModel({data:{design:{theme_mode:formMode}}}));
  const settings=new SettingsWidget(document.createElement('div'));
  const buttons=()=>[...settings.element.querySelector('.segmented-control').querySelectorAll('button')];
  assert.equal(buttons().every(button=>button.disabled),formMode!=='system');
  assert.equal(buttons()[formMode==='dark'?0:2].classList.contains('active'),true);
  if(formMode==='system') {
   buttons()[0].click();
   assert.equal(localStorage.getItem(AppConfig.Keys.theme),'dark');
   assert.equal(document.body.style.colorScheme,'dark');
   assert.equal(buttons()[0].classList.contains('active'),true);
  } else {
   buttons()[1].click();
   assert.equal(localStorage.getItem(AppConfig.Keys.theme),'light');
   assert.equal(document.body.style.colorScheme,formMode);
  }
 });
}
