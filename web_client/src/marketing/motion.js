let cleanupCurrent;
function initHeroSketch(root, win, preference) {
  const svg = root.querySelector('[data-hero-sketch]');
  if (!svg || !win.requestAnimationFrame) return () => {};
  const pen = svg.querySelector('.sketch-pen');
  const compact = win.matchMedia('(max-width: 760px)');
  let lanes;
  let frame;
  let origin;
  let disposed = false;
  function compose() {
    svg.setAttribute('viewBox', compact.matches ? '0 0 350 650' : '0 0 1200 650');
    svg.setAttribute('preserveAspectRatio', compact.matches ? 'xMidYMid meet' : 'xMidYMid slice');
    lanes = ['left', 'right'].map((side, laneIndex) =>
      [...svg.querySelectorAll(`[data-sketch-side="${side}"]`)].map((element, motifIndex) => {
        const transform = compact.matches
          ? laneIndex === 0
            ? motifIndex % 2 === 0 ? 'translate(-110 -95) scale(1.04)' : 'translate(178 -105) scale(1.02)'
            : motifIndex % 2 === 0 ? 'translate(174 400) scale(1.04)' : 'translate(-140 400) scale(1.04)'
          : laneIndex === 0 ? 'translate(-160 -155) scale(1.9)' : 'translate(880 -130) scale(1.85)';
        element.setAttribute('transform', transform);
        element.dataset.sketchCorner = laneIndex === 0 ? motifIndex % 2 === 0 ? 'top-left' : 'top-right' : motifIndex % 2 === 0 ? 'bottom-right' : 'bottom-left';
        let total = 0;
        const paths = [...element.querySelectorAll('path')].map(path => {
          const length = path.getTotalLength();
          const start = total;
          total += length;
          return {path, length, start};
        });
        return {element, paths, total, matrix: element.transform.baseVal.consolidate().matrix};
      })
    );
  }
  function render(scene, progress, fill, showPen = false) {
    const matrix = scene.element.getScreenCTM();
    scene.element.style.strokeWidth = String((compact.matches ? 1.65 : 1.45) / (matrix ? Math.hypot(matrix.a, matrix.b) || 1 : 1));
    scene.element.style.opacity = '1';
    scene.element.dataset.progress = progress.toFixed(3);
    scene.element.style.setProperty('--sketch-fill', String(fill));
    const distance = scene.total * progress;
    let head = scene.paths[0];
    scene.paths.forEach(item => {
      const local = Math.max(0, Math.min(1, (distance - item.start) / item.length));
      item.path.style.visibility = local > 0 ? 'visible' : 'hidden';
      item.path.style.strokeDashoffset = String(1 - local);
      if (distance >= item.start) head = item;
    });
    if (showPen && progress > 0 && progress < 1) {
      const local = head.path.getPointAtLength(Math.max(0, Math.min(head.length, distance - head.start)));
      const point = svg.createSVGPoint();
      point.x = local.x;
      point.y = local.y;
      const mapped = point.matrixTransform(scene.matrix);
      pen.setAttribute('cx', String(mapped.x));
      pen.setAttribute('cy', String(mapped.y));
      pen.style.opacity = '1';
    }
  }
  function clear() {
    lanes.flat().forEach(scene => { scene.element.style.opacity = '0'; });
    pen.style.opacity = '0';
  }
  function still() {
    svg.removeAttribute('data-sketch-active');
    clear();
    lanes.forEach(lane => render(lane[0], 1, 1));
  }
  function draw(now) {
    if (disposed || preference.matches) return;
    origin ??= now;
    const elapsed = (now - origin) / 1000;
    const step = Math.floor(elapsed / 4.8);
    const time = elapsed % 4.8;
    const active = step % 2;
    clear();
    svg.setAttribute('data-sketch-active', '');
    svg.dataset.scene = String(step);
    svg.dataset.side = active === 0 ? 'left' : 'right';
    lanes.forEach((lane, laneIndex) => {
      const latest = step - (step % 2 === laneIndex ? 0 : 1);
      if (latest < 0) return;
      const index = Math.floor(latest / 2) % lane.length;
      const isActive = laneIndex === active;
      if (!isActive) {
        render(lane[index], 1, 1);
        return;
      }
      // Only this side clears; its partner stays fully drawn throughout.
      const erase = latest >= 2 ? .5 : 0;
      let progress, fill, phase;
      if (time < erase) {
        progress = 1 - time / erase;
        fill = Math.max(0, 1 - time / .25);
        phase = 'erase';
        render(lane[(index + lane.length - 1) % lane.length], progress, fill, true);
      } else {
        const local = time - erase;
        progress = Math.min(1, local / 2.2);
        fill = Math.max(0, Math.min(1, (local - 2.2) / .35));
        phase = local < 2.2 ? 'draw' : local < 2.55 ? 'fill' : 'hold';
        render(lane[index], progress, fill, true);
      }
      svg.dataset.phase = phase;
      svg.dataset.drawProgress = progress.toFixed(3);
    });
    frame = win.requestAnimationFrame(draw);
  }
  function preferences() {
    win.cancelAnimationFrame(frame);
    if (preference.matches) still();
    else { origin = undefined; frame = win.requestAnimationFrame(draw); }
  }
  function resize() { compose(); preferences(); }
  compose();
  compact.addEventListener('change', resize);
  preference.addEventListener('change', preferences);
  preferences();
  return () => {
    disposed = true;
    win.cancelAnimationFrame(frame);
    preference.removeEventListener('change', preferences);
    compact.removeEventListener('change', resize);
    still();
  };
}


