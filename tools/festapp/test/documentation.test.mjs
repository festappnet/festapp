import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import {fileURLToPath} from 'node:url';
import {readMcpReference,renderMcpPrompts,renderMcpReference} from '../../../automation/release/help/mcp_reference.mjs';

const root=fileURLToPath(new URL('../../../',import.meta.url));
test('committed MCP documentation matches the actual registry, schemas, scope dependencies and public client projection',()=>{
  const check=spawnSync(process.execPath,[fileURLToPath(new URL('../scripts/generate-reference.mjs',import.meta.url)),'--check'],{encoding:'utf8'});
  assert.equal(check.status,0,check.stderr);
  const reference=readMcpReference(root);
  const publicTools=reference.publicChatgpt.tools;
  assert.equal(publicTools.some(t=>!t.readOnly),false);
  assert.equal(publicTools.some(t=>t.id.startsWith('forms.')),false);
  const operatorSearch=reference.tools.find(t=>t.id==='orders.list').inputSchema;
  const publicSearch=publicTools.find(t=>t.id==='orders.list').inputSchema;
  assert.equal(operatorSearch.properties.search.pattern,undefined);
  assert.equal(publicSearch.properties.search.pattern,'^[A-Z0-9]{10}$');
  assert.equal(operatorSearch.required.includes('limit'),false,'defaulted input is optional');
  const form=reference.tools.find(t=>t.id==='forms.save');
  assert.ok(form.scopes.includes('festapp:forms:read'));
  assert.ok(form.scopes.includes('festapp:forms:write'));
  assert.ok(form.inputSchema.required.includes('commandId'));
});
test('published examples reference existing tools and derive dependencies; unknown operations stop generation',()=>{
  const reference=readMcpReference(root);
  const examples=JSON.parse(fs.readFileSync(new URL('../../../automation/release/help/mcp-prompts.json',import.meta.url)));
  for(const locale of ['cs','en']) {
    const html=renderMcpPrompts(reference,examples,locale);
    const catalog=renderMcpReference(reference,locale);
    for(const example of examples) {
      assert.ok(html.includes(`id="prompt-${example.id}"`));
      for(const id of example.operations) {
        const tool=reference.tools.find(t=>t.id===id);
        assert.ok(tool,`Unknown prompt operation: ${id}`);
        assert.ok(catalog.includes(`id="${tool.name}"`));
      }
    }
  }
  assert.throws(()=>renderMcpPrompts(reference,[{operations:['forms.nonexistent']}],'cs'),/Unknown MCP prompt operation/);
});
