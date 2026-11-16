"""Resolve the pinned Supabase image without changing its content or PG major."""
import json
import re
import subprocess
import sys


def references(image):
    if not re.search(r'@sha256:[0-9a-f]{64}$', image):
        raise ValueError('PostgreSQL image must be pinned by digest')
    # Both official registries serve the identical OCI index. Never fall back
    # to a mutable tag or a different digest when a registry limits downloads.
    if re.fullmatch(r'public\.ecr\.aws/supabase/postgres:[\w.-]+@sha256:[0-9a-f]{64}', image):
        return [image, image.replace('public.ecr.aws/', 'docker.io/', 1)]
    return [image]


def resolve(image, *, pull=True):
    candidates = references(image)
    def inspect(reference):
        return json.loads(subprocess.check_output(
            ['docker','image','inspect',reference], stderr=subprocess.DEVNULL))[0]
    for reference in candidates:
        try:
            return reference, inspect(reference)
        except subprocess.CalledProcessError:
            pass
    if pull:
        for reference in candidates:
            if subprocess.run(['docker','pull',reference], stdout=sys.stderr).returncode == 0:
                return reference, inspect(reference)
    raise RuntimeError('Pinned PostgreSQL image unavailable from its approved registries: '+image)


if __name__ == '__main__':
    print(resolve(sys.argv[1])[0])
