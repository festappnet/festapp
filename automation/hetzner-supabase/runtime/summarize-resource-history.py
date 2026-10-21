#!/usr/bin/env python3
"""Summarize existing numeric host history offline; never proposes safe hard caps."""
import argparse
import json
from pathlib import Path


def summarize(samples, budget):
    samples = sorted(samples, key=lambda s: s['at'])
    if not samples or len({s['at'] for s in samples}) != len(samples):
        raise ValueError('history must contain unique timestamps and at least one sample')
    containers = {}
    simultaneous = []
    expected = {c['name'] for s in samples for c in s['containers']}
    incomplete = 0
    for sample in samples:
        current = {c['name']: c for c in sample['containers'] if not c.get('unavailable')}
        complete = set(current) == expected
        incomplete += not complete
        if complete:
            simultaneous.append(sum(c['memory_bytes'] for c in current.values()))
        for name, c in current.items():
            entry = containers.setdefault(name, {'samples': 0, 'max_memory_bytes': 0,
                                                'max_working_set_bytes': 0, 'max_pids': 0})
            entry['samples'] += 1
            for source, target in [('memory_bytes', 'max_memory_bytes'),
                                   ('working_set_bytes', 'max_working_set_bytes'), ('pids', 'max_pids')]:
                entry[target] = max(entry[target], c[source])
    totals = {s['host']['MemTotal'] for s in samples}
    if len(totals) != 1:
        raise ValueError('split histories across host memory changes')
    host_memory = totals.pop()
    admin_names = {'/supabase-' + name for name in budget['admin_limits']}
    if not admin_names <= expected:
        raise ValueError('missing budgeted admin container observations')
    reserves = budget['reserve_policy']
    admin_caps = sum(c['mem_limit'] for c in budget['admin_limits'].values())
    available = (host_memory - admin_caps - reserves['os_headroom_target_bytes']
                 - reserves['logical_backup_transient_target_bytes'])
    other_maxima = sum(c['max_working_set_bytes'] for name, c in containers.items()
                       if name not in admin_names)
    gaps = [b['at'] - a['at'] for a, b in zip(samples, samples[1:])]
    database = [s['database'] for s in samples if 'database' in s]
    edge = [s['edge'] for s in samples if 'edge' in s]
    return {
        'first_at': samples[0]['at'], 'last_at': samples[-1]['at'], 'samples': len(samples),
        'span_seconds': samples[-1]['at'] - samples[0]['at'],
        'largest_sample_gap_seconds': max(gaps, default=0),
        'incomplete_container_samples': incomplete,
        'host_memory_bytes': host_memory,
        'min_host_available_memory_bytes': min(s['host']['MemAvailable'] for s in samples),
        'max_simultaneously_sampled_container_memory_bytes': max(simultaneous, default=None),
        'valid_database_samples': len(database), 'valid_edge_samples': len(edge),
        'max_sampled_database_connections': max((s['connections'] for s in database), default=None),
        'max_sampled_active_database_connections': max((s['active'] for s in database), default=None),
        'max_sampled_live_edge_workers': max((s['activeUserWorkersCount'] for s in edge), default=None),
        'container_maxima': containers,
        'feasibility_screen': {
            'admin_hard_cap_sum_bytes': admin_caps,
            'os_reserve_target_bytes': reserves['os_headroom_target_bytes'],
            'logical_backup_reserve_target_bytes': reserves['logical_backup_transient_target_bytes'],
            'remaining_for_other_containers_bytes': available,
            'sum_nonsimultaneous_other_working_set_maxima_bytes': other_maxima,
            'shortfall_before_safety_margin_bytes': max(0, other_maxima - available),
            'fits_conservative_criteria': other_maxima <= available,
        },
        'representative_business_peak_proven': False,
        'whole_host_hard_cap_budget_complete': False,
        'note': 'Minute samples miss transient peaks. Working sets exclude inactive file cache; '
                'hard memory caps include it. Nonsimultaneous maxima and reserve targets are '
                'a feasibility screen, not cap recommendations or proof that paid resize is required.',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('history', nargs='+', type=Path)
    parser.add_argument('--budget', required=True, type=Path)
    args = parser.parse_args()
    samples = [json.loads(line) for path in args.history for line in path.read_text().splitlines() if line.strip()]
    print(json.dumps(summarize(samples, json.loads(args.budget.read_text())), indent=2))


if __name__ == '__main__':
    main()
