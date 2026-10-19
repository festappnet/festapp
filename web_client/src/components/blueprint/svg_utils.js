import { sanitizeSvg } from '../../utils/html.js';


export class SvgUtils {
    /**
     * Prepares the background SVG for the blueprint.
     * Parses the source string, ensures robust dimensions, and injects necessary attributes.
     * Defaults to DOMParser and avoids fragile Regex.
     * 
     * @param {string} source - Tne raw SVG string or URL
     * @returns {Object} { svg: string, isSvg: boolean }
     */
    static prepareBackgroundSvg(source) {
        if (typeof source !== 'string') return { svg: '', isSvg: false };
        if (!source.trim().startsWith('<')) {
            try {
                const url = new URL(source);
                if (['https:', 'http:'].includes(url.protocol)) return { svg: url.href, isSvg: false };
            } catch { /* Invalid image URL. */ }
            return { svg: '', isSvg: false };
        }

        let svgString = sanitizeSvg(source).toString();
        if (!svgString) return { svg: '', isSvg: true };
        let nativeW = 0;
        let nativeH = 0;

        try {
            const parser = new document.defaultView.DOMParser();
            const doc = parser.parseFromString(svgString, "image/svg+xml");
            const svgEl = doc.documentElement;
            
            if (svgEl && svgEl.tagName.toLowerCase() === 'svg') {
                 // extract dimensions
                 const wAttr = svgEl.getAttribute('width');
                 const hAttr = svgEl.getAttribute('height');
                 if (wAttr) nativeW = parseFloat(wAttr);
                 if (hAttr) nativeH = parseFloat(hAttr);
                 
                 // If attributes missing, try viewBox
                 if ((nativeW === 0 || nativeH === 0) && svgEl.getAttribute('viewBox')) {
                      const vb = svgEl.getAttribute('viewBox').split(/[\s,]+/).map(parseFloat);
                      if (vb.length === 4) {
                          nativeW = vb[2];
                          nativeH = vb[3];
                      }
                 }

                 // Inject standard attributes for Blueprint scaling
                 svgEl.classList.add('blueprint-bg-svg');
                 svgEl.setAttribute('width', '100%');
                 svgEl.setAttribute('height', '100%');
                 svgEl.setAttribute('preserveAspectRatio', 'xMinYMin slice');

                 // If viewBox was missing but we found dimensions (unlikely path if we relied on VB, but possible if width/height were present)
                 if (!svgEl.hasAttribute('viewBox') && nativeW > 0 && nativeH > 0) {
                     svgEl.setAttribute('viewBox', `0 0 ${nativeW} ${nativeH}`);
                 }
                 
                 return { svg: new document.defaultView.XMLSerializer().serializeToString(svgEl), isSvg: true };
            }
        } catch(e) {
            console.warn("SVG Parsing/Serialization error", e);
        }

        // Rejected input must never reach the renderer as trusted markup.
        return { svg: '', isSvg: true };
    }
}
