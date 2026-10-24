#!/usr/bin/env python3
"""Build an evidence gallery from the current clip manifest and actual QA artifacts."""
import argparse
import html
import json
import os
from pathlib import Path


def build(repo, output, preview):
    output.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((repo / 'automation/release/organizers/clips.json').read_text())
    media = repo / 'web/organizers-media'
    escape = html.escape
    images = ''.join(f'<figure><a href="{escape(p.name)}"><img loading="lazy" src="{escape(p.name)}" alt="{escape(p.stem)}"></a><figcaption>{escape(p.stem)}</figcaption></figure>' for p in sorted(output.glob('*.png')))
    videos = []
    active_ids = {clip_id for section in manifest['sections'] for clip_id in section['clips']}
    for clip in manifest['clips']:
        if clip['id'] not in active_ids:
            continue
        poster = (media / Path(clip['poster']).name).as_uri() if clip.get('poster') else ''
        src = (media / Path(clip['src']).name).as_uri()
        mobile = (media / Path(clip['mobileSrc']).name).as_uri() if clip.get('mobileSrc') else ''
        videos.append(f'<article><h3>{escape(clip["label"])}</h3><p>{escape(clip["description"])}</p><video controls preload="none" poster="{escape(poster)}" src="{escape(src)}"></video>' + (f'<details><summary>Mobilní varianta</summary><video controls preload="none" src="{escape(mobile)}"></video></details>' if mobile else '') + '</article>')
    scrolls = ''.join(f'<figure><video controls preload="none" src="{escape(p.name)}"></video><figcaption>{escape(p.stem)}</figcaption></figure>' for p in sorted(list(output.glob('scroll-*.webm')) + list(output.glob('hero-motion.webm')) + list(output.glob('closing-drawing.webm'))))
    reports = ''.join(f'<li><a href="{escape(p.name)}">{escape(p.name)}</a></li>' for p in sorted(output.glob('*.json')))
    comparison = ''
    previous = output.parent / 'polish-final'
    if previous == output or not previous.exists():
        previous = output.parent / 'sketch-review'
    if previous == output or not previous.exists():
        previous = output.parent / 'blueprint-review'
    if previous == output or not previous.exists():
        previous = output.parent / 'final-review'
    if previous == output or not previous.exists():
        previous = output.parent / 'airy-review'
    if previous == output or not previous.exists():
        previous = output.parent / 'real-product-review'
    for filename, label in [('hero-1440.png','Úvod'), ('formular-1440.png','Formulář'), ('odbaveni-390.png','Telefon'), ('reference-1440.png','Reference'), ('vyber-mist-1440.png','Výběr míst')]:
        old, new = previous / filename, output / filename
        if old.exists() and new.exists():
            old_href = Path(os.path.relpath(old, output)).as_posix()
            comparison += f'<article><h3>{escape(label)}</h3><p><a href="{escape(old_href)}">Předchozí verze</a> · <a href="{escape(filename)}">Aktuální verze</a></p></article>'
    comparison = '<h2>Porovnání před a po</h2><div class="grid">' + comparison + '</div>' if comparison else ''
    preview_href = Path(os.path.relpath(preview, output)).as_posix()
    page = f'''<!doctype html><html lang="cs"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>České produktové ukázky - lokální ověření</title><style>body{{font:17px/1.5 system-ui;background:#ebf1f6;color:#253759;margin:0}}main{{max-width:1200px;margin:auto;padding:32px 22px}}a{{color:inherit}}.grid{{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:22px}}article,figure{{margin:0;background:white;padding:18px;border-radius:15px}}img,video{{width:100%;height:auto}}img{{max-height:700px;object-fit:contain}}summary{{cursor:pointer;padding:15px}}@media(max-width:700px){{.grid{{grid-template-columns:1fr}}}}</style><main><h1>České produktové ukázky</h1><p><a href="{escape(preview_href)}">Otevřít aktuální landing page</a>. Lokální evidence bez nasazení.</p><p>Aktuální videa a popisky pocházejí ze zdrojového manifestu. Screenshoty a záznamy níže vznikly v prohlížeči. Syntetická data; nejde o produkční měření ani skutečnou platbu.</p>{comparison}<h2>Záznamy stránky a animace</h2><div class="grid">{scrolls}</div><h2>Skutečné screenshoty</h2><div class="grid">{images}</div><h2>Samostatné klipy a jejich varianty</h2><div class="grid">{''.join(videos)}</div><h2>Výsledky kontrol</h2><ul>{reports}</ul><p>Reprodukce: automation/landing_capture/. Výchozí data, jazyk, kroky a export jsou uložené v příslušných recipes. Delší YouTube sestřih je navazující výstup, nikoli automaticky vytvořený záznam této galerie.</p></main></html>'''
    (output / 'index.html').write_text(page)
    print(f'Static gallery: {output / "index.html"}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--preview', type=Path, required=True)
    args = parser.parse_args()
    build(args.repo.resolve(), args.output.resolve(), args.preview.resolve())
