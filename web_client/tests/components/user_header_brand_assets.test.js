import assert from 'node:assert/strict';
import test from 'node:test';
import {register} from 'node:module';
import {JSDOM} from 'jsdom';
register('../css_loader.mjs',import.meta.url);

test('canonical account header keeps responsive tenant logos within the public page asset owner',async t=>{
 const dom=new JSDOM('<body></body>',{url:'https://vstupenky.online/napoveda/ai-agenti/'});
 for(const key of ['window','document','HTMLElement','customElements'])globalThis[key]=key==='window'?dom.window:dom.window[key];
 const [{UserHeader},{RightsService},{AppConfig}]=await Promise.all([import('../../src/components/users/user_header.js'),import('../../src/services/rights_service.js'),import('../../src/app_config.js')]);
 const context=RightsService._context,link=AppConfig.webLink;
 t.after(()=>{RightsService._context=context;AppConfig.webLink=link;dom.window.close();});
 RightsService._context={organization:{}};
 for(const [site,base]of[['https://vstupenky.online','/napoveda/assets/'],['https://vstupenky.online','/'],['https://festapp.net','/napoveda/assets/']]){
  AppConfig.webLink=site;
  const header=new UserHeader();
  if(base!=='/')header.setAttribute('brand-asset-base',base);
  document.body.append(header);
  const urls=[...header.querySelectorAll('img')].map(img=>img.getAttribute('src'));
  if(site.includes('vstupenky.online')){
   assert.deepEqual(urls,[base+'brand-symbol.svg',base+'brand-wordmark.svg']);
   assert.equal(header.querySelector('source').getAttribute('srcset'),base+'brand-wordmark-stacked.svg');
  }else assert.deepEqual(urls,[base+'brand-logo.svg']);
  assert.equal(header.querySelector('.header-home-link').getAttribute('href'),'/');
  header.remove();
 }
});