function initClosingArt(root, win, preference) {
  const art = root.querySelector('[data-closing-art]');
  if (!art || !win.requestAnimationFrame) return () => {};
  const pen = art.querySelector('[data-closing-pen]');
  const scenes = [...art.querySelectorAll('[data-closing-motif]')].map(element => {
    let total = 0;
    const paths = [...element.querySelectorAll('path')].map(path => {
      const length = path.getTotalLength(), start = total;
      total += length;
      return {path, length, start};
    });
    return {element, paths, total};
  });
  let frame, origin, visible = !win.IntersectionObserver, disposed = false;
  const clear = () => {
    scenes.forEach(scene => { scene.element.style.opacity = '0'; });
    pen.style.opacity = '0';
  };
  function render(scene, progress, fill, drawing) {
    const matrix = scene.element.getScreenCTM();
    scene.element.style.strokeWidth = String(1.2 / (matrix ? Math.hypot(matrix.a, matrix.b) || 1 : 1));
    scene.element.style.opacity = '1';
    scene.element.style.setProperty('--closing-fill', String(fill));
    const distance = scene.total * progress;
    let head = scene.paths[0];
    scene.paths.forEach(item => {
      const local = Math.max(0, Math.min(1, (distance - item.start) / item.length));
      item.path.style.visibility = local > 0 ? 'visible' : 'hidden';
      item.path.style.strokeDashoffset = String(1 - local);
      if (distance >= item.start) head = item;
    });
    if (drawing && progress > 0 && progress < 1) {
      const point = head.path.getPointAtLength(Math.max(0, Math.min(head.length, distance - head.start)));
      pen.setAttribute('cx', point.x); pen.setAttribute('cy', point.y); pen.style.opacity = '1';
    }
  }
  function still() {
    clear(); render(scenes[0], 1, 1, false);
    art.dataset.phase = 'still'; art.dataset.motif = scenes[0].element.dataset.closingMotif;
  }
  function draw(now) {
    if (disposed || !visible || preference.matches) return;
    origin ??= now;
    const elapsed = (now - origin) / 1000, step = Math.floor(elapsed / 4.8), time = elapsed % 4.8;
    const erase = step > 0 ? .45 : 0;
    clear();
    if (time < erase) {
      const scene = scenes[(step - 1) % scenes.length];
      render(scene, 1 - time / erase, Math.max(0, 1 - time / .2), true);
      art.dataset.phase = 'erase'; art.dataset.motif = scene.element.dataset.closingMotif;
    } else {
      const scene = scenes[step % scenes.length], local = time - erase;
      const progress = Math.min(1, local / 2), fill = Math.max(0, Math.min(1, (local - 2) / .3));
      render(scene, progress, fill, true);
      art.dataset.phase = local < 2 ? 'draw' : local < 2.3 ? 'fill' : 'hold';
      art.dataset.motif = scene.element.dataset.closingMotif;
      art.dataset.progress = progress.toFixed(3);
    }
    frame = win.requestAnimationFrame(draw);
  }
  function update() {
    win.cancelAnimationFrame(frame);
    if (preference.matches) still();
    else if (visible) { origin = undefined; frame = win.requestAnimationFrame(draw); }
  }
  const observer = win.IntersectionObserver ? new win.IntersectionObserver(entries => {
    visible = entries.some(entry => entry.isIntersecting); update();
  }) : null;
  observer?.observe(art);
  preference.addEventListener('change', update);
  still(); update();
  return () => { disposed = true; win.cancelAnimationFrame(frame); observer?.disconnect(); preference.removeEventListener('change', update); still(); };
}

export function initMotion(root = document) {
  cleanupCurrent?.();
  const win = root.defaultView ?? window;
  const sections = [...root.querySelectorAll('.reveal')];
  const media = win.matchMedia('(prefers-reduced-motion: reduce)');
  const stopSketch = initHeroSketch(root, win, media);
  const stopClosing = initClosingArt(root, win, media);
  let observer;
  const reveal = element => { element.classList.remove('pending'); observer?.unobserve(element); };
  const revealAll = () => { sections.forEach(reveal); root.documentElement.classList.remove('motion-ready'); };
  function anchor(event) {
    const link = event.target.closest?.('a[href^="#"]');
    if (!link) return;
    const target = root.getElementById(link.getAttribute('href').slice(1));
    if (target) { reveal(target); target.querySelectorAll('.reveal').forEach(reveal); }
    root.querySelectorAll('.mobile-menu[open]').forEach(menu => { menu.open = false; });
  }
  function focus(event) {
    const section = event.target.closest?.('.reveal');
    if (section) reveal(section);
  }
  function preferences() { if (media.matches) revealAll(); }
  try {
    if (!media.matches && win.IntersectionObserver) {
      observer = new win.IntersectionObserver(entries => entries.forEach(entry => { if (entry.isIntersecting) reveal(entry.target); }), { threshold: .05, rootMargin: '0px 0px -8% 0px' });
      sections.forEach(section => {
        // Never hide already visible content or the destination of a deep link.
        if (section.getBoundingClientRect().top > win.innerHeight && `#${section.id}` !== win.location.hash) section.classList.add('pending');
        observer.observe(section);
      });
      root.documentElement.classList.add('motion-ready');
    }
  } catch { revealAll(); }
  root.addEventListener('click', anchor);
  root.addEventListener('focusin', focus);
  media.addEventListener('change', preferences);
  const cleanup = () => { stopSketch(); stopClosing(); observer?.disconnect(); root.removeEventListener('click', anchor); root.removeEventListener('focusin', focus); media.removeEventListener('change', preferences); revealAll(); if (cleanupCurrent === cleanup) cleanupCurrent = null; };
  cleanupCurrent = cleanup;
  return cleanup;
}
