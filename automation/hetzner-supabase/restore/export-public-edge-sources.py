#!/usr/bin/env python3
"""Export only public Edge source files; never copy runtime.env to a build host."""
import argparse,json,os
from pathlib import Path
from edge_smoke import function_sources,public_tar,source_digest
p=argparse.ArgumentParser();p.add_argument('--runtime-archive',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
os.umask(0o077);assert not a.output.exists(),'choose a new public-source export path'
files=function_sources(a.runtime_archive)
with a.output.open('xb') as stream:stream.write(public_tar(files))
print(json.dumps({'public_source_sha256':source_digest(files),'source_files':len(files),'runtime_env_exported':False}))
