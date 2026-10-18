"""Exact owned Storage identities and recursive reference inspection.

No network, environment credentials, writes or guessed visibility. Callers keep
raw fields and paths in protected evidence; reports contain counts/digests only.
"""
import hashlib
import html
import json
import re
from urllib.parse import urlsplit, unquote

URL = re.compile(r'(?:https?:)?//[^\s\x00-\x20"\'<>`\\)\]},]+')
ENTITY = re.compile(r'&(?:#[0-9]+|#x[0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]+);|\\/|\\u002[fF]|\\u003[aA]')


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()


def decoded_spans(value):
    """Decode HTML entities / embedded JSON slashes, retaining exact edit spans."""
    out, spans, start = [], [], 0
    for m in ENTITY.finditer(value):
        for i in range(start, m.start()):
            out.append(value[i]); spans.append((i, i + 1))
        token = m.group()
        text = html.unescape(token) if token.startswith('&') else (':' if token.lower() == r'\u003a' else '/')
        for char in text:
            out.append(char); spans.append((m.start(), m.end()))
        start = m.end()
    for i in range(start, len(value)):
        out.append(value[i]); spans.append((i, i + 1))
    return ''.join(out), spans


def storage_identity(url, owned_hosts):
    """Queries, including signed capabilities, are never part of identity."""
    uri = urlsplit('https:'+url if url.startswith('//') else url)
    if uri.hostname not in owned_hosts:
        return None
    if uri.scheme != 'https' or uri.port or uri.username or uri.password:
        raise ValueError('unsafe_owned_storage_origin')
    m = re.fullmatch(r'/storage/v1/(?:object|render/image)/(public|authenticated|sign)/([^/]+)/(.+)', uri.path)
    if not m:
        if '/storage/v1/' in uri.path:
            raise ValueError('unsupported_owned_storage_route')
        return None
    if re.search(r'%(?![0-9a-fA-F]{2})', m[2] + m[3]):
        raise ValueError('invalid_percent_encoding')
    bucket, key = unquote(m[2], errors='strict'), unquote(m[3], errors='strict')
    if not bucket or '/' in bucket or not key or key.startswith('/') or any(x in ('.', '..', '') for x in key.split('/')) or '\\' in key or any(ord(c) < 32 for c in key):
        raise ValueError('unsafe_storage_key')
    return {'bucket': bucket, 'key': key, 'route': m[1]}


def inspect_value(value, owned_hosts, path=()):
    if isinstance(value, dict):
        for key, item in value.items():
            # Keys can carry URLs too; do not silently skip them.
            yield from inspect_value(key, owned_hosts, path + ('$key', key))
            yield from inspect_value(item, owned_hosts, path + (key,))
    elif isinstance(value, list):
        for index, item in enumerate(value):
            yield from inspect_value(item, owned_hosts, path + (index,))
    elif isinstance(value, str):
        try:
            nested = json.loads(value)
        except (ValueError, TypeError):
            nested = None
        if isinstance(nested, (dict, list, str)):
            yield from inspect_value(nested, owned_hosts, path + ('$json',))
            return
        decoded, spans = decoded_spans(value)
        found = False
        for m in URL.finditer(decoded):
            # Strip CSS declaration terminators only outside the object path.
            candidate = m.group()
            try:
                identity = storage_identity(candidate, owned_hosts)
            except (ValueError, UnicodeError):
                yield {'path': path, 'error': 'unresolved_owned_storage_syntax', 'field_digest': digest(value)}
                continue
            if identity:
                found = True
                yield {'path': path, 'identity': identity, 'fragment':urlsplit(candidate).fragment,
                       'span': (spans[m.start()][0], spans[m.end()-1][1]), 'field_digest': digest(value)}
        # A residual owned route is a blocker, never a successful zero-match scan.
        residual = URL.sub('',decoded)
        if not found and any('//'+host+'/storage/v1/' in residual for host in owned_hosts):
            yield {'path': path, 'error': 'unparsed_owned_storage_reference', 'field_digest': digest(value)}


def rewrite_value(value, owned_hosts, mapping):
    """Change exact URL spans only. Mapping is explicit and pre-verified."""
    if isinstance(value, dict):
        result = {}
        for key, item in value.items():
            new_key = rewrite_value(key, owned_hosts, mapping)
            if new_key in result:
                raise ValueError('rewritten_json_key_collision')
            result[new_key] = rewrite_value(item, owned_hosts, mapping)
        return result
    if isinstance(value, list):
        return [rewrite_value(item, owned_hosts, mapping) for item in value]
    if not isinstance(value, str):
        return value
    try:
        nested = json.loads(value)
    except (ValueError, TypeError):
        nested = None
    if isinstance(nested, (dict, list, str)):
        rewritten = rewrite_value(nested, owned_hosts, mapping)
        return value if rewritten == nested else json.dumps(rewritten, ensure_ascii=False)
    edits = []
    for ref in inspect_value(value, owned_hosts):
        if 'error' in ref:
            raise ValueError(ref['error'])
        identity = ref['identity']; target = mapping[(identity['bucket'], identity['key'])]
        # Never promote a signed/private reference to public by inference.
        if identity['route'] != 'public' and target['visibility'] != 'private':
            raise ValueError('private_reference_requires_review')
        url = target['url'] + ('#'+ref['fragment'] if ref.get('fragment') else '')
        edits.append((*ref['span'], url))
    for start, end, url in reversed(edits):
        original = value[start:end]
        if r'\/' in original:
            url = url.replace('/', r'\/')
        elif r'\u002f' in original.lower():
            url = url.replace('/', r'\u002f')
        value = value[:start] + url + value[end:]
    return value
