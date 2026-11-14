"""Consent transfer through native module saves and real public page markup.

Requires the installed ZIPs and seed from verify.sh. Only Joomla's own HTML is
inspected; no service request is made. Every setting is restored afterwards.
"""
import html
import importlib.util
import json
import re
import time
from pathlib import Path

from cms import AUTH, ROOT, Fields, docker, request, session
_spec = importlib.util.spec_from_file_location('native_publication', Path(__file__).with_name('native-publication.py'))
_native = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_native)
clear_cache, module_form, save_form, set_module = _native.clear_cache, _native.module_form, _native.save_form, _native.set_module

REVISION = '0123456789abcdef0123456789abcdef'
COOKIEBOT = {'consent_link': '1', 'consent_provider': 'cookiebot', 'consent_organization': '7', 'consent_unit': '11',
             'consent_revision': REVISION, 'consent_cbid': '09e4e631-f8c7-434e-8387-315da47220fe',
             'consent_origin': 'https://www.poradatel.example', 'consent_valid_from': '2026-11-11T00:00:00.000Z', 'consent_max_age': '15552000'}
COOKIEBOT_JSON = ('{"provider":"cookiebot","organization":7,"unit":11,"consentRevision":"' + REVISION + '",'
                  '"cbid":"09e4e631-f8c7-434e-8387-315da47220fe","origin":"https://www.poradatel.example",'
                  '"consentValidFrom":"2026-11-11T00:00:00.000Z","maxAgeSeconds":15552000}')
COOKIECONSENT = {'consent_link': '1', 'consent_provider': 'cookieconsent', 'consent_organization': '7', 'consent_unit': '11',
                 'consent_revision': REVISION, 'consent_cc_revision': '3', 'consent_cc_analytics': 'statistika', 'consent_cc_marketing': 'marketing'}
COOKIECONSENT_JSON = ('{"provider":"cookieconsent","organization":7,"unit":11,"consentRevision":"' + REVISION + '",'
                      '"revision":3,"categories":{"analytics":"statistika","marketing":"marketing"}}')
OFF = {'consent_link': '0', 'output': 'embed'}
# Restores a pristine module: every consent setting empty, defaults elsewhere.
CLEAR = {**OFF, 'link_text': '', 'link_class': 'btn btn-primary', 'consent_provider': '', **{key: '' for key in
         ['consent_organization', 'consent_unit', 'consent_revision', 'consent_cbid', 'consent_origin', 'consent_valid_from',
          'consent_max_age', 'consent_cc_revision']}, 'consent_cc_analytics': 'analytics', 'consent_cc_marketing': 'marketing'}
FORM = 'https://vstupenky.online/form/embedded-synthetic'
LEGACY = '<a href="' + FORM + '" target="_blank" rel="noopener noreferrer">'
MARKED = '<a href="' + FORM + '" target="_blank" data-festapp-consent-link>'


def params(values):
    return {'jform[params][' + key + ']': value for key, value in values.items()}


def helpers(page, origin='https://vstupenky.online'):
    return re.findall(r'<script src="' + re.escape(origin) + r'/embed\.js"([^>]*)>', page)


def attribute(tag, name):
    match = re.search(r'\s' + re.escape(name) + r'="([^"]*)"', tag)
    return None if match is None else html.unescape(match.group(1))


def public(major):
    clear_cache(major)
    status, page = request(session(), f'http://127.0.0.1:5991{major}/')
    assert status == 200
    return page


def log_everything(major, enabled):
    value = '1' if enabled else '0'
    docker(major, 'php', '-r', "$f='configuration.php';$c=file_get_contents($f);"
           "$c=preg_match('/public \\$log_everything = /',$c)?preg_replace('/public \\$log_everything = .*?;/','public $log_everything = " + value + ";',$c)"
           ":str_replace('public $log_path','public $log_everything = " + value + ";\n\tpublic $log_path',$c);file_put_contents($f,$c);")
    docker(major, 'sh', '-c', 'rm -f administrator/logs/everything.php')


