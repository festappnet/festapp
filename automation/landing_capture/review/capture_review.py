#!/usr/bin/env python3
"""Capture static review evidence using an owned, isolated headless browser."""
import argparse
import json
from pathlib import Path
import subprocess
import time
import uuid


class Browser:
    def __init__(self, output):
        config = output / 'browser-empty.json'
        config.write_text('{}\n')
        config.chmod(0o600)
        self.prefix = ['agent-browser', '--config', str(config), '--headed', 'false',
                       '--hide-scrollbars', 'false', '--namespace', 'landing-review-' + uuid.uuid4().hex[:12], '--session', 'review']

    def run(self, *args):
        result = subprocess.run(self.prefix + list(args), text=True, capture_output=True, timeout=60)
        if result.returncode:
            raise RuntimeError(f'Browser command {args[:2]} failed: {result.stderr.strip()} {result.stdout.strip()}')
        return result.stdout.strip()

    def data(self, *args):
        result = json.loads(self.run('--json', *args))
        if not result.get('success', False):
            raise RuntimeError(str(result.get('error')))
        return result['data']

    def js(self, source):
        return self.data('eval', source)['result']

    def verify_owned(self):
        info = self.data('session', 'info')
        runtime = info['runtime']
        assert runtime['browserLaunched'] and runtime['pageCount'] == 1
        assert runtime['engine'] == 'chrome'
        pid = info['pid']
        processes = subprocess.check_output(['ps', '-axo', 'ppid=,pid=,command='], text=True)
        own = [line for line in processes.splitlines() if line.strip().split(maxsplit=2)[0] == str(pid)]
        assert any('Chrome' in line and '--headless' in line for line in own), 'No owned headless Chrome child'
        return {'ownedHeadlessChild': True, 'pageCount': 1, 'namespace': info['namespace']}


