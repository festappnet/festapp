"""Native first-publication and article-only dispatcher/cache coverage.

Requires the installed ZIPs and seed from verify.sh. No production service is
fetched: HTTP assertions inspect only Joomla's emitted markup. All writes use
Joomla's native administration forms, CSRF tokens and controllers.
"""
import json
import urllib.parse
from html.parser import HTMLParser

from cms import AUTH, ROOT, Fields, docker, request, session


class Markup(HTMLParser):
    def __init__(self, html):
        super().__init__()
        self.frames = []
        self.scripts = []
        self.new_modules = []
        self.feed(html)

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        if tag == 'iframe':
            self.frames.append(attributes)
        elif tag == 'script' and attributes.get('src'):
            self.scripts.append(attributes['src'])
        elif tag == 'a' and 'module.add' in attributes.get('href', ''):
            self.new_modules.append(attributes)


def get_form(admin, url, expected_field):
    status, html = request(admin, url)
    assert status == 200, 'Native edit form did not load'
    form = Fields(html)
    assert form.action and expected_field in form.fields, 'Expected native edit form missing'
    return form


def save_form(admin, base, form, task, values):
    fields = dict(form.fields)
    fields.update(values)
    fields['task'] = task
    status, html = request(admin, urllib.parse.urljoin(base, form.action), fields)
    assert status == 200, 'Native save failed'
    return html


def module_form(admin, base, module_id):
    return get_form(
        admin,
        base + '/administrator/index.php?option=com_modules&task=module.edit&id=' + str(module_id),
        'jform[params][url]',
    )


def set_module(admin, base, module_id, values):
    form = module_form(admin, base, module_id)
    save_form(admin, base, form, 'module.save', values)
    reloaded = module_form(admin, base, module_id)
    for key, expected in values.items():
        assert reloaded.fields.get(key) == str(expected), 'Native module setting did not persist: ' + key
    save_form(admin, base, reloaded, 'module.cancel', {})


def article_form(admin, base, article_id):
    return get_form(
        admin,
        base + '/administrator/index.php?option=com_content&task=article.edit&id=' + str(article_id),
        'jform[articletext]',
    )


def set_article(admin, base, article_id, text):
    form = article_form(admin, base, article_id)
    save_form(admin, base, form, 'article.save', {
        'jform[articletext]': text,
        # The seed places this article on the Featured homepage. Preserve that
        # intended publication when the native controller reconciles its rows.
        'jform[featured]': '1',
    })
    reloaded = article_form(admin, base, article_id)
    actual = reloaded.fields['jform[articletext]']
    save_form(admin, base, reloaded, 'article.cancel', {})
    # Joomla's textarea layout includes surrounding indentation/newlines; the
    # module macro and substantive HTML must persist without any repair.
    assert actual.strip() == text.strip(), 'Native article body did not persist'


def clear_cache(major):
    docker(major, 'php', '/tests/clear-cache.php')


def inspect_article(html, title, mode, inherit):
    markup = Markup(html)
    assert len(markup.frames) == 1, 'Article-only page must contain exactly one iframe'
    frame = markup.frames[0]
    assert frame['title'] == title and frame['height'] == '800'
    assert frame['src'] == 'https://vstupenky.online/form/embedded-synthetic?embed=1'
    helper = mode == 'auto' or inherit == 1
    assert markup.scripts.count('https://vstupenky.online/embed.js') == int(helper), 'Actual dispatcher helper count'
    assert ('data-festapp-embed' in frame) == helper
    assert ('data-festapp-height' in frame) == (mode == 'fixed' and inherit == 1)
    if mode == 'fixed' and inherit == 1:
        assert frame['data-festapp-height'] == 'fixed'
    assert ('data-festapp-style' in frame) == (inherit == 1)
    if inherit:
        assert frame['data-festapp-style'] == 'inherit'
    assert html.count('data-festapp-embed-host') == 1


