#!/usr/bin/env python3
"""Fail closed on pub validation failures; always replace the status report."""
import json,pathlib,re,sys
results=[]
for name in sys.argv[1:]:
 text=pathlib.Path(name).read_text()
 counts=[int(n) for n in re.findall(r'(?:Package\s+has|(?:Package\s+)?validation\s+found(?:\s+the\s+following)?)[\s:]+(\d+)\s+errors?',text,re.I)]
 if re.search(r'validation found (?:the following )?error\s*:',text,re.I):counts.append(1)
 warnings=re.findall(r'Package has (\d+) warnings?',text,re.I)
 healthy_summary=bool(re.search(r'Package has (?:\d+ warnings?|no warnings)|Package validation found no issues',text,re.I))
 failures=[]
 if 'Creating .tar.gz stream containing:' not in text:failures.append('missing pub archive selection')
 if 'Validating package finished' not in text:failures.append('validation did not finish')
 if not healthy_summary:failures.append('missing positive validation summary')
 if counts and max(counts):failures.append('package validation errors')
 if re.search(r'^\s*ERR\s*:',text,re.M):failures.append('pub ERR diagnostic')
 analyzer='`dart analyze` found the following issue' in text
 if analyzer:failures.append('package analyzer issues')
 result={'log':name,'errors':max(counts) if counts else 0 if healthy_summary else None,'warnings':int(warnings[-1]) if warnings else 0 if healthy_summary else None,'validated':'Validating package finished' in text,'analyzerIssues':analyzer,'passed':not failures,'failureReasons':failures}
 exit_path=pathlib.Path(name).with_suffix('.exit-code')
 if exit_path.exists():result['exitCode']=int(exit_path.read_text().strip())
 results.append(result)
if not results:raise SystemExit('No pub logs provided')
pathlib.Path(sys.argv[1]).parent.joinpath('publish-status.json').write_text(json.dumps(results,indent=2)+'\n')
if any(not r['passed'] for r in results):raise SystemExit(json.dumps(results))
print('Pub archive selections validated; warnings and actual exit codes recorded.')
