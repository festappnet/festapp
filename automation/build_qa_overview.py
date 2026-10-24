#!/usr/bin/env python3
"""Build the offline QA overview from the dated Markdown evidence reports.

Run: python3 automation/build_qa_overview.py
Add future reports to REPORTS and give their findings stable IDs in FINDINGS.
The Markdown reports remain the source of reproduction steps and evidence.
"""
from pathlib import Path
import html
import re

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / 'docs/development'
OUTPUT = DOCS / 'qa-overview.html'
REPORTS = [
    ('exploratory-ui-ux-qa-2026-10-23.md', 'Průchod 1', 'Akce, účastníci a navigace'),
    ('forms-occasion-qa-2026-10-23.md', 'Průchod 2', 'Formuláře a kopírování akcí'),
    ('program-speakers-qa-2026-10-23.md', 'Průchod 3', 'Program, přednášející a nastavení'),
    ('public-catalogue-qa-2026-10-23.md', 'Průchod 4', 'Veřejný katalog a ovládání klávesnicí'),
]
FINDINGS = [
    ('QA-001', 'Účastníci', 'Pozvánka třikrát selže, ale závěrečný dialog přesto oznámí úspěch.'),
    ('QA-002', 'Navigace', 'Neaktivní sekce zpřístupňují nesouvisející ovládání. Dopad na čtečku nebyl plně ověřen.'),
    ('QA-003', 'Navigace', 'Při změně šířky okna zmizí označení aktivní sekce mimo viditelnou navigaci.'),
    ('QA-004', 'Účastníci', 'Prázdný dialog nevysvětluje, odkud se účastníci vybírají ani jak pokračovat.'),
    ('QA-005', 'Formuláře', 'Uložené povinné pole bez možností znepřístupní celý veřejný formulář. Doplnění jediné volby ho obnoví.'),
    ('QA-006', 'Akce', 'Obsazený odkaz skončí HTTP 409. Dialog neukáže chybu a akce nevznikne.'),
    ('QA-007', 'Formuláře', 'Místo českého vysvětlení kolize odkazu se zobrazí databázová výjimka s kódem 23505.'),
    ('QA-008', 'Formuláře', 'Platnost nabídky 1,5 hodiny je odmítnutá. Stejná hodnota s tečkou se uloží správně.'),
    ('QA-009', 'Formuláře', 'Název je při vytváření povinný, ale nastavení dovolí uložit prázdnou hodnotu.'),
    ('QA-010', 'Formuláře', 'České rozhraní pojmenuje kopii formuláře anglickým dodatkem (copy).'),
    ('QA-011', 'Program', 'Přidání prvního řádku bez existujících míst vykreslí chybu místo prázdné hodnoty.'),
    ('QA-012', 'Navigace', 'Přepínač označí vnořenou administraci jako aplikaci a nenabídne očekávaný přechod do aplikace.'),
    ('QA-013', 'Přednášející', 'Po neúspěšném uložení a Stornu nový editor stále ukazuje neuložené jméno.'),
    ('QA-014', 'Program', 'Po odebrání a přidání typu se automaticky vygeneruje již použitý kód. Uložení duplicitu přijme.'),
    ('QA-015', 'Veřejný katalog', 'Neznámá cesta přepíše URL na úvod, ale katalog se nevykreslí. Pomůže až ruční reload.'),
    ('QA-016', 'Přístupnost', 'Ikonky nastavení a zpětné vazby jsou pouze klikatelné prvky bez standardního klávesového ovládání.'),
]


def esc(value):
    return html.escape(str(value), quote=True)


def inline(value):
    token = re.compile(r'`([^`]+)`|\*\*([^*]+)\*\*|\[([^\]]+)\]\(([^)]+)\)')
    result, last = [], 0
    for match in token.finditer(value):
        result.append(esc(value[last:match.start()]))
        code, strong, label, target = match.groups()
        if code is not None:
            result.append(f'<code>{esc(code)}</code>')
        elif strong is not None:
            result.append(f'<strong>{esc(strong)}</strong>')
        else:
            result.append(f'<a href="{esc(target)}">{esc(label)}</a>')
        last = match.end()
    result.append(esc(value[last:]))
    return ''.join(result)


