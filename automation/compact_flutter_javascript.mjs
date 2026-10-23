#!/usr/bin/env node
import {readFile,readdir,writeFile} from 'node:fs/promises';
import path from 'node:path';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';

// Keep Dart identifiers, constructor names and deferred-library identities.
// dart2js installs runtime type tags from constructor.name. Even without
// identifier minification, esbuild renames shadowed constructors (A -> A2).
// keepNames restores the names before Dart installs those type tags.
// Only lexical whitespace/comments change, before immutable files are stamped.
const require=createRequire(new URL('../web_client/package.json',import.meta.url));
export async function compactFlutterJavascript(buildDir){
 const{transform}=require('esbuild');
 const names=(await readdir(buildDir)).filter(name=>/^main\.dart\.js(?:_\d+\.part\.js)?$/.test(name));
 if(!names.includes('main.dart.js'))throw new Error('Missing compiled main.dart.js');
 const transformed=await Promise.all(names.map(async name=>{
  const source=await readFile(path.join(buildDir,name),'utf8');
  const {code}=await transform(source,{loader:'js',target:'esnext',keepNames:true,minifyWhitespace:true,minifyIdentifiers:false,minifySyntax:false,legalComments:'inline',sourcemap:false});
  return{name,source,code:Buffer.byteLength(code)<Buffer.byteLength(source)?code:source};
 }));
 let savedBytes=0;
 for(const{name,source,code}of transformed){savedBytes+=Buffer.byteLength(source)-Buffer.byteLength(code);if(code!==source)await writeFile(path.join(buildDir,name),code);}
 return{files:transformed.length,savedBytes};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href){
 const result=await compactFlutterJavascript(path.resolve(process.argv[2]||'build/web'));
 console.log(`Flutter JavaScript: ${result.files} executables, ${result.savedBytes} lexical formatting bytes removed`);
}
