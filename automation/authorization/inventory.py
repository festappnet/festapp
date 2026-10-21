#!/usr/bin/env python3
"""Source reachability candidates for authorization. Catalog evidence is separate.

This deliberately reports unresolved dynamic calls and unclassified endpoints;
text matches are never proof of an authorization boundary or execution coverage.
"""
import hashlib
import json
import re
import subprocess
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'automation'))
from generate_canonical_source_contract import statements, CREATE, identity

DEST = ROOT / 'docs/plans/evidence/canonical-authorization-20261020/source-inventory.json'


def inventory():
    functions, sql_edges, callsites, boundaries, policies, grants, dynamic = [], [], [], [], [], [], []
    tables=(ROOT/'lib/database_tables/tb.dart').read_text()
    table_classes={m[1]:m[2] for m in re.finditer(r'class\s+(\w+)\s*\{(?:(?!\bclass\s).)*?String get table => [\x27"]([^\x27"]+)',tables,re.S)}
    table_constants={m[2]:table_classes[m[1]] for m in re.finditer(r'static\s+(?:final\s+|const\s+)?(\w+)\s+(\w+)\s*=',tables) if m[1] in table_classes}
    test_callsites, test_boundaries = [], []
    roots = ['database/functions', 'database/policies', 'lib', 'web_client/src',
             'supabase/functions', 'workers', 'tools/festapp/src']
    files = sorted(p for folder in roots for p in (ROOT / folder).rglob('*')
                   if p.suffix in ('.sql', '.dart', '.js', '.mjs', '.ts')
                   and not any(x in p.parts for x in ('node_modules', '.wrangler', 'dist')))
    for path in files:
        text = path.read_text()
        rel = str(path.relative_to(ROOT))
        test_source = any(part in ('test', 'tests', '__tests__') for part in path.parts) or bool(
            re.search(r'(?:_test|\.test|\.spec)\.[^.]+$', path.name))
        if path.suffix == '.sql':
            for statement in statements(text):
                m = CREATE.search(statement)
                if m:
                    try:
                        signature = identity(m[1], m[2], True)
                    except (ValueError, IndexError):
                        signature = m[1] + '(' + m[2] + ')'
                    refs = sorted(set(re.findall(r'\b(?:public\.)?((?:get_is_|check_is_|get_can_|can_|check_occasion_|assert_)[a-z0-9_]+)\s*\(', m[5], re.I)))
                    functions.append(dict(signature=signature, source=rel,
                        line=text[:text.find(statement)].count('\n') + 1,
                        securityDefiner='SECURITY DEFINER' in m[3].upper(),
                        bodySha256=hashlib.sha256(m[5].encode()).hexdigest(),
                        authorizationCandidates=refs,
                        state='unclassified'))
                    for ref in refs:
                        sql_edges.append(dict(caller=signature, candidate=ref))
            for n, line in enumerate(text.splitlines(), 1):
                if re.search(r'CREATE\s+POLICY', line, re.I):
                    policies.append(dict(source=rel,line=n,sql=line.strip()))
                if re.search(r'\b(?:GRANT|REVOKE)\b', line, re.I):
                    grants.append(dict(source=rel,line=n,sql=line.strip()))
                if re.search(r'\bEXECUTE\s+(?!ON\b|PROCEDURE\b|FUNCTION\b|TO\b|FROM\b)', line, re.I):
                    dynamic.append(dict(source=rel,line=n,code=line.strip()))
        else:
            # Arguments often begin on the next line, especially command
            # transports. Match across whitespace, retaining unresolved calls.
            destination = test_callsites if test_source else callsites
            for call in re.finditer(r'(?:\.|\b_)(rpc|from|invokeIntent|invoke)(?:<[^;(){}]*>)?\s*\(', text):
                # Dart/JS DTO and collection constructors are not PostgREST.
                prefix=text[max(0,call.start()-250):call.start()]
                line_prefix=text[text.rfind('\n',0,call.start())+1:call.start()]
                if line_prefix.lstrip().startswith(('//','*','/*')):
                    continue
                if call[1]=='from' and re.search(r'\b[A-Z][A-Za-z0-9_]*(?:<[A-Za-z0-9_,.<>? \n]+>)?\s*$',prefix):
                    continue
                # A private transport declaration is not an invocation.
                if re.match(r'\s*(?:String|int|Future|Map|List)\b',text[call.end():]):
                    continue
                argument = re.match(r"\s*(['\"])([^'\"\r\n]+)\1", text[call.end():])
                target = argument[2] if argument and re.fullmatch(r'[a-zA-Z_][a-zA-Z0-9_.-]*', argument[2]) else None
                constant = re.match(r'\s*Tb\.([a-z_]+)\.table\b', text[call.end():])
                if call[1]=='from' and constant:
                    target=table_constants.get(constant[1])
                if call[1]=='invokeIntent':
                    # The first argument is an idempotency/resource key. The
                    # backend RPC name is the second positional argument.
                    intent=re.match(r"\s*(['\"])[^\r\n]*?\1\s*,\s*(['\"])([a-z][a-z0-9_]*)\2",text[call.end():])
                    target=intent[3] if intent else None
                n = text.count('\n', 0, call.start()) + 1
                destination.append(dict(source=rel,line=n,kind=call[1] if target else 'dynamic-'+call[1],
                    target=target,code=text[call.start():call.end()+min(120,len(text)-call.end())].split('\n')[0].strip()))
            # Named adapter functions and injected reads still dispatch real
            # RPCs. Record their literal candidates separately; actual dataflow
            # and SQL admission remain part of semantic classification.
            for call in re.finditer(r"(?<![\w.])(?:this\.)?(?:emailRpc|rpc|_read|_call|read|call)\s*\(\s*(['\"])([a-z][a-z0-9_]+)\1",text):
                destination.append(dict(source=rel,line=text.count('\n',0,call.start())+1,
                    kind='named-adapter-candidate',target=call[2],code=call[0]))
            for call in re.finditer(r"\.onPostgresChanges\s*\(|\.on\s*\(\s*['\"]postgres_changes['\"]", text):
                body=text[call.end():call.end()+2000]
                table=re.search(r"\btable\s*:\s*['\"]([^'\"]+)['\"]",body)
                schema=re.search(r"\bschema\s*:\s*['\"]([^'\"]+)['\"]",body)
                destination.append(dict(source=rel,line=text.count('\n',0,call.start())+1,
                    kind='realtime' if table else 'dynamic-realtime',target=table[1] if table else None,
                    schema=schema[1] if schema else None,code=text[call.start():call.end()].strip()))
            for n, line in enumerate(text.splitlines(), 1):
                # Worker/MCP adapters also call PostgREST directly. A dynamic
                # URL remains unresolved; its presence is not a reachability proof.
                if '/rest/v1/rpc/' in line:
                    m = re.search(r'/rest/v1/rpc/([a-z][a-z0-9_]+)', line)
                    (test_callsites if test_source else callsites).append(dict(source=rel,line=n,
                        kind='rpc-url' if m else 'dynamic-rpc-url',target=m[1] if m else None,code=line.strip()))
                if re.search(r'Deno\.serve|addEventListener\(.fetch|^\s*(?:async\s+)?(?:fetch|scheduled|queue)\s*\(|(?:fetch|scheduled|queue)\s*:\s*[a-zA-Z_]|server\.register|registerTool\(|authorizeOperation|authorizeContext', line):
                    (test_boundaries if test_source else boundaries).append(dict(source=rel,line=n,code=line.strip()))
    return dict(sourceHead=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
                notice='Candidates only. Unclassified is an open gate, not inferred policy coverage.',
                functions=functions, sqlAuthorizationEdges=sql_edges, callsites=callsites,
                transportBoundaries=boundaries, sourcePolicies=policies, sourceGrants=grants,
                testCallsites=test_callsites,testTransportBoundaries=test_boundaries,
                dynamicSqlCandidates=dynamic)


if __name__ == '__main__':
    result = inventory()
    DEST.parent.mkdir(parents=True, exist_ok=True)
    DEST.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k:len(v) for k,v in result.items() if isinstance(v,list)}))
