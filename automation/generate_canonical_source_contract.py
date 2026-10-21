#!/usr/bin/env python3
"""Generate catalog body contracts from the effective baseline/forward SQL, never a live DB."""
import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / 'automation/canonical-source-contract.json'
TARGET = ROOT / 'database/tests/canonical_mutation_source_parity_test.sql'


def statements(sql):
    """Split top-level SQL, leaving comments, quoted values and function bodies intact."""
    start = pos = 0
    while pos < len(sql):
        if sql.startswith('--', pos):
            end = sql.find('\n', pos)
            pos = len(sql) if end < 0 else end + 1
        elif sql.startswith('/*', pos):
            depth = 1
            pos += 2
            while depth:
                if pos >= len(sql):
                    raise ValueError('Unclosed SQL comment')
                if sql.startswith('/*', pos):
                    depth += 1
                    pos += 2
                elif sql.startswith('*/', pos):
                    depth -= 1
                    pos += 2
                else:
                    pos += 1
        elif sql[pos] in "'\"":
            quote = sql[pos]
            escaped = quote == "'" and pos > 0 and sql[pos - 1] in 'Ee' and (pos < 2 or not sql[pos - 2].isalnum())
            pos += 1
            while pos < len(sql):
                if escaped and sql[pos] == '\\':
                    pos += 2
                elif sql[pos] == quote:
                    pos += 1
                    if pos < len(sql) and sql[pos] == quote:
                        pos += 1
                    else:
                        break
                else:
                    pos += 1
            else:
                raise ValueError('Unclosed SQL quote')
        elif sql[pos] == '$' and (m := re.match(r'\$(?:[A-Za-z_]\w*)?\$', sql[pos:])):
            tag = m[0]
            end = sql.find(tag, pos + len(tag))
            if end < 0:
                raise ValueError('Unclosed dollar quote')
            pos = end + len(tag)
        elif sql[pos] == ';':
            yield sql[start:pos + 1]
            pos += 1
            start = pos
        else:
            pos += 1
    if sql[start:].strip():
        yield sql[start:]


def split_args(text):
    # Defaults may contain quoted commas, function calls, or array constructors.
    parts, start, depth, quote = [], 0, 0, None
    i = 0
    while i < len(text):
        c = text[i]
        if quote:
            if c == quote:
                if i + 1 < len(text) and text[i + 1] == quote:
                    i += 1
                else:
                    quote = None
        elif c in "'\"":
            quote = c
        elif c in '([':
            depth += 1
        elif c in ')]':
            depth -= 1
        elif c == ',' and depth == 0:
            parts.append(text[start:i])
            start = i + 1
        i += 1
    return [x.strip() for x in parts + [text[start:]] if x.strip()]


def identity(name, args, declaration=False):
    types = []
    for arg in split_args(args):
        arg = re.split(r'\bDEFAULT\b|\s+=\s+', arg, maxsplit=1, flags=re.I)[0].strip()
        words = arg.replace('"', '').lower().split()
        if words[0] == 'out':
            continue
        if words[0] in ('in', 'inout', 'variadic'):
            words = words[1:]
        if declaration:
            # All authored release declarations use named input parameters.
            words = words[1:]
        typ = ' '.join(words).replace('pg_catalog.', '')
        typ = {'int8': 'bigint', 'int4': 'integer', 'int': 'integer', 'bool': 'boolean',
               'float8': 'double precision', 'timestamptz': 'timestamp with time zone',
               'varchar': 'character varying'}.get(typ, typ)
        if not typ:
            raise ValueError(f'Cannot parse argument: {arg}')
        types.append(typ)
    name = name.replace('"', '').lower()
    if '.' not in name:
        name = 'public.' + name
    return name + '(' + ','.join(types) + ')'


NAME = r'(?:"?\w+"?\.)?"?\w+"?'
CREATE = re.compile(r'CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(' + NAME + r')\s*\((.*?)\)\s*RETURNS\b(.*?)\bAS\s+(\$(?:\w*)\$)(.*?)\4', re.I | re.S)
RENAME = re.compile(r'ALTER\s+FUNCTION\s+(' + NAME + r')\s*\((.*?)\)\s+RENAME\s+TO\s+(\"?\w+\"?)\s*;?$', re.I | re.S)
DROP = re.compile(r'DROP\s+FUNCTION\s+(?:IF\s+EXISTS\s+)?(.*?)(?:\s+(?:CASCADE|RESTRICT))?\s*;?$', re.I | re.S)