def logged(major, text):
    # Apache's opcache may serve the previous configuration.php for a moment.
    for _ in range(4):
        log = docker(major, 'sh', '-c', 'cat administrator/logs/everything.php 2>/dev/null || true')
        if text in log:
            return True
        time.sleep(2.5)
        public(major)
    return False


def verify(major):
    base = f'http://127.0.0.1:5991{major}'
    seed = json.loads((ROOT / f'.private/seed-{major}.json').read_text())
    sidebar, article = seed['modules']['mod_vstupenky_online'], seed['article_module']
    admin = session()
    _, login = request(admin, base + '/administrator/')
    fields = Fields(login).fields
    fields.update(username=AUTH['username'], passwd=AUTH['password'])
    _, page = request(admin, base + '/administrator/index.php', fields)
    assert 'task=logout' in page, 'Native administrator login'
    cases = []
    log_everything(major, True)
    try:
        for module in [sidebar, article]:
            set_module(admin, base, module, params(CLEAR))
        # The editor shows the settings tab, with suggestions only as placeholders.
        form = module_form(admin, base, sidebar)
        status, editor = request(admin, base + '/administrator/index.php?option=com_modules&task=module.edit&id=' + str(sidebar))
        assert 'jform[params][consent_link]' in form.fields and form.fields.get('jform[params][consent_valid_from]') == ''
        assert re.search(r'name="jform\[params\]\[consent_valid_from\]"[^>]*placeholder="\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z"', editor)
        assert 'Take over consent from the banner of approved websites' in editor and 'My websites' in editor
        assert '<iframe' not in editor and not re.search(r'<script[^>]+src="https://vstupenky.online', editor)
        save_form(admin, base, form, 'module.cancel', {})
        cases.append('settings tab, help and placeholder-only suggestions in the native editor')

        # Default and disabled settings keep the legacy markup and helper.
        page = public(major)
        assert page.count(LEGACY) == 2 and 'data-festapp-consent=' not in page and len(helpers(page)) == 1
        assert 'data-cookieconsent' not in page
        cases.append('default off: legacy links, unconfigured helper')

        # Incomplete enabled settings are rejected by the native save, unchanged.
        rejected = module_form(admin, base, sidebar)
        response = save_form(admin, base, rejected, 'module.apply', params({**COOKIEBOT, 'consent_cbid': 'not-a-cbid'}))
        assert 'Cookie consent transfer cannot be saved' in response and 'Cookiebot CBID' in response
        cancel = module_form(admin, base, sidebar)
        save_form(admin, base, cancel, 'module.cancel', {})
        assert module_form(admin, base, sidebar).fields.get('jform[params][consent_link]') == '0', 'Rejected save changed settings'
        save_form(admin, base, module_form(admin, base, sidebar), 'module.cancel', {})
        rejected = module_form(admin, base, sidebar)
        response = save_form(admin, base, rejected, 'module.apply', params({**COOKIEBOT, 'consent_origin': '', 'consent_valid_from': ''}))
        assert 'Cookie consent transfer cannot be saved' in response and 'Website origin' in response and 'Notice valid from (UTC)' in response
        save_form(admin, base, module_form(admin, base, sidebar), 'module.cancel', {})
        cases.append('native save rejects invalid or empty Cookiebot settings and never fills them in')

        # One configured module: exact helper JSON once, its link marked.
        set_module(admin, base, sidebar, params(COOKIEBOT))
        page = public(major)
        tags = helpers(page)
        assert len(tags) == 1 and attribute(tags[0], 'data-festapp-consent') == COOKIEBOT_JSON
        assert attribute(tags[0], 'data-cookieconsent') == 'ignore' and ' defer' in tags[0]
        assert page.count(MARKED) == 1 and page.count(LEGACY) == 1, 'Only the configured module link is marked'
        tickets = helpers(page, 'https://tickets.festapp.net')
        assert len(tickets) == 1 and 'data-festapp-consent=' not in tickets[0], 'Other brand stays unconfigured'
        assert not re.search(r'<meta name="referrer"', page, re.I), 'Template must not block the consent link'
        assert logged(major, 'needs Cross-Origin-Opener-Policy same-origin-allow-popups'), 'Default COOP is reported'
        cases.append('cookiebot: exact JSON once, data-cookieconsent=ignore, marked link, other brand untouched')

        # Same configuration in a second instance: still one helper, both links marked.
        set_module(admin, base, article, params(COOKIEBOT))
        page = public(major)
        assert len(helpers(page)) == 1 and attribute(helpers(page)[0], 'data-festapp-consent') == COOKIEBOT_JSON
        assert page.count(MARKED) == 2 and page.count(LEGACY) == 0
        cases.append('duplicate identical instances share one configured helper')

        # Conflicting instance: no configuration on the page, logged.
        set_module(admin, base, article, params(COOKIECONSENT))
        page = public(major)
        assert len(helpers(page)) == 1 and 'data-festapp-consent=' not in page
        assert page.count(MARKED) <= 1 and page.count(MARKED) + page.count(LEGACY) == 2
        assert logged(major, 'different organization, Unit or consent configuration'), 'Conflict is logged'
        cases.append('conflicting instances: helper unconfigured, later link legacy, warning logged')

        # CookieConsent alone, as a link-only button.
        set_module(admin, base, article, params(OFF))
        set_module(admin, base, sidebar, params({**OFF, **COOKIECONSENT, 'output': 'link', 'link_text': 'Koupit vstupenky', 'link_class': 'btn btn-primary'}))
        page = public(major)
        tags = helpers(page)
        assert len(tags) == 1 and attribute(tags[0], 'data-festapp-consent') == COOKIECONSENT_JSON and 'data-cookieconsent' not in tags[0]
        assert '<div class="mod_vstupenky_online mod_vstupenky_online-link"><p><a class="btn btn-primary" href="' + FORM + '" target="_blank" data-festapp-consent-link>Koupit vstupenky</a></p></div>' in page
        assert page.count('data-festapp-embed-host') == 2, 'Link-only module renders no frame'
        cases.append('cookieconsent link-only button: exact JSON, marked button, no frame')

        # Invalid stored settings (bypassing the editor) fail closed and are logged.
        docker(major, 'php', '-r', "require '/tests/bootstrap.php';$db->setQuery(\"UPDATE #__modules SET params=JSON_SET(params,'$.consent_cc_revision','0') WHERE id=" + str(sidebar) + "\")->execute();")
        page = public(major)
        assert 'data-festapp-consent=' not in page and LEGACY.replace('<a ', '<a class="btn btn-primary" ') in page
        assert len(helpers(page)) == 1, 'Remaining embedded module still loads the helper'
        assert logged(major, 'incomplete or invalid settings (CONSENT_CC_REVISION)'), 'Invalid settings are logged'
        cases.append('invalid stored settings: unmarked legacy link, no configuration, warning logged')

        # A plain link-only page needs no external helper at all.
        set_module(admin, base, sidebar, params({**OFF, 'output': 'link', 'consent_cc_revision': '3'}))
        set_module(admin, base, article, params({**OFF, 'output': 'link'}))
        page = public(major)
        assert len(helpers(page)) == 0 and page.count(LEGACY.replace('<a ', '<a class="btn btn-primary" ')) == 2
        cases.append('link-only without consent transfer loads no helper')
    finally:
        for module in [sidebar, article]:
            set_module(admin, base, module, params(CLEAR))
        log_everything(major, False)
        clear_cache(major)
    page = public(major)
    assert page.count('data-festapp-embed-host') == 3 and page.count(LEGACY) == 2 and 'data-festapp-consent=' not in page, 'Baseline restored'
    return {'joomla_major': major, 'cases': cases}


if __name__ == '__main__':
    receipt = {'checks': [verify(major) for major in [5, 6]], 'boundary': 'native Joomla admin HTTP saves and public markup only; no service requests'}
    (ROOT / 'evidence/consent-page.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print('PASS consent transfer settings, helper configuration and link markup on both CMS versions')
