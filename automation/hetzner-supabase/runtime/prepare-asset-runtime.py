#!/usr/bin/env python3
"""Prepare canonical Compose/Envoy inputs in a NEW directory, without activation.

Requires the distribution's python3-yaml. Inputs contain configuration only;
runtime .env, customer data and Storage volumes are never read or changed.
"""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import re

import yaml

RETIRED = {'storage', 'imgproxy'}


def prepare(compose, clusters, listeners):
    compose, clusters, listeners = copy.deepcopy((compose, clusters, listeners))
    if not RETIRED <= compose['services'].keys():
        raise ValueError('expected_pinned_source_services_missing')
    for name in RETIRED:
        del compose['services'][name]
    for service in compose['services'].values():
        dependencies = service.get('depends_on')
        if isinstance(dependencies, (dict, list)) and RETIRED.intersection(dependencies):
            raise ValueError('unreviewed_remaining_storage_consumer')
    resources = clusters['resources']
    if sum(item.get('name') == 'storage' for item in resources) != 1:
        raise ValueError('expected_source_cluster_missing')
    clusters['resources'] = [item for item in resources if item.get('name') != 'storage']
    removed = 0

    def remove_routes(value):
        nonlocal removed
        if isinstance(value, dict):
            for key, child in value.items():
                if key == 'routes' and isinstance(child, list):
                    retained = []
                    for route in child:
                        if route.get('route', {}).get('cluster') == 'storage':
                            if route.get('match', {}).get('prefix') != '/storage/v1/':
                                raise ValueError('unreviewed_storage_route')
                            removed += 1
                        else:
                            retained.append(route)
                    value[key] = retained
                else:
                    remove_routes(child)
        elif isinstance(value, list):
            for child in value:
                remove_routes(child)
    remove_routes(listeners)
    if removed != 1:
        raise ValueError('expected_source_route_missing')
    # Refuse a new upstream consumer rather than silently removing its contract.
    for document in (compose, clusters, listeners):
        text = json.dumps(document)
        if re.search(r'"(?:storage|imgproxy)"|(?:storage|imgproxy):50(?:00|01)|/storage/v1', text):
            raise ValueError('unreviewed_remaining_storage_consumer')
    return compose, clusters, listeners


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compose-dir', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    args = parser.parse_args()
    os.umask(0o077)
    names = ['docker-compose.yml', 'volumes/api/envoy/cds.yaml', 'volumes/api/envoy/lds.template.yaml']
    original = [(args.compose_dir / name).read_bytes() for name in names]
    result = prepare(*(yaml.safe_load(body) for body in original))
    args.output_dir.mkdir(mode=0o700, exist_ok=False)
    receipt = {'version': 1, 'production_mutations': False, 'retired_services': sorted(RETIRED), 'files': {}}
    for name, before, document in zip(names, original, result):
        target = args.output_dir / name
        target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        body = yaml.safe_dump(document, sort_keys=False).encode()
        target.write_bytes(body)
        receipt['files'][name] = {'source_sha256': hashlib.sha256(before).hexdigest(),
                                 'prepared_sha256': hashlib.sha256(body).hexdigest()}
    (args.output_dir / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print('Prepared canonical Compose/Envoy configuration; no service or source file changed')


if __name__ == '__main__':
    main()