def verify(major):
    base = f'http://127.0.0.1:5991{major}'
    seed = json.loads((ROOT / f'.private/seed-{major}.json').read_text())
    admin = session()
    status, login = request(admin, base + '/administrator/')
    assert status == 200
    fields = Fields(login).fields
    fields.update(username=AUTH['username'], passwd=AUTH['password'])
    status, page = request(admin, base + '/administrator/index.php', fields)
    assert status == 200 and 'task=logout' in page, 'Native administrator login'

    # Follow Joomla's actual New -> module-type selection link, including its eid.
    status, selection = request(admin, base + '/administrator/index.php?option=com_modules&view=select&client_id=0')
    assert status == 200
    links = [link for link in Markup(selection).new_modules if 'vstupenky.online' in link.get('aria-label', '')]
    assert len(links) == 1, 'Installed Czech module missing from native New selector'
    new_url = urllib.parse.urljoin(base + '/administrator/', links[0]['href'])
    form = get_form(admin, new_url, 'jform[params][url]')
    title = f'Native Czech publication {major}'
    iframe_title = f'Native Czech form {major}'
    saved = save_form(admin, base, form, 'module.apply', {
        'jform[title]': title,
        'jform[position]': 'sidebar-right',
        'jform[published]': '1',
        'jform[access]': '1',
        'jform[assignment]': '0',
        'jform[showtitle]': '0',
        'jform[params][url]': 'https://vstupenky.online/form/embedded-synthetic',
        'jform[params][iframe_title]': iframe_title,
        'jform[params][mode]': 'auto',
        'jform[params][height]': '800',
        'jform[params][inherit_style]': '1',
    })
    created = Fields(saved)
    assert created.fields.get('jform[title]') == title, 'New module title missing after save'
    identity = urllib.parse.parse_qs(urllib.parse.urlparse(created.action or '').query)
    module_id = int(identity.get('id', ['0'])[0])
    assert module_id > 0 and module_id not in seed['modules'].values(), 'New native module was not created'
    for key, expected in {'jform[position]':'sidebar-right', 'jform[published]':'1', 'jform[assignment]':'0'}.items():
        assert created.fields.get(key) == expected, 'Native publication/menu state did not persist'
    save_form(admin, base, created, 'module.cancel', {})
    original_article = article_form(admin, base, seed['article'])
    original_text = original_article.fields['jform[articletext]']
    save_form(admin, base, original_article, 'article.cancel', {})
    cases = []
    try:
        clear_cache(major)
        status, public = request(session(), base + '/')
        assert status == 200
        assert len([frame for frame in Markup(public).frames if frame.get('title') == iframe_title]) == 1
        assert Markup(public).scripts.count('https://vstupenky.online/embed.js') == 1
        cases.append('native New/type selection/save/publish/template position/all-menu assignment/public readback')

        # Move the newly created module out of template positions, then publish
        # its actual ID through the native article editor. No sidebar fallback
        # can supply the script on tmpl=component requests below.
        set_module(admin, base, module_id, {'jform[position]': 'native-article-only'})
        set_article(admin, base, seed['article'], '<p>Native publication proof</p>{loadmoduleid ' + str(module_id) + '}')
        article_url = base + '/index.php?option=com_content&view=article&id=' + str(seed['article']) + '&tmpl=component'
        for mode in ['auto', 'fixed']:
            for inherit in [0, 1]:
                set_module(admin, base, module_id, {
                    'jform[params][mode]': mode,
                    'jform[params][inherit_style]': str(inherit),
                })
                clear_cache(major)
                for temperature in ['cold', 'warm']:
                    status, article = request(session(), article_url)
                    assert status == 200
                    inspect_article(article, iframe_title, mode, inherit)
                    cases.append({'article_only': True, 'mode': mode, 'inherit_style': bool(inherit), 'cache': temperature, 'helpers': int(mode == 'auto' or inherit == 1)})
    finally:
        # Preserve the existing three-instance baseline for browser/lifecycle.
        try:
            set_article(admin, base, seed['article'], original_text)
        finally:
            try:
                set_module(admin, base, module_id, {'jform[published]': '0'})
            finally:
                clear_cache(major)
    status, restored = request(session(), base + '/')
    assert status == 200 and restored.count('data-festapp-embed-host') == 3, 'Seed baseline not restored'
    return {'joomla_major': major, 'new_module_id': module_id, 'article_id': seed['article'], 'baseline_restored': True, 'cases': cases}


if __name__ == '__main__':
    receipt = {'checks': [verify(major) for major in [5, 6]], 'boundary': 'native Joomla admin HTTP saves and public markup only; no service requests or purchases'}
    (ROOT / 'evidence/native-publication.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print('PASS native first publication and article-only cold/warm dispatcher matrix on both CMS versions')
