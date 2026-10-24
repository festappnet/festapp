#!/usr/bin/env python3
"""Build an offline comparison of truthful search snippets, with desktop/mobile widths."""
from pathlib import Path
import argparse
import html
import json


def build(repo, output):
    output.mkdir(parents=True, exist_ok=True)
    seo = json.loads((repo / 'automation/release/organizers/content.json').read_text())['publicProjection']['seo']
    variants = [
        ('1. Prodej vstupenek - nastaveno v nové verzi', seo['title'], seo['description']),
        ('2. Jednoduché sdělení', 'Vstupenky pro Vaši akci | vstupenky.online', 'Vlastní plánek sálu i vzhled vstupenek. QR platby bez transakčních poplatků, výběr míst a odbavení telefonem. Připravte vstupenky pro Vaši akci.'),
        ('3. Zaměření na plesy', 'Prodej vstupenek na ples | vstupenky.online', 'Uspořádejte ples s vlastním plánkem sálu. Hosté si vyberou místa i večeři a zaplatí QR převodem bez transakčního poplatku. Vstup ověříte telefonem.'),
    ]
    cards = ''.join(f'<section><h2>{html.escape(label)}</h2><article><div class="site"><span class="icon">v</span><div>vstupenky.online<small>https://vstupenky.online</small></div></div><a class="result-title" href="../landing.html">{html.escape(title)}</a><p>{html.escape(description)}</p></article></section>' for label, title, description in variants)
    image = (repo / 'web/organizers-media/organizers-social.png').as_uri()
    page = f'''<!doctype html><html lang="cs"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Návrhy výsledku vyhledávání - vstupenky.online</title><style>
*{{box-sizing:border-box}}body{{margin:0;background:#ebf1f6;color:#253759;font:17px/1.55 system-ui,sans-serif}}main{{max-width:1020px;margin:auto;padding:40px 24px}}h1{{font-size:32px;line-height:1.2}}h2{{font-size:18px;margin:30px 0 12px}}nav{{display:flex;gap:12px;margin:24px 0}}button{{font:inherit;border:1px solid #cbd7e6;background:#ffffff90;border-radius:26px;padding:10px 22px;color:#253759;cursor:pointer}}button[aria-pressed="true"]{{background:#82bff2}}a{{color:#253759}}#snippets{{max-width:720px;transition:max-width .2s}}body[data-width="mobile"] #snippets{{max-width:370px}}article{{background:white;padding:22px;border-radius:16px;font:14px/1.58 Arial,sans-serif;color:#4d5156}}.site{{display:flex;gap:12px;align-items:center;color:#202124;line-height:1.4}}.site small{{display:block;font-size:12px}}.icon{{width:28px;height:28px;border-radius:50%;display:grid;place-items:center;background:#253759;color:white;font-weight:bold;font-size:20px}}.result-title{{display:block;color:#1a0dab;text-decoration:none;font-size:20px;line-height:1.3;margin:14px 0 6px}}.result-title:hover{{text-decoration:underline}}article p{{margin:0}}.sharing{{max-width:720px;margin-top:45px}}.sharing img{{width:100%;height:auto;display:block;border-radius:14px}}.note{{font-size:14px;color:#526174;max-width:760px}}@media(max-width:480px){{main{{padding:25px 16px}}article{{padding:18px}}}}
</style><main><h1>Návrhy zobrazení v Googlu</h1><p>Varianta 1 je nastavená v nové stránce. Varianty 2 a 3 jsou návrhy k porovnání.</p><p class="note">Orientační náhled. Google může titulek i popis přepsat podle dotazu a zařízení. Třetí varianta zužuje zaměření na plesy; pro obecnou úvodní stránku doporučujeme první.</p><nav aria-label="Šířka náhledu"><button aria-pressed="true" data-mode="desktop">Desktop</button><button aria-pressed="false" data-mode="mobile">Mobil</button></nav><div id="snippets">{cards}</div><section class="sharing"><h2>Náhled při sdílení</h2><img src="{html.escape(image)}" width="1200" height="630" alt="Nový značkový náhled vstupenky.online"><p class="note">Open Graph obrázek pro sdílení. Není příslibem obrázku u textového výsledku v Googlu.</p></section><p><a href="../landing.html">Otevřít aktuální stránku</a></p></main><script>document.querySelectorAll('[data-mode]').forEach(b=>b.addEventListener('click',()=>{{document.body.dataset.width=b.dataset.mode;document.querySelectorAll('[data-mode]').forEach(x=>x.setAttribute('aria-pressed',String(x===b)));}}));</script></html>'''
    (output / 'search-preview.html').write_text(page)
    (output / 'snippet-variants.json').write_text(json.dumps([{'label':label,'title':title,'description':description} for label,title,description in variants], ensure_ascii=False, indent=2)+'\n')
    print(f'Search preview: {output / "search-preview.html"}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    build(args.repo.resolve(), args.output.resolve())