def markdown(source):
    """Render the small, deliberately limited Markdown used by these reports."""
    lines, result, paragraph = source.splitlines(), [], []
    def flush():
        if paragraph:
            result.append('<p>' + inline(' '.join(paragraph)) + '</p>')
            paragraph.clear()
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        if not line:
            flush(); i += 1; continue
        if line.startswith('|'):
            flush(); rows = []
            while i < len(lines) and lines[i].strip().startswith('|'):
                cells = [c.strip() for c in lines[i].strip().strip('|').split('|')]
                if not all(re.fullmatch(r':?-+:?', c) for c in cells):
                    rows.append(cells)
                i += 1
            result.append('<div class="table-scroll" tabindex="0" role="region" aria-label="Výsledky průchodů"><table><thead><tr>' + ''.join(f'<th scope="col">{inline(c)}</th>' for c in rows[0]) + '</tr></thead><tbody>' + ''.join('<tr>' + ''.join(f'<td>{inline(c)}</td>' for c in row) + '</tr>' for row in rows[1:]) + '</tbody></table></div>')
            continue
        heading = re.match(r'^(#{1,3}) (.+)$', line)
        if heading:
            flush(); level = min(len(heading[1]) + 2, 5)
            result.append(f'<h{level}>{inline(heading[2])}</h{level}>'); i += 1; continue
        item = re.match(r'^(?:- |\d+\. )(.+)$', line)
        if item:
            flush(); ordered = bool(re.match(r'^\d+\.', line)); tag = 'ol' if ordered else 'ul'
            result.append(f'<{tag}>')
            pattern = r'^\d+\. (.+)$' if ordered else r'^- (.+)$'
            while i < len(lines):
                match = re.match(pattern, lines[i].strip())
                if not match: break
                result.append('<li>' + inline(match[1]) + '</li>'); i += 1
            result.append(f'</{tag}>'); continue
        paragraph.append(line); i += 1
    flush()
    return '\n'.join(result)


articles, reports, index = [], [], 0
counts = {'P1': 0, 'P2': 0, 'P3': 0}
run_counts = {number: 0 for number in range(1, len(REPORTS) + 1)}
for run_number, (filename, run, title) in enumerate(REPORTS, 1):
    source = (DOCS / filename).read_text()
    matches = list(re.finditer(r'^## (\d+)\. (P[123]) - (.+)$', source, re.M))
    last_end = 0
    for match in matches:
        next_heading = re.search(r'^## ', source[match.end():], re.M)
        end = match.end() + next_heading.start() if next_heading else len(source)
        body = source[match.end():end].strip()
        finding_id, area, summary = FINDINGS[index]
        priority, name = match[2], match[3]
        counts[priority] += 1
        run_counts[run_number] += 1
        pictures = list(dict.fromkeys(re.findall(r'\[([^\]]+)\]\(([^)]+\.png)\)', body)))
        gallery = ''
        if pictures:
            gallery = '<section class="evidence"><h4>Snímky k nálezu</h4><div class="gallery">' + ''.join(f'<a class="image-link" href="{esc(path)}" data-image><img src="{esc(path)}" alt="{esc(label)} - {esc(name)}" loading="lazy" decoding="async"><span>{esc(label)}<span aria-hidden="true"> ↗</span></span></a>' for label, path in pictures) + '</div></section>'
        search = ' '.join((finding_id, priority, area, name, summary, body))
        articles.append((priority, finding_id, f'''<article class="finding" id="{finding_id}" data-priority="{priority}" data-run="{run_number}" data-area="{esc(area)}" data-search="{esc(search)}">
<div class="finding-meta"><span class="priority {priority}">{priority}</span><span>{esc(area)}</span><span class="run-label{' latest' if run_number == len(REPORTS) else ''}">{run}{' · nové' if run_number == len(REPORTS) else ''}</span><a class="finding-id" href="#{finding_id}" aria-label="Odkaz na nález {finding_id}">{finding_id}</a></div>
<h3>{esc(name)}</h3><p class="finding-summary">{esc(summary)}</p>
<details class="finding-detail"><summary>Reprodukce, dopad a důkazy <span aria-hidden="true">+</span></summary><div class="prose">{markdown(body)}</div>{gallery}<p class="source-link">Zdroj: <a href="{filename}">{run} - původní zápis</a></p></details></article>'''))
        index += 1
        last_end = end
    context = source[:matches[0].start()] + '\n' + source[last_end:]
    # The cross-link from report 1 is already visible in the report list.
    context = re.sub(r'## Navazující průchod.*', '', context, flags=re.S)
    context = re.sub(r'^# .+\n', '', context)
    videos = list(dict.fromkeys(re.findall(r'\[([^\]]+)\]\(([^)]+\.webm)\)', context)))
    if filename == REPORTS[0][0]:
        videos.append(('Surový záznam prvního průchodu', 'evidence/ui-ux-qa-2026-10-23/exploration.webm'))
    media = ''.join(f'<details class="video-detail"><summary>{esc(label)} - video</summary><video controls preload="metadata" src="{esc(path)}" aria-label="{esc(label)}">Video lze <a href="{esc(path)}">otevřít samostatně</a>.</video><p>Surový záznam lokálního průchodu, včetně práce s automatizací.</p></details>' for label, path in videos)
    reports.append(f'<details class="run"><summary><span><strong>{run}</strong>{esc(title)}</span><span aria-hidden="true">+</span></summary><div class="prose">{markdown(context)}</div>{media}<p><a href="{filename}">Původní Markdown report</a></p></details>')
