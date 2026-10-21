#!/usr/bin/env python3
"""Verify actual import directions; fixtures and documentation are not imports."""
import argparse,pathlib,re
parser=argparse.ArgumentParser();parser.add_argument('--host',type=pathlib.Path);args=parser.parse_args()
root=pathlib.Path(__file__).resolve().parent.parent
errors=[];count=0
for directory in [root/'lib',root/'packages/venue_layout_core/lib',root/'web/src']:
 for path in directory.rglob('*'):
  if path.suffix not in {'.dart','.js','.ts'}:continue
  text=path.read_text();imports=re.findall(r"(?:import|export)\s+(?:[^;]*?\s+from\s+)?[\"']([^\"']+)[\"']",text)
  for uri in imports:
   count+=1
   if re.search(r'(?:package:|@)(?:fstapp|festapp_core|supabase)(?:[/_:]|$)',uri) or 'supabase-js' in uri:errors.append(f'{path.relative_to(root)}: forbidden host dependency {uri}')
   if 'venue_layout_core/lib' in str(path) and (uri.startswith('dart:ui') or uri.startswith('package:flutter')):errors.append(f'{path}: Flutter dependency in core {uri}')
  if path.suffix in {'.js','.ts'} and re.search(r'https?://[^\s\"\']*(?:festapp\.net|supabase\.(?:co|com))',text):errors.append(f'{path}: hardcoded host endpoint')
if args.host:
 for path in (args.host/'lib').rglob('*.dart'):
  for uri in re.findall(r"(?:import|export)\s+[\"']([^\"']+)[\"']",path.read_text()):
   if uri.startswith('package:venue_seat_picker/src/'):errors.append(f'{path}: private package import {uri}')
if errors:raise SystemExit('\n'.join(errors))
print(f'Architecture import gate passed ({count} production imports).')
