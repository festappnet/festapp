"""Own a fresh PostgreSQL container and private bridge for one CMS fixture."""
import re
import subprocess
from local_db.runtime import Runtime


class CmsPostgres:
    def __init__(self, project, port, run):
        if not re.fullmatch(r'festapp-cms-consent-[a-f0-9]{12}', project):
            raise ValueError('A unique CMS database project is required')
        self.runtime = Runtime(project=project, port=port)
        self.network = project + '-database'
        self.run = run
        self.owns_container = False
        self.owns_network = False

    def start(self):
        if self.runtime.inspect() is not None:
            raise ValueError('Refusing to reuse a CMS database container')
        volume = subprocess.run(['docker', 'volume', 'inspect', self.runtime.container],
                                capture_output=True, text=True)
        if not volume.returncode or 'no such volume' not in volume.stderr.lower():
            raise ValueError('Fresh CMS database storage could not be verified')
        self.owns_container = True
        self.runtime.start()
        self.runtime.provider()
        # The test-only service connects as authenticator across its owned bridge.
        self.runtime.sql("ALTER ROLE authenticator PASSWORD 'postgres';")
        self.run(['docker', 'network', 'create', '--label', 'net.festapp.cms-database='+self.runtime.project,
                  self.network], label='backend.network')
        self.owns_network = True
        self.run(['docker', 'network', 'connect', self.network, self.runtime.container], label='backend.network')

    def close(self):
        try:
            if self.owns_container and self.runtime.inspect() is not None:
                self.run(['docker', 'rm', '-f', self.runtime.container], label='cleanup.postgres')
                self.run(['docker', 'volume', 'rm', self.runtime.container], label='cleanup.postgres-volume')
        finally:
            if self.owns_network:
                self.run(['docker', 'network', 'rm', self.network], label='cleanup.database-network')
            # No runtime checkpoints or leases are created in this fixture.
            self.runtime.cache.rmdir()
