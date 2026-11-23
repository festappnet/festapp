#!/usr/bin/env python3
"""Guard selected canonical Function releases against exact installed bytes.

Shared modules change only when individually selected and pinned in the manifest.
Every other installed module, dependency, lock and router remains unchanged.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil


AUTHORING_CONTEXT = 'send-custom-email/authoringContext.ts'
AUTHORING_QR_IMPORTS = {'node:buffer', '../_shared/qrCodePayment.ts'}
AUTHORING_QR_RESOURCES = (
    '_shared/qrCodePayment.ts',
    '_shared/paymentQrArtwork.ts',
    '_shared/ticket-assets/roboto.ttf',
)


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


def module_closure(root, functions, shared_modules):
    root = root.resolve()
    pending = [root / name / 'index.ts' for name in functions]
    pending.extend(root / name for name in shared_modules)
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
                require(target.startswith(('https://', 'jsr:', 'npm:', 'node:')), 'Unresolved module dependency requires a full release')
                external.add(target)
    return seen, external


def selection(source, base, functions, shared_modules=()):
    require(functions and len(set(functions)) == len(functions), 'Invalid Function selection')
    require(all(re.fullmatch(r'[a-z][a-z0-9-]+', name) and name not in ('main', 'hello', 'instance-install') for name in functions), 'Invalid Function name')
    require(base.get('version') == 1 and base.get('tree_sha256') == digest(json.dumps(base['files'], sort_keys=True, separators=(',', ':')).encode()), 'Invalid base inventory')
    require(len(set(shared_modules)) == len(shared_modules), 'Duplicate shared module selection')
    require(all(re.fullmatch(r'_shared/[A-Za-z][A-Za-z0-9_.-]*\.(?:ts|js|mjs)', name)
                and name in base['files'] and not (source / name).is_symlink()
                for name in shared_modules), 'Shared selection must name existing direct code modules')
    closure, external = module_closure(source, functions, shared_modules)
    dependencies = {name: digest((source / name).read_bytes()) for name in sorted(closure)
                    if name.split('/')[0] not in functions and name not in shared_modules}
    require(all(base['files'].get(name) == value for name, value in dependencies.items()), 'Shared dependency differs from installed canonical owner; coordinate a full release')
    # External specs must already exist in the installed lock; selected releases
    # cannot upgrade or silently fetch a new dependency graph.
    lock = source / 'deno.lock'
    require(base['files'].get('deno.lock') == digest(lock.read_bytes()), 'Dependency lock differs; coordinate a full release')
    return {'functions': sorted(functions), 'base_runtime_sha256': base['tree_sha256'],
            'shared_modules': {name: digest((source / name).read_bytes()) for name in sorted(shared_modules)},
            'dependencies': dependencies, 'external_imports': sorted(external),
            'lock_sha256': base['files']['deno.lock']}


def stage(current, stage, manifest):
    selected = dict(manifest['selection'])
    selected.setdefault('shared_modules', {})
    require(inventory(current)['tree_sha256'] == selected['base_runtime_sha256'], 'Installed Function tree changed since selection')
    allowed = selected['functions']
    shared = selected['shared_modules']
    require(isinstance(shared, dict), 'Invalid shared module manifest')
    require(set(p.name for p in stage.iterdir()) == set(allowed) | ({'_shared'} if shared else set()),
            'Selected archive has unexpected paths')
    if shared:
        require((stage / '_shared').is_dir() and not (stage / '_shared').is_symlink(), 'Unsafe shared archive directory')
        actual_shared = {'_shared/' + name: value for name, value in inventory(stage / '_shared')['files'].items()}
        require(actual_shared == shared, 'Shared archive differs from its explicit module selection')
    for name in allowed:
        require(re.fullmatch(r'[a-z][a-z0-9-]+', name) and name not in ('main', 'hello', 'instance-install'), 'Unsafe selected Function')
        require((stage / name).is_dir() and not (stage / name).is_symlink(), 'Missing selected Function directory')
    # Verify dependencies from the actual extracted source, not only the manifest.
    candidate = stage.parent / (stage.name + '.verify')
    require(not candidate.exists(), 'Verification stage already exists')
    try:
        shutil.copytree(current, candidate)
        for name in allowed:
            function = candidate / name
            if function.exists():
                shutil.rmtree(function)
            shutil.copytree(stage / name, function)
        for name in shared:
            require(re.fullmatch(r'_shared/[A-Za-z][A-Za-z0-9_.-]*\.(?:ts|js|mjs)', name), 'Unsafe shared module path')
            shutil.copy2(stage / name, candidate / name)
        actual = selection(candidate, inventory(current), allowed, shared)
        require(actual == selected, 'Selected dependency manifest does not match source')
        before, after = inventory(current)['files'], inventory(candidate)['files']
        unchanged = lambda values: {name: value for name, value in values.items()
                                    if name.split('/')[0] not in allowed and name not in shared}
        require(unchanged(before) == unchanged(after), 'Unselected Function bytes changed')
        shutil.copytree(candidate, stage, dirs_exist_ok=True)
        require(inventory(stage) == inventory(candidate), 'Staged Function tree differs from verified candidate')
    finally:
        shutil.rmtree(candidate, ignore_errors=True)


def exact_shared_plan(source, base, modules):
    require(base.get('version') == 1 and base.get('tree_sha256') ==
            digest(json.dumps(base['files'], sort_keys=True, separators=(',', ':')).encode()),
            'Invalid base inventory')
    require(modules and len(set(modules)) == len(modules), 'Invalid exact shared selection')
    planned = {}
    for name in sorted(modules):
        path = source / name
        require((name == AUTHORING_CONTEXT or re.fullmatch(
                    r'_shared/(?:[A-Za-z][A-Za-z0-9_.-]*\.(?:ts|js|mjs)|translations/translations\.[a-z]{2}\.ts)', name))
                and name in base['files'] and path.is_file()
                and path.resolve() == source.resolve() / name,
                'Exact replacement requires an existing allowed code or locale module')
        value = digest(path.read_bytes())
        require(value != base['files'][name], 'Exact shared replacement must change each selected module')
        planned[name] = value
    return {'base_runtime_sha256': base['tree_sha256'], 'shared_modules': planned}


def stage_exact_shared(current, stage, manifest):
    planned = manifest['exact_shared_replacement']
    base = inventory(current)
    require(base['tree_sha256'] == planned['base_runtime_sha256'],
            'Installed Function tree changed since selection')
    modules = planned['shared_modules']
    require(inventory(stage)['files'] == modules,
            'Exact shared archive contains unexpected bytes or paths')
    require(exact_shared_plan(stage, base, list(modules)) == planned,
            'Exact shared plan does not match the extracted source')
    directories = {stage / parent for name in modules for parent in Path(name).parents
                   if parent != Path('.')}
    require(set(stage.rglob('*')) == directories | {stage / name for name in modules},
            'Exact shared archive contains unexpected paths')
    for name in planned['shared_modules']:
        # The entire installed tree stays pinned. Compare direct imports only
        # for the replacement files and keep the existing dependency graph.
        before = set(imports(current / name))
        after = set(imports(stage / name))
        if name == AUTHORING_CONTEXT:
            # The installed tree digest also pins the QR renderer and its font.
            require(before <= after and after - before <= AUTHORING_QR_IMPORTS
                    and all(resource in base['files'] for resource in AUTHORING_QR_RESOURCES),
                    'Exact authoring replacement changes dependencies')
        else:
            require(before == after, 'Exact shared replacement changes dependencies')
    replacements = {name: (stage / name).read_bytes() for name in planned['shared_modules']}
    shutil.copytree(current, stage, dirs_exist_ok=True)
    for name, content in replacements.items():
        (stage / name).write_bytes(content)
    require(inventory(stage)['files'] == {**base['files'], **planned['shared_modules']},
            'Exact shared staging changed unselected bytes')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['inventory', 'select', 'stage', 'plan-exact-shared', 'stage-exact-shared'])
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--base', type=Path)
    parser.add_argument('--functions')
    parser.add_argument('--shared-modules', default='')
    parser.add_argument('--stage', type=Path)
    parser.add_argument('--manifest', type=Path)
    args = parser.parse_args()
    if args.command == 'inventory':
        print(json.dumps(inventory(args.root), sort_keys=True))
    elif args.command == 'select':
        print(json.dumps(selection(args.root, json.loads(args.base.read_text()), args.functions.split(','),
                                   args.shared_modules.split(',') if args.shared_modules else []), sort_keys=True))
    elif args.command == 'plan-exact-shared':
        base = json.loads(args.base.read_text())
        modules = args.shared_modules.split(',')
        if AUTHORING_CONTEXT in modules:
            require(all((args.root / name).is_file()
                        and base['files'].get(name) == digest((args.root / name).read_bytes())
                        for name in AUTHORING_QR_RESOURCES),
                    'Installed payment QR artwork dependencies differ from canonical source')
        print(json.dumps(exact_shared_plan(args.root, base, modules), sort_keys=True))
    elif args.command == 'stage-exact-shared':
        stage_exact_shared(args.root, args.stage, json.loads(args.manifest.read_text()))
    else:
        stage(args.root, args.stage, json.loads(args.manifest.read_text()))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError) as error:
        raise SystemExit('Selected Function release refused: ' + str(error)) from None
