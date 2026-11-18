"""Real disposable WordPress without wp-env's unused Composer/PHPUnit builds.

Only public Docker image and WP-CLI interfaces are used. Each version has its
own core volume and database; all resources carry the unique fixture owner.
"""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import time
import uuid

LABEL = 'net.festapp.cms-wordpress'


class WordPress:
    def __init__(self, root, project, run):
        self.root = Path(root).resolve()
        if (not re.fullmatch(r'festapp-cms-consent-[a-f0-9]{12}', project)
                or self.root.parts[-3:] != (project, 'integrations', 'wordpress')):
            raise ValueError('Unique owned CMS fixture required')
        self.project, self.run = project, run
        config = json.loads((self.root / '.wp-env.json').read_text())
        pins = json.loads((self.root / 'docker-images.json').read_text())
        references = {name: name + '@' + digest for name, digest in pins.items()}
        for reference in references.values():
            if not re.fullmatch(r'(?:wordpress|mariadb):[a-zA-Z0-9._-]+@sha256:[a-f0-9]{64}', reference):
                raise ValueError('Digest-pinned official CMS image required')
        self.images = references
        self.database_image = references['mariadb:lts']
        self.archives = json.loads((self.root / 'core-archives.json').read_text())
        self.network = project + '-wordpress'
        self.database = self.network + '-db'
        self.private = self.root / '.private/wordpress'
        self.private.mkdir(parents=True, mode=0o700, exist_ok=True)
        self.versions = {}
        for name, overrides in [('cli', {}), ('tests-cli', config['env']['tests'])]:
            current = {**config, **overrides}
            match = re.fullmatch(r'https://wordpress.org/wordpress-([0-9]+\.[0-9]+(?:\.[0-9]+)?)\.zip', current['core'])
            php = current['phpVersion']
            if not match or php not in ('8.5', '7.4'):
                raise ValueError('Pinned WordPress release/PHP pair required')
            port = config['port'] if name == 'cli' else config['testsPort']
            if not isinstance(port, int) or not 1024 <= port <= 65535:
                raise ValueError('Loopback WordPress port required')
            container = self.network + '-' + name
            self.versions[name] = dict(version=match[1], php=php, port=port,
                config={**config['config'], **overrides.get('config', {})},
                container=container, volume=container + '-core',
                env=self.private / (name + '.env'), database='wordpress_' + name.replace('-', '_'))

    def _resources(self):
        return ([('container', self.database)]
            + [('container', row['container']) for row in self.versions.values()]
            + [('container', row['container'] + '-command') for row in self.versions.values()]
            + [('volume', row['volume']) for row in self.versions.values()]
            + [('network', self.network)])

    def _inspect(self, kind, name):
        result = subprocess.run(['docker', kind, 'inspect', name], capture_output=True, text=True)
        if result.returncode:
            # Distinguish an absent resource from a failed Docker daemon.
            if 'no such' not in result.stderr.lower() and 'not found' not in result.stderr.lower():
                raise RuntimeError('Cannot inspect owned WordPress resource')
            return None
        row = json.loads(result.stdout)[0]
        labels = row.get('Labels') if kind != 'container' else row['Config'].get('Labels')
        if (labels or {}).get(LABEL) != self.project:
            raise ValueError('Foreign WordPress resource refused')
        return row

    def cli(self, name, *args, capture=False):
        row = self.versions[name]
        return self.run(['docker', 'run', '--rm', '--name', row['container'] + '-command',
            '--label', LABEL + '=' + self.project, '--network', self.network,
            '--user', '33:33', '--env-file', row['env'], '-e', 'HOME=/tmp',
            '-v', row['volume'] + ':/var/www/html',
            '-v', str(self.root / 'tests') + ':/var/www/html/wp-content/plugins/vstupenky-online-tests:ro',
            '-v', str(self.root / 'dist') + ':/var/www/html/wp-content/vo-artifacts:ro',
            self.images['wordpress:cli-php' + row['php']], 'wp', *args], capture=capture, label='wordpress.cli')

    def prepare_core_cache(self):
        cache = Path.home() / '.cache/festapp-wordpress-core'
        cache.mkdir(parents=True, exist_ok=True)
        fixture_cache = self.private / 'core-cache/core'
        fixture_cache.mkdir(parents=True, mode=0o755)
        versions = {row['version'] for row in self.versions.values()}
        for version in sorted(versions.intersection(self.archives)):
            digest = self.archives[version]
            if not re.fullmatch(r'[a-f0-9]{64}', digest):
                raise ValueError('WordPress core archive must have a pinned SHA-256')
            name = 'wordpress-' + version + '-en_US.tar.gz'
            published = cache / name
            equivalent = lambda path: path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == digest
            if not equivalent(published):
                temporary = cache / (name + '.' + uuid.uuid4().hex + '.part')
                try:
                    self.run(['curl', '--fail', '--silent', '--show-error', '--location',
                              '--connect-timeout', '10', '--max-time', '45', '--retry', '2',
                              '--retry-max-time', '75', '--output', temporary,
                              'https://wordpress.org/wordpress-' + version + '.tar.gz'], label='wordpress.core-archive')
                    if not equivalent(temporary):
                        raise ValueError('WordPress core archive digest mismatch')
                    os.replace(temporary, published)
                finally:
                    temporary.unlink(missing_ok=True)
            fixture_archive = fixture_cache / name
            shutil.copyfile(published, fixture_archive)
            fixture_archive.chmod(0o644)
            if not equivalent(fixture_archive):
                raise ValueError('Staged WordPress core archive digest mismatch')

    def start(self, core_archive):
        if any(self._inspect(kind, name) for kind, name in self._resources()):
            raise ValueError('WordPress environment already exists')
        password = secrets.token_hex(24)
        database_env = self.private / 'database.env'
        database_env.write_text('MARIADB_ROOT_PASSWORD=' + password + '\nMYSQL_PWD=' + password + '\n')
        database_env.chmod(0o600)
        self.run(['docker', 'network', 'create', '--label', LABEL + '=' + self.project, self.network])
        self.run(['docker', 'run', '-d', '--name', self.database, '--label', LABEL + '=' + self.project,
            '--network', self.network, '--env-file', database_env, self.database_image], label='wordpress.database')
        with ThreadPoolExecutor(max_workers=2) as workers:
            list(workers.map(lambda row: self._start_core(row, password, core_archive), self.versions.values()))
            deadline = time.monotonic() + 90
            while True:
                result = subprocess.run(['docker', 'exec', self.database, 'healthcheck.sh', '--connect', '--innodb_initialized'], capture_output=True)
                if result.returncode == 0:
                    break
                if time.monotonic() >= deadline:
                    raise RuntimeError('Owned WordPress database readiness timeout')
                time.sleep(.2)
            self.run(['docker', 'exec', '--env-file', database_env, self.database, 'mariadb', '-uroot', '-e',
                ';'.join('CREATE DATABASE ' + row['database'] for row in self.versions.values())])
            list(workers.map(lambda name: self._install_core(name, deadline), self.versions))

    def _start_core(self, row, password, core_archive):
        self.run(['docker', 'volume', 'create', '--label', LABEL + '=' + self.project, row['volume']])
        version = row['version']
        if version in self.archives:
            core_archive.result()
            self.run(['docker', 'run', '--rm', '--network', 'none', '--name', row['container'] + '-command',
                      '--label', LABEL + '=' + self.project, '--user', '0:0',
                      '-v', row['volume'] + ':/var/www/html',
                      '-v', str(self.private / 'core-cache') + ':/fixture-wp-cache:ro',
                      '-e', 'WP_CLI_CACHE_DIR=/fixture-wp-cache', '--entrypoint', 'sh',
                      self.images['wordpress:cli-php' + row['php']], '-eu', '-c',
                      'wp core download --path=/var/www/html --version="$1" --allow-root; chown -R 33:33 /var/www/html',
                      'sh', version], label='wordpress.core-install')
        extra = '\n'.join('define(' + json.dumps(key) + ',' + json.dumps(value) + ');'
            for key, value in row['config'].items() if key != 'WP_DEBUG')
        # Docker env files cannot contain multiline values. PHP accepts spaces.
        row['env'].write_text('\n'.join(['WORDPRESS_DB_HOST=' + self.database,
            'WORDPRESS_DB_USER=root', 'WORDPRESS_DB_PASSWORD=' + password,
            'WORDPRESS_DB_NAME=' + row['database'], 'WORDPRESS_DEBUG=' + ('1' if row['config'].get('WP_DEBUG') else ''), 'WORDPRESS_CONFIG_EXTRA=' + extra.replace('\n', ' ')]) + '\n')
        row['env'].chmod(0o600)
        self.run(['docker', 'run', '-d', '--name', row['container'], '--label', LABEL + '=' + self.project,
            '--network', self.network, '--env-file', row['env'], '-p', '127.0.0.1:' + str(row['port']) + ':80',
            '-v', row['volume'] + ':/var/www/html',
            '-v', str(self.root / 'tests') + ':/var/www/html/wp-content/plugins/vstupenky-online-tests:ro',
            '-v', str(self.root / 'dist') + ':/var/www/html/wp-content/vo-artifacts:ro',
            self.images['wordpress:php' + row['php']]], label='wordpress.apache')
        if version in self.archives:
            # The image normally copies its rewrite rules together with the core.
            self.run(['docker', 'exec', row['container'], 'cp', '-p',
                      '/usr/src/wordpress/.htaccess', '/var/www/html/.htaccess'], label='wordpress.rewrite-rules')

    def _install_core(self, name, deadline):
        row = self.versions[name]
        while subprocess.run(['docker', 'exec', row['container'], 'test', '-f', '/var/www/html/wp-config.php'], capture_output=True).returncode:
            if time.monotonic() >= deadline:
                raise RuntimeError('Owned WordPress core initialization timeout')
            time.sleep(.2)
        if self.cli(name, 'core', 'version', capture=True).strip() != row['version']:
            raise RuntimeError('WordPress core volume does not contain the configured release')
        self.cli(name, 'core', 'install', '--url=' + row['config']['WP_HOME'],
            '--title=CMS consent fixture', '--admin_user=fixture', '--admin_password=disposable-fixture-only',
            '--admin_email=wordpress@example.invalid', '--skip-email')
        if self.cli(name, 'core', 'version', capture=True).strip() != row['version']:
            raise RuntimeError('WordPress version mismatch')
        if self.cli(name, 'eval', 'echo PHP_MAJOR_VERSION,".",PHP_MINOR_VERSION;', capture=True).strip() != row['php']:
            raise RuntimeError('PHP version mismatch')

    def stop(self):
        owned = [(kind, name) for kind, name in self._resources() if self._inspect(kind, name)]
        for kind, name in owned:
            self.run(['docker', kind, 'rm', *(['-fv'] if kind == 'container' else []), name], label='cleanup.wordpress')
        for path in self.private.glob('*.env'):
            path.unlink()
