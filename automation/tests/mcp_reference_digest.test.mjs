import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {referenceSourceDigest} from '../release/help/mcp_reference.mjs';

test('MCP reference tracks its labels and transitive contracts without unrelated translations',t=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'festapp-mcp-digest-'));t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
 const put=(file,text)=>{const name=path.join(root,file);fs.mkdirSync(path.dirname(name),{recursive:true});fs.writeFileSync(name,text);};
 for(const file of ['tools/festapp/src/mcp/server.mjs','tools/festapp/src/remote/delegation.mjs','tools/festapp/src/remote/config.mjs','tools/festapp/scripts/generate-reference.mjs','tools/festapp/package.json','packages/festapp_contracts/mcp-permissions.mjs','integrations/chatgpt/client-policy.json'])put(file,'{}');
 put('tools/festapp/src/operations/catalog.mjs',"import './enums.json';");put('tools/festapp/src/operations/enums.json','["one"]');
 for(const locale of ['cs','en'])put(`assets/translations/${locale}.json`,JSON.stringify({McpConnection:{read:'Read'},Other:'old'}));
 const original=referenceSourceDigest(root);
 put('assets/translations/cs.json',JSON.stringify({McpConnection:{read:'Read'},Other:'new unrelated copy'}));assert.equal(referenceSourceDigest(root),original);
 put('assets/translations/cs.json',JSON.stringify({McpConnection:{read:'Changed label'},Other:'new unrelated copy'}));assert.notEqual(referenceSourceDigest(root),original);
 const labels=referenceSourceDigest(root);put('tools/festapp/src/operations/enums.json','["one","two"]');assert.notEqual(referenceSourceDigest(root),labels);
});
