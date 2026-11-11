import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
for (const slug of ['vstupenky-online','festapp-tickets']) test(slug+' persists host only for new insertions',()=>{
 const base=new URL('../'+slug+'/',import.meta.url);
 const metadata=JSON.parse(readFileSync(new URL('blocks/ticket-form/block.json',base)));
 let variation;
 vm.runInNewContext(readFileSync(new URL('blocks/ticket-form/editor.js',base),'utf8'),{window:{wp:{blocks:{registerBlockType(){},registerBlockVariation(name,v){variation=v;}},element:{},blockEditor:{},components:{},i18n:{}}}});
 assert.equal(metadata.attributes.measurement.default,'unit');
 assert.equal(variation.isDefault,true);assert.equal(variation.attributes.measurement,'host');
 assert.notEqual(variation.attributes.measurement,metadata.attributes.measurement.default,'Gutenberg must serialize host explicitly');
 const help=readFileSync(new URL('includes/admin.php',base),'utf8');
 for(const shortcode of help.matchAll(/\[[a-z_]+ url=[^\]]+\]/g))assert.match(shortcode[0],/measurement="host"/);
});
