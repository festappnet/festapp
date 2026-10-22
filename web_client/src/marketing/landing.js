import { initDemoPlayers } from './demo_player.js';
import { initMotion } from './motion.js';
import { initReferenceCarousels } from './reference_carousel.js';

// Legacy app/scanner hash links still enter through the marketing root.
const current = new URL(window.location.href);
const legacy = current.hash.startsWith('#/') ? new URL(current.hash.slice(1), current.origin) : null;
const target = legacy?.origin === current.origin && legacy.pathname !== '/' ? legacy.pathname + legacy.search + legacy.hash : null;
if (target) {
    window.location.replace(target);
} else {
    initDemoPlayers();
    initMotion();
    initReferenceCarousels();
}
