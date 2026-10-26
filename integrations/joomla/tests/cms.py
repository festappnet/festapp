"""HTTP checks exercise native Joomla login/save, ACL, CSRF and lifecycle."""
import http.cookiejar
import json
import re
import subprocess
import urllib.parse
import urllib.request
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AUTH = json.loads((ROOT / '.private/auth.json').read_text())


class Fields(HTMLParser):
    def __init__(self, html):
        super().__init__()
        self.fields = {}
        self.select = None
        self.action = None
        self.first = False
        self.textarea = None
        self.feed(html)

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == 'form' and a.get('name') == 'adminForm':
            self.action = a.get('action')
        if tag == 'input' and a.get('name') and a.get('type') not in ['submit', 'button', 'file']:
            if a.get('type') in ['checkbox', 'radio'] and 'checked' not in a:
                return
            self.fields[a['name']] = a.get('value', '')
        if tag == 'textarea' and a.get('name'):
            self.textarea = a['name']
            self.fields[self.textarea] = ''
        if tag == 'select':
            self.select = a.get('name')
            self.first = True
        if tag == 'option' and self.select:
            if 'selected' in a or self.first:
                self.fields[self.select] = a.get('value', '')
            self.first = False

    def handle_data(self, data):
        if self.textarea:
            self.fields[self.textarea] += data

    def handle_endtag(self, tag):
        if tag == 'textarea':
            self.textarea = None
        if tag == 'select':
            self.select = None


def session():
    return urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))


def request(client, url, data=None):
    try:
        with client.open(url, None if data is None else urllib.parse.urlencode(data).encode(), timeout=30) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def docker(major, *args):
    return subprocess.check_output(['docker', 'exec', f'festapp-joomla-20261026-{major}', *args], text=True)


if __name__ == '__main__':
    receipts = []
    for major, port in [(5, 59915), (6, 59916)]:
        base = f'http://127.0.0.1:{port}'
        seed = json.loads((ROOT / f'.private/seed-{major}.json').read_text())
        admin = session()
        _, login = request(admin, base + '/administrator/')
        data = Fields(login).fields
        data.update(username=AUTH['username'], passwd=AUTH['password'])
        _, page = request(admin, base + '/administrator/index.php', data)
        assert 'task=logout' in page, 'Native admin login failed'
        edit = base + '/administrator/index.php?option=com_modules&task=module.edit&id=' + str(seed['modules']['mod_vstupenky_online'])
        _, page = request(admin, edit)
        form = Fields(page)
        fields = form.fields
        save_url = base + form.action
        assert 'jform[params][url]' in fields and 'Start with vstupenky.online' in page
        assert '<iframe' not in page and not re.search(r'<script[^>]+src="https://(?:vstupenky.online|tickets.festapp.net)', page)
        fields.update({'task':'module.apply', 'jform[title]':'Saved through Joomla', 'jform[params][url]':'https://vstupenky.online/form/embedded-synthetic','jform[params][cache]':'0','jform[params][height]':'800','jform[params][mode]':'auto','jform[params][inherit_style]':'1'})
        status, saved = request(admin, save_url, fields)
        _, reloaded = request(admin, edit)
        (ROOT / f'.private/save-{major}.html').write_text(saved)
        (ROOT / f'.private/reload-{major}.html').write_text(reloaded)
        assert Fields(reloaded).fields.get('jform[title]') == 'Saved through Joomla', 'Native save persists'
        fields = Fields(reloaded).fields
        fields['task'] = 'module.apply'
        # Valid session, missing CSRF token must not alter the stored module.
        without_token = {k:v for k,v in fields.items() if not re.fullmatch('[a-f0-9]{32}', k)}
        without_token['jform[title]'] = 'CSRF write must fail'
        status, rejected = request(admin, save_url, without_token)
        _, after = request(admin, edit)
        assert Fields(after).fields.get('jform[title]') == 'Saved through Joomla', 'CSRF write accepted'
        # Exact public URL validation runs inside native Joomla save.
        invalid = Fields(after).fields
        invalid.update({'task':'module.apply','jform[params][url]':'https://evil.invalid/form/test'})
        request(admin, save_url, invalid)
        # Cancel edit to discard rejected form session values and release checkout.
        cancel = Fields(request(admin, edit)[1]).fields
        cancel['task'] = 'module.cancel'
        request(admin, save_url, cancel)
        _, after = request(admin, edit)
        assert Fields(after).fields['jform[params][url]'] == 'https://vstupenky.online/form/embedded-synthetic'
        cancel = Fields(after).fields
        cancel['task'] = 'module.cancel'
        request(admin, save_url, cancel)
        guest = session()
        # Public visitor cannot write even with a token from its own Joomla session.
        _, guest_page = request(guest, base + '/administrator/')
        guest_fields = Fields(guest_page).fields
        guest_fields.update({'task':'module.apply','jform[id]':str(seed['modules']['mod_vstupenky_online']),'jform[title]':'Unauthorized'})
        request(guest, save_url, guest_fields)
        # Registered-only account cannot enter administrator or edit modules.
        viewer = session()
        _, viewer_login = request(viewer, base + '/administrator/')
        viewer_fields = Fields(viewer_login).fields
        viewer_fields.update(username='viewer', passwd='OnlyLocalViewer123!')
        _, denied = request(viewer, base + '/administrator/index.php', viewer_fields)
        assert 'name="passwd"' in denied and 'task=logout' not in denied, 'ACL allows registered backend login'
        _, public = request(guest, base + '/')
        assert public.count('data-festapp-embed-host') == 3, 'Position plus article modules'
        for origin in ['https://vstupenky.online', 'https://tickets.festapp.net']:
            assert public.count('src="' + origin + '/embed.js"') == 1, 'Helper once per origin'
        assert 'embedded-synthetic?embed=1' in public
        # Conservative caching: repeat actual HTTP page render, including article module.
        _, cached = request(guest, base + '/')
        assert cached.count('data-festapp-embed-host') == 3
        assert cached.count('/embed.js"') == 2
        # Reinstall the exact ZIPs; verify settings survive via native module editor.
        products = {p['element']: p for p in json.loads((ROOT / 'products.json').read_text())}
        for element in seed['modules']:
            package = element + '-' + products[element]['version'] + '.zip'
            docker(major, 'cp', '/artifacts/' + package, '/tmp/')
            docker(major, 'php','cli/joomla.php','extension:install','--path=/tmp/' + package)
        _, upgraded = request(admin, edit)
        assert Fields(upgraded).fields.get('jform[title]') == 'Saved through Joomla'
        assert Fields(upgraded).fields.get('jform[params][url]') == 'https://vstupenky.online/form/embedded-synthetic'
        cancel = Fields(upgraded).fields
        cancel['task'] = 'module.cancel'
        request(admin, save_url, cancel)
        receipts.append({'joomla_major':major,'checks':['native login and save/reload','no admin iframe or external helper','CSRF rejects mutation','guest and registered ACL','invalid URL rejected by CMS','position and article','two brands, three instances','one helper per origin','global cache enabled/reload','same-version reinstall preserves settings']})
    (ROOT / 'evidence/cms.json').write_text(json.dumps(receipts, indent=2)+'\n')
    print('PASS native CMS save/security/cache/reinstall on both Joomla versions')