def definitions(sql):
    for statement in statements(sql):
        # Remove only leading comments, never comments inside a function body.
        head = re.sub(r'\A(?:\s|--[^\n]*(?:\n|$)|/\*.*?\*/)*', '', statement, flags=re.S)
        if head.upper().startswith('CREATE') and re.match(r'CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\b', head, re.I):
            m = CREATE.match(head)
            if not m:
                raise ValueError('Unsupported function definition: ' + head[:120])
            yield identity(m[1], m[2], True), m[5].strip(' \n\r\t')
        elif (m := RENAME.match(head)):
            previous = identity(m[1], m[2])
            schema = previous.split('.', 1)[0]
            yield previous, ('rename', identity(schema + '.' + m[3], m[2]))
        elif (m := DROP.match(head)):
            for entry in split_args(m[1].rstrip(';').strip()):
                name, args = entry.split('(', 1)
                yield identity(name.strip(), args.rsplit(')', 1)[0]), None


def command_transaction_owners(selected):
    """One receipt owner per literal operation ID, regardless of function name.

    Signed/anonymous admission branches inside the same function are one owner.
    This is scoped to the selected commands, not a general SQL call-graph parser.
    """
    owners = {}
    pattern = r"\bbegin_(?:anonymous_|unit_)?client_mutation_v1\s*\(\s*[^,]+,\s*'([^']+)'"
    for signature, body in selected.items():
        for operation in re.findall(pattern, body, re.I):
            owners.setdefault(operation, set()).add(signature)
    for operation, signatures in owners.items():
        if len(signatures) > 1:
            raise ValueError(f'Multiple transaction owners for {operation}: {sorted(signatures)}')
    return owners


def render(root=ROOT):
    config = json.loads((root / 'automation/canonical-source-contract.json').read_text())
    manifest = json.loads((root / config['operationsManifest']).read_text())
    selected, effective = {}, {}
    for source in manifest['sources']:
        for signature, body in definitions((root / 'database/functions' / source).read_text()):
            if body is not None:
                selected[signature] = body
    command_transaction_owners(selected)
    baseline = json.loads((root / config['baselineManifest']).read_text())
    inputs = [root / baseline['schema']['path']]
    inputs += sorted(x for x in (root / 'supabase/migrations').glob('*.sql') if x.name[:14] > baseline['coveredThrough'])
    for path in inputs:
        for signature, body in definitions(path.read_text()):
            if isinstance(body, tuple):
                if signature not in effective or effective[signature][0] is None:
                    raise ValueError(f'Rename of unknown function: {signature}')
                effective[body[1]] = (effective[signature][0], path.relative_to(root).as_posix())
                effective[signature] = (None, path.relative_to(root).as_posix())
            else:
                effective[signature] = (body, path.relative_to(root).as_posix())
    for signature, body in selected.items():
        if effective.get(signature, (None,))[0] != body:
            raise ValueError(f'Authored source not effective at release head: {signature}')
    retired = set(config.get('retiredSignatures', []))
    for signature in retired:
        if signature in selected or effective.get(signature, (None,))[0] is not None:
            raise ValueError(f'Retired implementation remains reachable: {signature}')
    signatures = sorted(set(selected) | set(config['retainedSignatures']) | retired)
    lines = ['-- Generated by python3 automation/generate_canonical_source_contract.py.',
             '-- Effective baseline + forward definitions; no database-derived hashes.',
             '-- Retained historical identities remain checked, including absent obsolete helpers.',
             'DO $$ BEGIN']
    for signature in signatures:
        body, owner = effective.get(signature, (None, 'absent from the effective release'))
        lines.append('-- ' + owner)
        if body is None:
            lines.append(f" PERFORM assert_true(to_regprocedure('{signature}') IS NULL,'retired SQL identity remains absent: {signature}');")
        else:
            digest = hashlib.md5(body.encode()).hexdigest()
            lines.append(f" PERFORM assert_true(EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('{signature}') AND md5(btrim(prosrc,E' \\n\\r\\t'))='{digest}'),'current SQL source parity: {signature}');")
    return '\n'.join(lines + ['END $$;', ''])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--print', action='store_true', dest='print_sql')
    args = parser.parse_args()
    sql = render()
    if args.print_sql:
        print(sql, end='')
    elif args.check:
        if TARGET.read_text() != sql:
            raise SystemExit('Canonical SQL source contract is stale; regenerate it explicitly.')
    else:
        TARGET.write_text(sql)


if __name__ == '__main__':
    main()
