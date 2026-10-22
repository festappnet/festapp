// One page owns playback, including the hero. User intent survives scroll changes.
export function chooseVisiblePlayer(players) {
  return players.filter(player => player.ratio >= .5 && !player.manualPause && !player.ended && !player.error)
    .sort((a, b) => b.ratio - a.ratio)[0] ?? null;
}
export function visibleRatio(rect, viewportHeight, viewportWidth) {
  const height = Math.max(0, Math.min(rect.bottom, viewportHeight) - Math.max(rect.top, 0));
  const width = Math.max(0, Math.min(rect.right, viewportWidth) - Math.max(rect.left, 0));
  return height * width / Math.max(1, Math.min(rect.height, viewportHeight) * Math.min(rect.width, viewportWidth));
}
let cleanupCurrent;
export function initDemoPlayers(root = document) {
  cleanupCurrent?.();
  const win = root.defaultView ?? window;
  const motion = win.matchMedia('(prefers-reduced-motion: reduce)');
  const narrow = win.matchMedia('(max-width: 760px)');
  const adapt = variant => ({...variant, src: narrow.matches && variant.mobileSrc ? variant.mobileSrc : variant.src, poster: narrow.matches && variant.mobilePoster ? variant.mobilePoster : variant.poster});
  const connection = win.navigator.connection;
  const players = [];
  const removers = [];
  let timer;
  let destroyed = false;
  function listen(target, name, callback, options) {
    target.addEventListener(name, callback, options);
    removers.push(() => target.removeEventListener(name, callback, options));
  }
  const automatic = () => !motion.matches && !connection?.saveData;
  const pauseOthers = current => players.forEach(player => { if (player !== current) player.video.pause(); });
  function updateButton(player) {
    const text = player.error ? 'Zkusit znovu' : player.ended ? 'Znovu přehrát' : !player.video.paused ? 'Pozastavit' : 'Přehrát';
    player.button.setAttribute('aria-pressed', String(!player.video.paused));
    player.button.setAttribute('aria-label', `${text}: ${player.variant.description}`);
  }
  function load(player) {
    if (!player.variant.src) return false;
    if (player.video.getAttribute('src') !== player.variant.src) {
      player.video.src = player.variant.src;
      player.video.load();
    }
    return true;
  }
  async function play(player, explicit = false) {
    if (destroyed || root.hidden || (!explicit && (!automatic() || player.manualPause || player.ended || player.error))) return;
    pauseOthers(player);
    player.video.loop = automatic() && player.variants.length === 1;
    if (!load(player)) return;
    if (explicit) {
      player.manualPause = false;
      player.userStarted = true;
      player.error = false;
      player.fallback.hidden = true;
      if (player.ended) player.video.currentTime = 0;
      player.ended = false;
    }
    try { await player.video.play(); } catch { /* Autoplay denial keeps the poster and manual control. */ }
    if (destroyed) player.video.pause();
    updateButton(player);
  }
  function measure() {
    if (destroyed) return;
    players.forEach(player => { player.ratio = visibleRatio(player.stage.getBoundingClientRect(), win.innerHeight, win.innerWidth); });
    const active = root.hidden ? null : automatic() ? chooseVisiblePlayer(players) : players.find(player => player.userStarted && !player.video.paused && player.ratio >= .5);
    players.forEach(player => { if (player !== active) player.video.pause(); });
    if (active && automatic()) play(active);
  }
  function schedule() {
    clearTimeout(timer);
    // Pause immediately on departure; delay starting until the composed reveal settles.
    players.forEach(player => {
      player.ratio = visibleRatio(player.stage.getBoundingClientRect(), win.innerHeight, win.innerWidth);
      if (root.hidden || player.ratio < .5) player.video.pause();
    });
    timer = win.setTimeout(measure, 550);
  }
  root.querySelectorAll('[data-demo-player]').forEach(stage => {
    let variants;
    try { variants = JSON.parse(stage.dataset.variants).map(adapt); } catch { return; }
    const video = stage.querySelector('video');
    const button = stage.querySelector('[data-playback-surface]');
    if (!video || !button || !variants?.length) return;
    const player = { stage, video, button, variants, variant: variants[0], ratio: 0, manualPause: false, ended: false, error: false, fallback: stage.querySelector('.media-fallback') };
    players.push(player);
    if (player.variant.poster) video.poster = player.variant.poster;
    listen(button, 'click', () => {
      if (!video.paused) { player.manualPause = true; video.pause(); updateButton(player); }
      else play(player, true);
    });
    listen(video, 'play', () => { pauseOthers(player); updateButton(player); });
    listen(video, 'pause', () => updateButton(player));
    listen(video, 'ended', () => {
      // Native looping normally bypasses ended; keep visibility and manual intent authoritative.
      if (automatic() && !player.manualPause && player.ratio >= .5 && !root.hidden) {
        if (player.variants.length > 1) {
          player.variant = player.variants[(player.variants.indexOf(player.variant) + 1) % player.variants.length];
          video.poster = player.variant.poster;
          video.setAttribute('aria-label', player.variant.description);
          const download = stage.querySelector('[data-media-download]');
          if (download) download.href = player.variant.src;
        } else video.currentTime = 0;
        play(player);
      } else { player.ended = true; updateButton(player); }
    });
    listen(video, 'error', () => {
      player.error = true;
      video.pause();
      // Removing a failed source exposes the already-rendered poster again.
      video.removeAttribute('src');
      video.load();
      player.fallback.hidden = false;
      updateButton(player);
    });

  });
  listen(win, 'scroll', schedule, { passive: true });
  listen(win, 'resize', schedule, { passive: true });
  listen(root, 'visibilitychange', schedule);
  listen(motion, 'change', schedule);
  if (connection?.addEventListener) listen(connection, 'change', schedule);
  schedule();
  const cleanup = () => {
    destroyed = true;
    clearTimeout(timer);
    removers.forEach(remove => remove());
    players.forEach(player => player.video.pause());
    if (cleanupCurrent === cleanup) cleanupCurrent = null;
  };
  cleanupCurrent = cleanup;
  return cleanup;
}