assert index == len(FINDINGS), 'Update FINDINGS when a report gains findings.'
# The public-form outage is the most directly blocking finding.
articles.sort(key=lambda row: (row[0], 0 if row[1] == 'QA-005' else 1, row[1]))

PAGE = r'''<!doctype html>
<html lang="cs">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light"><title>Festapp | QA zápisník</title>
<style>
:root{--paper:#fff;--ground:#f3f5f4;--ink:#172c28;--muted:#536660;--line:#d5dfda;--accent:#16634d;--soft:#e9f2ed;--p1:#9c2729;--p1-bg:#fcebec;--p2:#795000;--p2-bg:#fbf0d9;--p3:#315975;--p3-bg:#eaf1f7;--focus:#167960;--radius:12px;--ui:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
*{box-sizing:border-box}html{scroll-behavior:smooth;scroll-padding-top:28px}body{margin:0;background:var(--ground);color:var(--ink);font:16px/1.65 var(--ui);-webkit-font-smoothing:antialiased}::selection{background:#c8e4d6;color:#142d23}a{color:var(--accent);text-underline-offset:3px;text-decoration-thickness:1px}a:hover{text-decoration-thickness:2px}button,input,select{font:inherit;color:inherit}button,select,summary{cursor:pointer}button,input,select{min-height:44px;border:1px solid #adbbb4;background:var(--paper);border-radius:7px}button{padding:8px 14px;font-weight:600}button:hover{background:var(--soft)}input,select{width:100%;padding:9px 12px;caret-color:var(--accent)}:focus-visible{outline:3px solid var(--focus);outline-offset:4px}h1,h2,h3,h4{line-height:1.25;text-wrap:balance}h1{font-size:clamp(32px,4vw,48px);letter-spacing:-.025em;margin:0 0 20px;font-weight:720}h2{font-size:25px;letter-spacing:-.02em;margin:0}h3{font-size:21px;letter-spacing:-.015em;margin:15px 0 10px}h4{font-size:17px;margin:28px 0 12px}p{margin:0 0 14px}strong{font-weight:650}code{font-family:ui-monospace,SFMono-Regular,Consolas,monospace;font-size:.88em;background:#edf1ee;padding:2px 4px;border-radius:3px;overflow-wrap:anywhere}small{font-size:13px}.skip-link{position:absolute;top:-80px;left:20px;background:var(--paper);padding:12px;z-index:20}.skip-link:focus{top:12px}.topbar{border-bottom:1px solid var(--line);background:var(--paper);padding:17px 30px;display:flex;align-items:center;justify-content:space-between;gap:20px}.brand{font-weight:750;letter-spacing:-.025em;text-decoration:none;color:var(--ink);font-size:21px}.brand span{font-size:14px;letter-spacing:0;font-weight:500;color:var(--muted);margin-left:12px}.topbar .date{font-size:14px;color:var(--muted);font-variant-numeric:tabular-nums}.layout{max-width:1450px;margin:auto;display:grid;grid-template-columns:235px minmax(0,1fr)}.sidebar{padding:38px 26px;position:sticky;top:0;align-self:start;max-height:100vh;overflow:auto}.sidebar nav{display:flex;flex-direction:column;gap:5px}.sidebar nav a{color:var(--ink);text-decoration:none;border-radius:7px;padding:9px 12px;font-size:14px}.sidebar nav a:hover,.sidebar nav a:first-child{background:#e1ebe5;color:#114e3a}.sidebar h2{font-size:12px;letter-spacing:.06em;text-transform:uppercase;margin:36px 12px 10px;color:var(--muted)}.legend{margin:0;padding:0 12px;list-style:none;font-size:13px}.legend li{display:flex;align-items:center;gap:9px;margin:12px 0}.side-note{font-size:13px;color:var(--muted);margin:35px 12px 0;max-width:175px}.main{min-width:0;padding:42px 44px 70px;border-left:1px solid var(--line)}.intro{padding-bottom:30px;border-bottom:1px solid var(--line);margin-bottom:34px}.intro .lead{max-width:66ch;color:var(--muted);font-size:18px}.stats{display:flex;flex-wrap:wrap;align-items:center;gap:12px 26px;margin-top:26px;font-size:14px}.stats strong{font-variant-numeric:tabular-nums}.stats .total{font-size:17px;color:var(--ink)}.stats .state{margin-left:auto;color:var(--muted);font-size:13px}.focus-note{display:flex;gap:18px;padding:22px 0 26px}.focus-note .mark{width:32px;height:32px;flex-shrink:0;margin-top:3px;color:var(--accent)}.focus-note p{max-width:68ch;font-size:15px;margin:0}.focus-note strong{display:block;font-size:17px;margin-bottom:5px}.section-title{display:flex;justify-content:space-between;align-items:baseline;gap:20px;margin-bottom:19px}.section-title p{margin:0;color:var(--muted);font-size:14px}.toolbar{padding:21px;background:var(--paper);border:1px solid var(--line);border-radius:var(--radius);margin-bottom:20px}.controls{display:grid;grid-template-columns:minmax(200px,2fr) repeat(3,minmax(130px,1fr));gap:15px}.control label{display:block;font-size:13px;font-weight:600;margin-bottom:6px}.toolbar-bottom{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-top:16px}.toolbar-bottom button{font-size:13px;min-height:36px;padding:5px 10px}.toolbar-bottom p{margin:0;font-size:13px;color:var(--muted);font-variant-numeric:tabular-nums}.findings{display:grid;gap:0;background:var(--paper);border:1px solid var(--line);border-radius:var(--radius);overflow:clip}.finding{padding:27px 28px;scroll-margin-top:24px}.finding+.finding{border-top:1px solid var(--line)}.finding:target{background:#f2f8f3}.finding-meta{display:flex;align-items:center;gap:11px;font-size:13px;color:var(--muted)}.priority{display:inline-flex;align-items:center;justify-content:center;padding:2px 8px;font-size:12px;line-height:1.8;border-radius:5px;font-weight:750;letter-spacing:.025em;font-variant-numeric:tabular-nums;white-space:nowrap}.P1{background:var(--p1-bg);color:var(--p1)}.P2{background:var(--p2-bg);color:var(--p2)}.P3{background:var(--p3-bg);color:var(--p3)}.run-label{font-size:11px;color:var(--muted);white-space:nowrap}.run-label.latest{background:var(--soft);color:var(--accent);padding:2px 7px;border-radius:4px;font-weight:650}.finding-id{margin-left:auto;text-decoration:none;font-size:12px;color:var(--muted);font-variant-numeric:tabular-nums}.finding-summary{font-size:15px;max-width:72ch;color:var(--muted);margin-bottom:15px}.finding-detail summary{display:flex;align-items:center;justify-content:space-between;gap:18px;font-size:14px;font-weight:600;color:var(--accent);padding:6px 0;list-style:none;min-height:40px}.finding-detail summary::-webkit-details-marker,.run summary::-webkit-details-marker{display:none}.finding-detail summary span,.run summary>span:last-child{font-size:23px;line-height:1;transition:transform .18s ease-out}.finding-detail[open] summary span,.run[open]>summary>span:last-child{transform:rotate(45deg)}.finding-detail[open]>summary{margin-bottom:18px}.prose{font-size:15px;max-width:76ch;overflow-wrap:anywhere}.prose p{margin:0 0 16px}.prose p:last-child{margin-bottom:0}.prose li{padding-left:3px;margin:7px 0}.prose ol,.prose ul{padding-left:24px;margin:18px 0}.prose h3,.prose h4,.prose h5{font-size:19px;margin:27px 0 13px}.evidence{margin-top:26px}.evidence h4{font-size:14px;margin-bottom:12px}.gallery{display:flex;flex-wrap:wrap;gap:14px}.image-link{display:flex;flex-direction:column;flex:1 1 190px;max-width:330px;text-decoration:none;border:1px solid var(--line);border-radius:8px;overflow:hidden;background:#f6f8f6}.image-link img{display:block;width:100%;height:160px;object-fit:contain;padding:7px}.image-link>span{display:flex;justify-content:space-between;border-top:1px solid var(--line);padding:9px 12px;background:var(--paper);font-size:12px}.source-link{margin:22px 0 0;font-size:12px;color:var(--muted)}.empty{padding:35px;text-align:center;background:var(--paper);border:1px solid var(--line);border-radius:var(--radius)}.empty h3{margin-top:0}.empty p{color:var(--muted);font-size:15px}.methods{margin-top:48px}.method-intro{margin:15px 0 23px;color:var(--muted);max-width:70ch;font-size:15px}.run{border-top:1px solid var(--line);padding:0 0 22px}.run>summary{display:flex;justify-content:space-between;gap:20px;align-items:center;list-style:none;padding:22px 0;min-height:76px}.run>summary strong{display:block;font-size:13px;color:var(--muted);margin-bottom:5px}.run>summary>span:first-child{font-size:18px}.table-scroll{overflow-x:auto;max-width:100%;margin:20px 0}table{border-collapse:collapse;text-align:left;width:100%;font-size:14px}th{background:#e7eeea;color:#233f33;font-weight:650}th,td{border-bottom:1px solid var(--line);padding:11px 13px;vertical-align:top}th:first-child,td:first-child{width:50%}.video-detail{margin:20px 0;padding:12px 15px;border:1px solid var(--line);border-radius:8px;background:var(--paper)}.video-detail summary{font-size:14px;min-height:32px}.video-detail video{width:100%;max-height:520px;margin-top:12px;background:#14271f;border-radius:5px}.video-detail p{font-size:12px;color:var(--muted);margin-top:9px}.footer{border-top:1px solid var(--line);padding-top:22px;margin-top:30px;color:var(--muted);font-size:12px}.footer p{max-width:78ch}.footer code{font-size:12px}dialog{padding:0;border:0;border-radius:10px;background:var(--paper);color:var(--ink);max-width:calc(100vw - 32px);max-height:calc(100vh - 32px);box-shadow:0 12px 60px #172c2840}dialog::backdrop{background:#101e19c9}.viewer-head{display:flex;align-items:center;justify-content:space-between;gap:20px;padding:10px 16px;border-bottom:1px solid var(--line);font-size:14px}.viewer-head p{margin:0}.viewer-body{overflow:auto;max-height:calc(100vh - 115px)}.viewer-body img{display:block;max-width:100%;height:auto;margin:auto}.viewer-head button{font-size:13px;min-height:36px}body:has(dialog[open]){overflow:hidden}[hidden]{display:none!important}noscript p{padding:15px;background:var(--p2-bg)}*{scrollbar-width:thin;scrollbar-color:#b0c3b7 transparent}
@media(min-width:1500px){.main{padding-right:80px}}@media(max-width:1000px){.layout{grid-template-columns:185px minmax(0,1fr)}.sidebar{padding:30px 15px}.main{padding:34px 26px 60px}.controls{grid-template-columns:1fr 1fr}.control:first-child,.control:nth-child(2){grid-column:1/-1}.stats .state{margin-left:0;width:100%}}@media(max-width:700px){html{scroll-padding-top:15px}.topbar{padding:14px 18px}.brand span{margin-left:7px;font-size:12px}.topbar .date{font-size:12px}.layout{display:block}.sidebar{position:static;max-height:none;padding:12px 10px;border-bottom:1px solid var(--line)}.sidebar nav{flex-direction:row;flex-wrap:wrap;gap:3px}.sidebar nav a{font-size:12px;padding:8px}.sidebar h2,.legend,.side-note{display:none}.main{border:0;padding:29px 18px 45px}.intro{padding-bottom:22px;margin-bottom:23px}h1{font-size:35px}.intro .lead{font-size:16px}.stats{gap:10px 19px;margin-top:21px}.focus-note{gap:12px;padding:10px 0 27px}.focus-note .mark{width:25px;height:25px}.focus-note p{font-size:14px}.focus-note strong{font-size:16px}.section-title{align-items:center}.section-title p{font-size:12px}.toolbar{padding:15px}.controls{gap:12px}.finding{padding:22px 18px}h3{font-size:19px}.finding-summary,.prose{font-size:14px}.finding-meta{font-size:12px}.gallery{gap:10px}.image-link{max-width:100%;flex-basis:100%}.image-link img{height:210px}.section-title h2,.methods h2{font-size:23px}.toolbar-bottom{align-items:flex-start}.toolbar-bottom p{padding-top:5px}.run>summary>span:first-child{font-size:16px}.table-scroll{font-size:12px}.finding-detail summary{font-size:13px}.main .print-button{font-size:12px;padding:7px 10px}.topbar{gap:10px}}@media(prefers-reduced-motion:reduce){html{scroll-behavior:auto}*{transition:none!important}}@media print{body{background:white;color:black;font-size:11pt}.topbar,.sidebar,.toolbar,.print-button,.finding-detail>summary,.video-detail,dialog,.empty,.skip-link{display:none!important}.layout{display:block}.main{padding:0;border:0;max-width:none}.intro{margin-bottom:18px;padding-bottom:15px}h1{font-size:26pt}.stats{margin-top:15px}.finding{padding:20px 0;break-inside:avoid}.findings{border:0;overflow:visible}.finding-summary,.prose{color:#222}.gallery .image-link{max-width:47%}.image-link img{max-height:180px}.methods{break-before:page}.run>summary{padding:16px 0}.finding-detail:not([open])>*:not(summary){display:block}.run:not([open])>*:not(summary){display:block}.source-link,.footer{font-size:9pt}.focus-note{padding-bottom:16px}.prose{max-width:none}a{color:#164c39}.table-scroll{overflow:visible}}
</style></head>
<body><a class="skip-link" href="#nalezy">Přeskočit na nálezy</a>
<header class="topbar"><a class="brand" href="#prehled">festapp<span>QA zápisník</span></a><span class="date">Stav při testování · 23. 10. 2026</span></header>
<div class="layout"><aside class="sidebar"><nav aria-label="Sekce přehledu"><a href="#prehled">Přehled testování</a><a href="#nalezy" data-all-runs>Všechny nálezy <strong>@@TOTAL@@</strong></a><a href="#pruchody">Průchody a podmínky</a></nav><h2>Jak číst priority</h2><ul class="legend"><li><span class="priority P1">P1</span> Závažný problém</li><li><span class="priority P2">P2</span> Menší problém</li><li><span class="priority P3">P3</span> Drobné zlepšení</li></ul><p class="side-note">Pouze lokální testy se smyšlenými daty.<br><br>Stav oprav zatím nebyl ověřen.</p></aside>
<main class="main" id="prehled"><section class="intro" aria-labelledby="page-title"><h1 id="page-title">Co ukázalo testování Festappu</h1><p class="lead">Zápisník testování katalogu, akcí, formulářů, programu a správy účastníků i přednášejících. Každý nález má postup reprodukce, dopad a důkazy.</p><div class="stats"><span class="total"><strong>@@TOTAL@@</strong> nálezů ze <strong>@@RUNS@@</strong> průchodů</span><span><b class="priority P1">P1</b> <strong>@@P1@@</strong></span><span><b class="priority P2">P2</b> <strong>@@P2@@</strong></span><span><b class="priority P3">P3</b> <strong>@@P3@@</strong></span><span class="state">Opravy zatím neověřeny</span></div></section>
<div class="focus-note"><svg class="mark" viewBox="0 0 32 32" fill="none" aria-hidden="true"><path d="M7 16l6 6L26 9" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/><circle cx="16" cy="16" r="14" stroke="currentColor" stroke-width="1"/></svg><p><strong>Průchod @@RUNS@@: @@LATEST_TITLE@@</strong><b>@@LATEST_COUNT@@ nové nálezy.</b> Výchozí seznam ukazuje jen tento průchod. Starších @@OLDER_COUNT@@ nálezů zůstává dostupných přes filtr Průchod; v posledním běhu nebyly znovu ověřované.</p></div>
<section id="nalezy" aria-labelledby="findings-title"><div class="section-title"><h2 id="findings-title">Nálezy</h2><button class="print-button" id="print" type="button">Tisk / uložit PDF</button></div>
<noscript><p>Všechny nálezy jsou dostupné i bez JavaScriptu. Hledání a filtry potřebují JavaScript.</p></noscript>
<form class="toolbar" id="filters" role="search"><div class="controls"><div class="control"><label for="query">Hledat v nálezech a postupech</label><input id="query" type="search" placeholder="Např. pozvánka, kapacita, odkaz…" autocomplete="off"></div><div class="control"><label for="run">Průchod</label><select id="run">@@RUN_OPTIONS@@</select></div><div class="control"><label for="priority">Závažnost</label><select id="priority"><option value="">Všechny priority</option><option value="P1">P1 - závažné</option><option value="P2">P2 - menší problémy</option><option value="P3">P3 - drobná zlepšení</option></select></div><div class="control"><label for="area">Oblast</label><select id="area"><option value="">Všechny oblasti</option>@@AREA_OPTIONS@@</select></div></div><div class="toolbar-bottom"><p id="count" role="status" aria-live="polite">Zobrazeno @@TOTAL@@ z @@TOTAL@@ nálezů · podle závažnosti</p><button type="reset">Výchozí pohled</button></div></form>
<div class="findings" id="finding-list">@@ARTICLES@@</div><div class="empty" id="empty" hidden><h3>Žádný nález neodpovídá filtrům</h3><p>Zkuste kratší hledání nebo zobrazte všechny nálezy.</p><button type="button" id="show-all">Zobrazit všechny nálezy</button></div></section>
<section class="methods" id="pruchody" aria-labelledby="runs-title"><h2 id="runs-title">Co prošlo a kde jsou meze</h2><p class="method-intro">Nálezy zachycují stav lokálního pracovního stromu při testování. Následující zápisy obsahují i úspěšné scénáře, testovací prostředí a neověřené části.</p>@@REPORTS@@</section>
<footer class="footer"><p>Přehled vychází z původních reportů. Nálezy nejsou automaticky označeny za opravené. Neproběhla kontrola nasazené produkce, skutečné odesílání e-mailů ani platby.</p><p>Obnovení přehledu po doplnění zápisů: <code>python3 automation/build_qa_overview.py</code>. Stránka funguje přímo ze souboru a používá pouze lokální důkazy.</p></footer></main></div>
<dialog id="viewer" aria-labelledby="viewer-caption"><div class="viewer-head"><p id="viewer-caption">Snímek z testování</p><button type="button" id="close-viewer">Zavřít</button></div><div class="viewer-body"><img id="viewer-image" alt=""></div></dialog>
<script>
(()=>{'use strict';const form=document.getElementById('filters'),query=document.getElementById('query'),priority=document.getElementById('priority'),area=document.getElementById('area'),runFilter=document.getElementById('run'),list=document.getElementById('finding-list'),cards=[...list.querySelectorAll('.finding')],empty=document.getElementById('empty'),count=document.getElementById('count');const normalize=s=>s.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();const haystacks=new Map(cards.map(c=>[c,normalize(c.dataset.search)]));function filter(){const words=normalize(query.value.trim()).split(/\s+/).filter(Boolean);let visible=0;for(const card of cards){card.hidden=!!((runFilter.value&&runFilter.value!==card.dataset.run)||(priority.value&&priority.value!==card.dataset.priority)||(area.value&&area.value!==card.dataset.area)||words.some(w=>!haystacks.get(card).includes(w)));if(!card.hidden)visible++}list.hidden=!visible;empty.hidden=!!visible;count.textContent=`Zobrazeno ${visible} z ${cards.length} nálezů · ${runFilter.value ? "průchod " + runFilter.value : "všechny průchody"}`}form.addEventListener('submit',e=>e.preventDefault());form.addEventListener('input',filter);form.addEventListener('change',filter);form.addEventListener('reset',()=>setTimeout(filter,0));function showAll(){form.reset();runFilter.value='';filter()}document.getElementById('show-all').addEventListener('click',()=>{showAll();query.focus()});document.querySelectorAll('[data-all-runs]').forEach(a=>a.addEventListener('click',showAll));function revealHash(){const id=decodeURIComponent(location.hash.slice(1));const card=cards.find(c=>c.id===id);if(!card)return;if(card.hidden)showAll();card.querySelector('details').open=true;requestAnimationFrame(()=>card.scrollIntoView({block:'start'}))}window.addEventListener('hashchange',revealHash);revealHash();const viewer=document.getElementById('viewer'),viewerImage=document.getElementById('viewer-image'),caption=document.getElementById('viewer-caption');document.addEventListener('click',e=>{const a=e.target.closest('a');if(!a||!a.getAttribute('href')?.endsWith('.png')||typeof viewer.showModal!=='function')return;e.preventDefault();viewerImage.src=a.href;viewerImage.alt=a.querySelector('img')?.alt||a.textContent.trim();caption.textContent=a.querySelector('img')?.alt||a.textContent.trim();viewer.showModal()});document.getElementById('close-viewer').addEventListener('click',()=>viewer.close());viewer.addEventListener('click',e=>{if(e.target===viewer)viewer.close()});viewer.addEventListener('close',()=>{viewerImage.removeAttribute('src')});let printState=[];window.addEventListener('beforeprint',()=>{printState=[...document.querySelectorAll('details')].map(d=>[d,d.open]);printState.forEach(([d])=>d.open=true)});window.addEventListener('afterprint',()=>{printState.forEach(([d,open])=>d.open=open);printState=[]});document.getElementById('print').addEventListener('click',()=>window.print());filter()})();
</script></body></html>'''
run_options = f'<option value="">Všechny průchody ({index})</option>' + ''.join(
    f'<option value="{number}"{" selected" if number == len(REPORTS) else ""}>Průchod {number}{" - poslední" if number == len(REPORTS) else ""} ({run_counts[number]})</option>'
    for number in range(len(REPORTS), 0, -1))
PAGE = PAGE.replace('@@RUN_OPTIONS@@', run_options)
PAGE = PAGE.replace('@@LATEST_TITLE@@', esc(REPORTS[-1][2]))
PAGE = PAGE.replace('@@LATEST_COUNT@@', str(run_counts[len(REPORTS)]))
PAGE = PAGE.replace('@@OLDER_COUNT@@', str(index - run_counts[len(REPORTS)]))
PAGE = PAGE.replace('@@AREA_OPTIONS@@', ''.join(f'<option value="{esc(a)}">{esc(a)}</option>' for a in sorted({f[1] for f in FINDINGS})))
PAGE = PAGE.replace('@@ARTICLES@@', '\n'.join(a[2] for a in articles)).replace('@@REPORTS@@', '\n'.join(reports))
for token, value in {'TOTAL': index, 'RUNS': len(REPORTS), **counts}.items():
    PAGE = PAGE.replace('@@' + token + '@@', str(value))
OUTPUT.write_text(PAGE)
print(f'Built {OUTPUT.relative_to(ROOT)}: {index} findings, {counts}.')