def capture(preview, output):
    output.mkdir(parents=True, exist_ok=True)
    browser = Browser(output)
    results = {'isolation': None, 'viewports': [], 'scrolls': {}}
    owned = False
    try:
        browser.run('open', preview.as_uri())
        results['isolation'] = browser.verify_owned()
        owned = True
        for width, height in [(320,844),(390,844),(768,1000),(1440,1000)]:
            browser.run('set', 'viewport', str(width), str(height))
            browser.run('reload')
            browser.js('document.documentElement.style.scrollBehavior="auto"; window.scrollTo({top:0,behavior:"instant"}); [...document.images].forEach(i=>i.loading="eager")')
            browser.run('wait', '--fn', '[...document.images].every(i=>i.complete)')
            time.sleep(1.1)
            metrics = browser.js('({width:innerWidth,scrollWidth:document.documentElement.scrollWidth,brokenImages:[...document.images].filter(i=>!i.naturalWidth).map(i=>i.src),h1:document.querySelectorAll("h1").length,decorativeArrows:[...document.querySelectorAll("a")].filter(a=>/[↗↓→]/.test(a.textContent)).length,referenceCards:document.querySelectorAll(".reference-card").length,referenceScrollbarHidden:getComputedStyle(document.querySelector("[data-reference-track]")).scrollbarWidth==="none"})')
            results['viewports'].append(metrics)
            browser.run('screenshot', str(output / f'hero-{width}.png'))
            if width == 390:
                browser.run('wait', '--fn', 'document.querySelector("[data-hero-sketch]").dataset.phase==="hold"')
                results['mobileSketch'] = browser.js('({viewBox:document.querySelector("[data-hero-sketch]").getAttribute("viewBox"),opacity:getComputedStyle(document.querySelector("[data-hero-sketch]")).opacity,visiblePaths:[...document.querySelector(".sketch-scene").querySelectorAll("path")].filter(p=>getComputedStyle(p).display!=="none").length})')
                browser.run('screenshot', str(output / 'hero-mobile-drawn.png'))
                browser.run('record', 'start', str(output / 'hero-motion.webm'))
                time.sleep(18)
                browser.run('record', 'stop')
            if width == 1440:
                browser.js('document.getElementById("planek").scrollIntoView({block:"start",behavior:"instant"})')
                time.sleep(.7)
                results['desktopEditor'] = browser.js('(()=>{const r=document.querySelector("#planek video").getBoundingClientRect();return {width:r.width,height:r.height,viewportHeight:innerHeight}})()')
                assert results['desktopEditor']['width'] <= 821 and results['desktopEditor']['height'] <= 581
                browser.run('screenshot', str(output / 'planek-desktop.png'))

            for section in (['reference','platby','formular','vstupenka','vyber-mist','odbaveni','pro-technicke-tymy'] if width in (390,1440) else []):
                browser.js(f'document.getElementById({json.dumps(section)})?.scrollIntoView({{block:"start",behavior:"instant"}})')
                time.sleep(1.1)
                browser.run('screenshot', str(output / f'{section}-{width}.png'))
        # Observe actual alternating drawing: the partner survives erase and redraw.
        browser.run('reload')
        browser.js('window.scrollTo({top:0,behavior:"instant"})')
        sketch_state = '(()=>{const s=document.querySelector("[data-hero-sketch]");return {data:{...s.dataset},visible:[...s.querySelectorAll("[data-sketch-motif]")].filter(e=>e.style.opacity==="1").map(e=>({motif:e.dataset.sketchMotif,side:e.dataset.sketchSide,progress:+e.dataset.progress,fill:+e.style.getPropertyValue("--sketch-fill")}))}})()'
        browser.run('wait', '--fn', 'document.querySelector("[data-hero-sketch]").dataset.scene==="0" && document.querySelector("[data-hero-sketch]").dataset.phase==="hold"')
        initial = browser.js(sketch_state)
        browser.run('screenshot', str(output / 'hero-drawn.png'))
        browser.run('wait', '--fn', 'document.querySelector("[data-hero-sketch]").dataset.scene==="1" && +document.querySelector("[data-hero-sketch]").dataset.drawProgress>.3')
        right_drawing = browser.js(sketch_state)
        assert any(v['side']=='left' and v['progress']==1 and v['fill']==1 for v in right_drawing['visible'])
        browser.run('screenshot', str(output / 'hero-paired.png'))
        browser.run('wait', '--fn', 'document.querySelector("[data-hero-sketch]").dataset.scene==="2" && document.querySelector("[data-hero-sketch]").dataset.phase==="erase"')
        left_clearing = browser.js(sketch_state)
        assert any(v['side']=='right' and v['progress']==1 and v['fill']==1 for v in left_clearing['visible'])
        browser.run('screenshot', str(output / 'hero-turnover.png'))
        browser.run('wait', '--fn', 'document.querySelector("[data-hero-sketch]").dataset.scene==="2" && document.querySelector("[data-hero-sketch]").dataset.phase==="hold"')
        browser.run('screenshot', str(output / 'hero-ticket.png'))
        results['architecture'] = {'initial':initial,'partnerDuringDraw':right_drawing,'partnerDuringErase':left_clearing,'motifs':browser.js('document.querySelectorAll("[data-sketch-motif]").length')}
        assert results['architecture']['motifs'] >= 12
        results['architecture']['hallCapacities'] = browser.js('[...document.querySelectorAll("[data-sketch-seats]")].map(e=>+e.dataset.sketchSeats).filter(Boolean)')
        assert max(results['architecture']['hallCapacities']) >= 180

        sizes = browser.js('(()=>{const e=document.querySelector("#vyber-mist .feature-media");return {width:e.getBoundingClientRect().width,height:e.getBoundingClientRect().height}})()')
        assert sizes['width'] <= 331 and sizes['height'] < 760, sizes
        results['phoneSize'] = sizes
        results['contentContract'] = browser.js('({title:document.querySelector("h1").textContent,formResultTabs:document.querySelectorAll("#formular [data-variant=form-style]").length,paymentVideos:document.querySelectorAll("#platby video").length,paymentImages:document.querySelectorAll("#platby img").length,mediaBorders:[...document.querySelectorAll(".feature .media-stage")].map(e=>getComputedStyle(e).borderTopWidth),visibleControlLabels:document.querySelectorAll(".media-toolbar,.media-title,.variant-tabs").length,ticketCards:document.querySelectorAll("#vstupenka .output-card").length})')
        assert results['contentContract']['title'] == 'Vstupenkypro Vaši akci.'
        results['navigation'] = browser.js('({create:document.querySelector(".hero .primary").getAttribute("href"),signin:document.querySelector(".header-signin").getAttribute("href"),headerCreate:document.querySelector(".header-cta").getAttribute("href")})')
        assert results['navigation']['create'].endswith('/events?create=1')
        assert results['navigation']['headerCreate'].endswith('/events?create=1')
        assert results['navigation']['signin'].endswith('/login')

        assert not results['contentContract']['paymentVideos'] and not results['contentContract']['paymentImages'] and not results['contentContract']['formResultTabs']
        assert results['contentContract']['ticketCards'] >= 9
        assert results['contentContract']['visibleControlLabels'] == 0
        assert all(border == '0px' for border in results['contentContract']['mediaBorders'])
        # Prove carousel behavior in the actual full-page preview.
        browser.js('document.getElementById("reference").scrollIntoView({block:"start",behavior:"instant"});document.querySelector("[data-reference-next]").click()')
        browser.run('wait', '--fn', 'document.querySelector("[data-reference-track]").scrollLeft>0')
        time.sleep(.4)
        results['carousel'] = browser.js('({left:document.querySelector("[data-reference-track]").scrollLeft,buttonsVisible:!document.querySelector("[data-reference-controls]").hidden,cards:document.querySelectorAll(".reference-card").length})')
        # No visible toolbar: clicking the video pauses its automatic sequence.
        browser.js('document.querySelector("#planek .media-viewport").scrollIntoView({block:"center",behavior:"instant"})')
        browser.run('wait', '--fn', '(()=>{const v=document.querySelector("#planek video");return v.readyState>=2&&!v.paused})()')
        before_source = browser.js('document.querySelector("#planek video").currentSrc')
        browser.js('(()=>{const v=document.querySelector("#planek video");v.currentTime=v.duration-.2})()')
        browser.run('wait', '--fn', '(()=>{const v=document.querySelector("#planek video");return v.currentSrc!=='+json.dumps(before_source)+'&&v.readyState>=2&&!v.paused})()')
        browser.js('document.querySelector("#planek [data-playback-surface]").click();window.dispatchEvent(new Event("scroll"))')
        time.sleep(.7)
        results['playback'] = browser.js('(()=>{const v=document.querySelector("#planek video");return {sequenceAdvanced:true,manualPause:v.paused,visibleControls:document.querySelectorAll(".media-toolbar,.variant-tabs").length}})()')
        assert results['playback']['manualPause'] and not results['playback']['visibleControls']
        browser.js('document.querySelector("#vstupenka .media-viewport").scrollIntoView({block:"center",behavior:"instant"})')
        browser.run('wait', '--fn', '(()=>{const v=document.querySelector("#vstupenka video");return v.readyState>=2&&!v.paused&&v.loop})()')
        browser.js('(()=>{const v=document.querySelector("#vstupenka video");v.currentTime=v.duration-.2})()')
        browser.run('wait', '--fn', '(()=>{const v=document.querySelector("#vstupenka video");return !v.paused&&v.currentTime<2})()')
        results['playback']['nativeLoop'] = True
        accessibility = browser.data('a11y')
        (output / 'a11y.json').write_text(json.dumps(accessibility, ensure_ascii=False, indent=2))
        results['a11yViolations'] = accessibility['counts']['violations']
        for label, width, height in [('desktop',1440,1000),('mobile',390,844)]:
            browser.run('set', 'viewport', str(width), str(height))
            browser.run('set', 'media', 'light')
            browser.run('open', preview.as_uri())
            browser.js('document.documentElement.style.scrollBehavior="auto";window.scrollTo({top:0,behavior:"instant"})')
            time.sleep(.8)
            video = output / f'scroll-{label}.webm'
            if video.exists(): video.unlink()
            browser.run('record', 'start', str(video))
            # Emulation/navigation after record-start can replace the context and
            # discard recording. Only read DOM and scroll until record-stop.
            dimensions = browser.js('({width:innerWidth,height:innerHeight})')
            assert dimensions['width'] == width, dimensions
            height_total = browser.js('document.documentElement.scrollHeight')
            samples = []
            for y in range(0, height_total, 650 if width > 800 else 500):
                browser.js(f'window.scrollTo({{top:{y},behavior:"instant"}})')
                time.sleep(.65)
                samples.append(browser.js('[...document.querySelectorAll("video")].filter(v=>!v.paused&&!v.ended).length'))
            browser.run('record', 'stop')
            results['scrolls'][label] = {'width':width,'height':height,'reducedMotion':False,'maxPlaying':max(samples,default=0),'samples':len(samples)}
        # Verify reduced motion independently: recording-start may reset media
        # emulation, so a normal recording cannot establish this preference.
        browser.run('set', 'media', 'light', 'reduced-motion')
        browser.run('reload')
        browser.js('window.scrollTo({top:0,behavior:"instant"})')
        time.sleep(.7)
        reduced_samples = []
        for section in ['planek','formular','vstupenka','vyber-mist','odbaveni','prehled']:
            browser.js(f'document.getElementById({json.dumps(section)})?.scrollIntoView({{block:"start",behavior:"instant"}})')
            time.sleep(.25)
            reduced_samples.append(browser.js('[...document.querySelectorAll("video")].filter(v=>!v.paused&&!v.ended).length'))
        results['reducedMotion'] = browser.js('({matches:matchMedia("(prefers-reduced-motion: reduce)").matches,playing:[...document.querySelectorAll("video")].filter(v=>!v.paused&&!v.ended).length,pending:document.querySelectorAll(".reveal.pending").length})')
        results['reducedMotion']['maxPlaying'] = max(reduced_samples,default=0)
        browser.run('screenshot', str(output / 'reduced-motion.png'))
        (output / 'results.json').write_text(json.dumps(results, ensure_ascii=False, indent=2))
        assert all(v['scrollWidth'] <= v['width'] and not v['brokenImages'] and v['h1'] == 1 and not v['decorativeArrows'] and v['referenceScrollbarHidden'] for v in results['viewports'])
        assert results['a11yViolations'] == 0
        assert all(s['maxPlaying'] <= (0 if s['reducedMotion'] else 1) for s in results['scrolls'].values())
        assert results['reducedMotion']['matches'] and not results['reducedMotion']['pending'] and not results['reducedMotion']['maxPlaying']
        print('Static review PASS: 4 viewports, carousel, accessibility, desktop/mobile scroll and reduced-motion state')
    finally:
        (output / 'results.json').write_text(json.dumps(results, ensure_ascii=False, indent=2))
        if owned:
            browser.run('close')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--preview', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    capture(args.preview.resolve(), args.output.resolve())
