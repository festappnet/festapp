import { legacyHashTarget } from '../services/url_normalizer.js';
import { initDemoPlayers } from './demo_player.js';
import { initMotion } from './motion.js';
import { initReferenceCarousels } from './reference_carousel.js';

const target = legacyHashTarget(window.location.href);
if (target) {
    window.location.replace(target);
} else {
    initDemoPlayers();
    initMotion();
    initReferenceCarousels();
}
