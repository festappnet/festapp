#!/bin/bash
set -euo pipefail
ab() { agent-browser --config /tmp/festapp-setup-20261021/browser.json --headed false --session occasion-performance-20261021 "$@"; }
for run in 0 1 2 3; do
 ab eval "window.__click('Vytvořit novou událost');'menu'" >/dev/null
 ab wait --text 'Krok za krokem' >/dev/null
 ab eval "window.__watchUI('openWizard',()=>[...document.querySelectorAll('[role=button]')].some(e=>e.textContent==='Předloha'));[...document.querySelectorAll('[role=button]')].find(e=>e.textContent.startsWith('Krok za krokem')).click();'start'" >/dev/null
 ab wait --fn 'window.__uiSamples.filter(r=>r.stage==="openWizard").length>='"$((run+1))" >/dev/null
 ab wait 350 >/dev/null
 ab eval "window.__watchUI('transition',()=>document.body.innerText.includes('Otázka 2 z '));window.__watchUI('saved',()=>document.body.innerText.includes('Uloženo'));window.__click('Pokračovat');'next'" >/dev/null
 ab wait --fn 'window.__uiSamples.filter(r=>r.stage==="saved").length>='"$((run+1))" >/dev/null
 ab eval "window.__watchUI('overview',()=>[...document.querySelectorAll('[role=button]')].some(e=>e.textContent==='Vytvořit novou událost'));window.__click('Odejít');'leave'" >/dev/null
 ab wait --fn 'window.__uiSamples.filter(r=>r.stage==="overview").length>='"$((run+1))" >/dev/null
done
ab eval 'window.__uiSamples' > /tmp/festapp-setup-20261021/ui-main-after.json
