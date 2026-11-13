#!/usr/bin/env python3
"""Guard selected canonical Function releases against exact installed bytes.

Selected releases never replace shared modules, dependencies, locks or router.
A changed shared dependency requires a coordinated full release instead.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil


def require(value, message):
    if not value:
        raise ValueError(message)


def digest(value):
    return hashlib.sha256(value).hexdigest()


def imports(path):
    if path.suffix not in ('.ts', '.js', '.mjs'):
        return []
    text = path.read_text()
    require(not re.search(r'\b(?:import|require)\s*\(\s*[^\s\"\']', text),
            'Non-literal module dependency requires a full release')
    require(not re.search(r'\b(?:readFile(?:Sync)?|readTextFile(?:Sync)?|readDir(?:Sync)?|createWorker|Worker)\s*\(', text),
            'Filesystem/worker dependency requires a full release')
    return sorted(set(re.findall(r'(?:\bfrom\s*|\bimport\s*(?:\(\s*)?)[\"\']([^\"\']+)[\"\']', text)))


def inventory(root):
    root = root.resolve()
    files = {}
    for path in sorted(root.rglob('*')):
        require(not path.is_symlink(), 'Function tree contains a symlink')
        if path.is_file():
            files[path.relative_to(root).as_posix()] = digest(path.read_bytes())
    return {'version': 1, 'files': files, 'tree_sha256': digest(json.dumps(files, sort_keys=True, separators=(',', ':')).encode())}


def module_closure(root, functions):
    root = root.resolve()
    pending = [root / name / 'index.ts' for name in functions]
    seen, external = set(), set()
    while pending:
        path = pending.pop().resolve()
        require(path.is_relative_to(root) and path.is_file() and not path.is_symlink(), 'Missing or unsafe module dependency')
        relative = path.relative_to(root).as_posix()
        if relative in seen:
            continue
        seen.add(relative)
        for target in imports(path):
            if target.startswith('.'):
                pending.append(path.parent / target)
            else:
                require(target.startswith(('https://', 'jsr:', 'npm:')), 'Unresolved module dependency requires a full release')
                external.add(target)
    return seen, external


def selection(source, base, functions):
    require(functions and len(set(functions)) == len(functions), 'Invalid Function selection')
    require(all(re.fullmatch(r'[a-z][a-z0-9-]+', name) and name not in ('main', 'hello', 'instance-install') for name in functions), 'Invalid Function name')
    require(base.get('version') == 1 and base.get('tree_sha256') == digest(json.dumps(base['files'], sort_keys=True, separators=(',', ':')).encode()), 'Invalid base inventory')
    closure, external = module_closure(source, functions)
    dependencies = {name: digest((source / name).read_bytes()) for name in sorted(closure) if name.split('/')[0] not in functions}
    require(all(base['files'].get(name) == value for name, value in dependencies.items()), 'Shared dependency differs from installed canonical owner; coordinate a full release')
    # External specs must already exist in the installed lock; selected releases
    # cannot upgrade or silently fetch a new dependency graph.
    lock = source / 'deno.lock'
    require(base['files'].get('deno.lock') == digest(lock.read_bytes()), 'Dependency lock differs; coordinate a full release')
    return {'functions': sorted(functions), 'base_runtime_sha256': base['tree_sha256'],
            'dependencies': dependencies, 'external_imports': sorted(external),
            'lock_sha256': base['files']['deno.lock']}


def stage(current, stage, manifest):
    selected = manifest['selection']
    require(inventory(current)['tree_sha256'] == selected['base_runtime_sha256'], 'Installed Function tree changed since selection')
    allowed = selected['functions']
    require(set(p.name for p in stage.iterdir()) == set(allowed), 'Selected archive has unexpected paths')
    for name in allowed:
        require(re.fullmatch(r'[a-z][a-z0-9-]+', name) and name not in ('main', 'hello', 'instance-install'), 'Unsafe selected Function')
        require((stage / name).is_dir() and not (stage / name).is_symlink(), 'Missing selected Function directory')
    # Verify dependencies from the actual extracted source, not only the manifest.
    candidate = stage.parent / (stage.name + '.verify')
    require(not candidate.exists(), 'Verification stage already exists')
    try:
        shutil.copytree(current, candidate)
        for name in allowed:
            shutil.rmtree(candidate / name)
            shutil.copytree(stage / name, candidate / name)
        actual = selection(candidate, inventory(current), allowed)
        require(actual == selected, 'Selected dependency manifest does not match source')
        before, after = inventory(current)['files'], inventory(candidate)['files']
        unchanged = lambda values: {name: value for name, value in values.items() if name.split('/')[0] not in allowed}
        require(unchanged(before) == unchanged(after), 'Unselected Function bytes changed')
        for path in current.iterdir():
            if path.name in allowed:
                continue
            if path.is_dir():
                shutil.copytree(path, stage / path.name)
            else:
                shutil.copy2(path, stage / path.name)
    finally:
        shutil.rmtree(candidate, ignore_errors=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['inventory', 'select', 'stage'])
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--base', type=Path)
    parser.add_argument('--functions')
    parser.add_argument('--stage', type=Path)
    parser.add_argument('--manifest', type=Path)
    args = parser.parse_args()
    if args.command == 'inventory':
        print(json.dumps(inventory(args.root), sort_keys=True))
    elif args.command == 'select':
        print(json.dumps(selection(args.root, json.loads(args.base.read_text()), args.functions.split(',')), sort_keys=True))
    else:
        stage(args.root, args.stage, json.loads(args.manifest.read_text()))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError) as error:
        raise SystemExit('Selected Function release refused: ' + str(error)) from None
