"""Compare executed semantic cases, including groups and skips, across moves."""
from collections import Counter
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "automation/client_test_inventory.json"


def is_semantic_case(test):
    # Synthetic discovery has no source location. A real widget regression is
    # named "loading is visible ..." and must remain an executed semantic case.
    loading = (test["name"].startswith("loading ")
               and test.get("url") is None and test.get("root_url") is None)
    return not loading and not test["name"].endswith(("(setUpAll)", "(tearDownAll)"))


def cases(paths, moves):
    found = []
    for path in paths:
        suites = {}
        for line in path.read_text().splitlines():
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            if event.get("type") == "suite":
                suites[event["suite"]["id"]] = event["suite"].get("path")
                continue
            if event.get("type") != "testStart":
                continue
            test = event["test"]
            if not is_semantic_case(test):
                continue
            def relative(value):
                return value.removeprefix("file://").removeprefix(str(ROOT) + "/")
            source = relative(suites.get(test.get("suiteID")) or test.get("root_url") or test.get("url") or "")
            case_source = relative(test.get("url") or "")
            # testWidgets may report widget_tester.dart rather than the case
            # source. Resolve that only through a documented entrypoint/group,
            # never through an arbitrary matching test name.
            name = test["name"]
            relocation = moves.get(case_source)
            if relocation is None:
                grouped = [value for value in moves.values() if isinstance(value, dict)
                           and value.get("entrypoint") == source
                           and name.startswith(value["added_group"] + " ")]
                # Nested registered groups have nested documented prefixes.
                # Select the most specific explicit registration path; two
                # different origins for that same path remain an error.
                grouped.sort(key=lambda value: len(value["added_group"]), reverse=True)
                if len(grouped) > 1 and grouped[0]["added_group"] == grouped[1]["added_group"]:
                    raise ValueError(f"Ambiguous documented origin: {source}: {name}")
                relocation = grouped[0] if grouped else moves.get(source, source)
            if isinstance(relocation, dict):
                source = relocation["source"]
                prefix = relocation["added_group"] + " "
                if not name.startswith(prefix):
                    raise ValueError(f"Missing documented group prefix {prefix!r}: {name!r}")
                name = name[len(prefix):]
            else:
                source = relocation
            found.append((source, name, bool(test["metadata"]["skip"])))
    return Counter(found)


def main():
    mode, location = sys.argv[1:]
    if mode == "baseline":
        inventory = cases([Path(location)], {})
        MANIFEST.write_text(json.dumps({"moves": {}, "cases": [list(key) + [count] for key, count in sorted(inventory.items())]}, ensure_ascii=False, separators=(',', ':')) + "\n")
        print(f"Baseline: {sum(inventory.values())} semantic cases")
        return 0
    manifest = json.loads(MANIFEST.read_text())
    expected = Counter({tuple(row[:3]): row[3] for row in manifest["cases"]})
    actual = cases(sorted(Path(location).glob("*.jsonl")), manifest["moves"])
    missing, added = expected - actual, actual - expected
    # New behavior cases are allowed; duplicate executions of existing cases are not.
    duplicates = {key: count for key, count in actual.items() if count > 1}
    if missing or duplicates:
        print(f"Inventory FAILED: {len(missing)} missing, {len(duplicates)} duplicated", file=sys.stderr)
        for key in list(missing)[:15]:
            print(f"Missing: {key}", file=sys.stderr)
        for key in list(duplicates)[:15]:
            print(f"Duplicate: {key}", file=sys.stderr)
        return 1
    revisions = len(manifest.get('baseline_revisions', []))
    print(f"Inventory: {sum(expected.values())} baseline cases accounted for, {sum(added.values())} added; {revisions} documented contract revisions")
    return 0


if __name__ == "__main__":
    sys.exit(main())
