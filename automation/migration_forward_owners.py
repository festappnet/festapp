"""One declarative owner check for immutable migrations and explicit forwards.

History is checksum pinned. Only a registered later source owner may supersede
an old block; current function bodies must still match effective migration head.
No assembler is imported or executed by this module.
"""
from functools import lru_cache
import hashlib
import json
from pathlib import Path
import re
import migration_inputs


def registry(root: Path):
    return json.loads(migration_inputs.read_text(root / 'automation/migration-forward-owners.json'))['migrations']


def manifest(root: Path, entry):
    return json.loads(migration_inputs.read_text(root / 'automation' / entry['manifest'])) if 'manifest' in entry else entry


def sources(root: Path, entry):
    return manifest(root, entry).get(entry.get('sourceKey', 'sources'), [])


def entry_for(root: Path, migration):
    return next(e for e in registry(root) if e['migration'] == migration)


def forward_sources(root: Path, after=''):
    return frozenset(s for e in registry(root) if e['migration'] > after for s in sources(root, e))


def render_forward(root: Path, entry):
    config = manifest(root, entry)
    parts = [config['header']]
    for source in sources(root, entry):
        parts.append('-- SOURCE: ' + source + '\n' + migration_inputs.read_text(root / 'database/functions' / source).rstrip())
    return root / 'supabase/migrations' / entry['migration'], '\n\n'.join(parts) + '\n'


def historical_text(root: Path, migration: str):
    target = root / 'supabase/migrations' / migration
    digest = entry_for(root, migration).get('sha256')
    if digest is None or hashlib.sha256(migration_inputs.read_bytes(target)).hexdigest() != digest:
        raise SystemExit('Immutable migration bytes changed: ' + migration)
    return migration_inputs.read_text(target)


def historical_source(root: Path, migration: str, source: str):
    text = historical_text(root, migration)
    sections = list(re.finditer(r'^-- (?:SOURCE|Source): ([^\n]+)\n', text, re.M))
    for index, section in enumerate(sections):
        if section.group(1).removeprefix('database/functions/') == source.removeprefix('database/functions/'):
            end = sections[index + 1].start() if index + 1 < len(sections) else len(text)
            body = text[section.end():end].strip()
            # One outer execution-role wrapper precedes the first hardening source.
            if body.startswith('SET LOCAL ROLE postgres;\n'):
                body = body.removeprefix('SET LOCAL ROLE postgres;\n').lstrip()
            for suffix in ('\nRESET ROLE;', '\nCOMMIT;'):
                if body.endswith(suffix):
                    body = body[:-len(suffix)].rstrip()
            return body
    raise SystemExit('Historical migration has no source block: ' + source)


def selected_source(root: Path, entry, source):
    text = migration_inputs.read_text(root / 'database/functions' / source)
    names = manifest(root, entry).get('selectors', {}).get(source)
    if names:
        blocks = [re.search(r'CREATE OR REPLACE FUNCTION public\.' + re.escape(name) + r'\([\s\S]*?\$\$;', text) for name in names]
        if not all(blocks):
            raise SystemExit('Missing selected canonical function: ' + source)
        text = '\n'.join(block.group(0) for block in blocks)
    return text.strip()


def check_runtime_source(root: Path, source):
    """A function-only owner cannot silently reacquire migration side effects."""
    from generate_canonical_source_contract import statements
    for statement in statements(migration_inputs.read_text(root / 'database/functions' / source)):
        sql = re.sub(r'(?s)^(?:\s|--[^\n]*(?:\n|$)|/\*.*?\*/)*', '', statement)
        if sql and not re.match(r'(?:CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION|REVOKE\s+ALL\s+ON\s+FUNCTION|GRANT\s+EXECUTE\s+ON\s+FUNCTION)\b', sql, re.I):
            raise SystemExit('Runtime function source contains migration-only SQL: ' + source)


def check_frozen(root: Path, migration):
    entry = entry_for(root, migration)
    historical_text(root, migration)
    later = forward_sources(root, after=migration)
    function_only = set(entry.get('functionOnlySources', []))
    for source in function_only:
        check_runtime_source(root, source)
    for source in sources(root, entry):
        if source not in later and source not in function_only and selected_source(root, entry, source) != historical_source(root, migration, source).strip():
            raise SystemExit('Unplanned canonical source drift: ' + source)
    check_effective_sources(root, sources(root, entry))


@lru_cache(maxsize=None)
def verify_forward(root: Path):
    for entry in registry(root):
        if entry.get('active'):
            target, expected = render_forward(root, entry)
            if not migration_inputs.exists(target) or migration_inputs.read_text(target) != expected:
                raise SystemExit('Explicit forward is missing or stale: ' + entry['migration'])
        elif entry.get('checkSources'):
            check_frozen(root, entry['migration'])
        else:
            historical_text(root, entry['migration'])


def check_effective_sources(root: Path, source_list):
    from generate_canonical_source_contract import definitions
    effective = {}
    for migration in sorted(migration_inputs.migration_paths(root)):
        for signature, body in definitions(migration_inputs.read_text(migration)):
            if isinstance(body, tuple):
                if signature in effective:
                    effective[body[1]] = effective.pop(signature)
            elif body is None:
                effective.pop(signature, None)
            else:
                effective[signature] = body
    for source in source_list:
        for signature, body in definitions(migration_inputs.read_text(root / 'database/functions' / source)):
            if body is not None and not isinstance(body, tuple) and effective.get(signature) != body:
                raise SystemExit('Canonical owner differs from effective migration head: ' + signature)


def migration_cli(*migrations):
    """Thin existing CLI adapters share rendering, frozen checks and refusal rules."""
    import argparse
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description='Check immutable history or assemble an explicit current forward.')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    entries = [entry_for(root, name) for name in migrations]
    if not args.check and any(not entry.get('active') for entry in entries):
        raise SystemExit('Installed migration is immutable; create an explicit forward')
    for entry in entries:
        if entry.get('active'):
            target, expected = render_forward(root, entry)
            if args.check:
                if not migration_inputs.exists(target) or migration_inputs.read_text(target) != expected:
                    raise SystemExit('Explicit forward is missing or stale: ' + entry['migration'])
            else:
                migration_inputs.write_text(target, expected)
        else:
            check_frozen(root, entry['migration'])
    if args.check:
        print('Immutable history and canonical owners match')
