import { AppConfig } from '../app_config.js';

export class SeoService {
    
    /**
     * Updates SEO meta tags based on the FormModel.
     * @param {FormModel} formModel 
     */
    static updateMetaTags(formModel, currentUrl) {
        if (!formModel) return;

        const title = formModel.title || AppConfig.appName;
        
        // Extract plain text description from HTML header
        let description = '';
        let imageData = null;

        if (formModel.header) {
            description = this._extractTextFromHtml(formModel.header);
            imageData = this._extractImageFromHtml(formModel.header);
        }

        // Fallbacks
        if (!description) {
            description = formModel.description || 'Rychlé a jednoduché založení události, prodej vstupenek a registrace.';
        }
        
        // Add date info if available
        if (formModel.startTime) {
            const dateStr = this._formatDate(formModel.startTime);
            if (dateStr) {
                description = `${dateStr} - ${description}`;
            }
        }

        // 1. Update Title
        document.title = `${title} - ${AppConfig.appTitleShort}`;

        // 2. Update Description
        this._setMetaTag('name', 'description', description);

        // 3. Update OG Tags
        this._setMetaTag('property', 'og:title', document.title);
        this._setMetaTag('property', 'og:description', description);
        
        if (currentUrl) {
            const canonicalUrl = new URL(currentUrl, window.location.origin);
            canonicalUrl.search = '';
            canonicalUrl.hash = '';
            let canonical = document.querySelector('link[rel="canonical"]');
            if (!canonical) {
                canonical = document.createElement('link');
                canonical.rel = 'canonical';
                document.head.appendChild(canonical);
            }
            canonical.href = canonicalUrl.href;
            this._setMetaTag('property', 'og:url', canonicalUrl.href);
            this._setMetaTag('property', 'twitter:url', canonicalUrl.href);
        }

        const imageUrl = imageData?.src || new URL('/android-chrome-512x512.png', window.location.origin).href;
        this._setMetaTag('property', 'og:image', imageUrl);
        for (const dimension of ['width', 'height']) {
            if (imageData?.[dimension]) this._setMetaTag('property', `og:image:${dimension}`, imageData[dimension]);
            else document.querySelector(`meta[property="og:image:${dimension}"]`)?.remove();
        }

        // 4. Update Twitter Tags
        this._setMetaTag('property', 'twitter:title', document.title);
        this._setMetaTag('property', 'twitter:description', description);
        this._setMetaTag('property', 'twitter:image', imageUrl);
    }

    static _setMetaTag(attrName, attrValue, content) {
        // Truncate content if too long (standard SEO practice)
        // Meta desc ~160 chars, OG desc ~200-300 chars. 
        // We'll be generous but safe to avoid massive HTML dumps being put into attribute.
        let safeContent = content ? String(content).trim() : '';
        // Only truncate description/title-like fields, not URLs or numbers
        const isUrl = attrValue.includes('image') || attrValue.includes('url');
        const isNum = attrValue.includes('width') || attrValue.includes('height');

        if (!isUrl && !isNum && safeContent.length > 300) {
            safeContent = safeContent.substring(0, 297) + '...';
        }

        let element = document.querySelector(`meta[${attrName}="${attrValue}"]`);
        
        if (!element) {
            element = document.createElement('meta');
            element.setAttribute(attrName, attrValue);
            document.head.appendChild(element);
        }
        
        element.setAttribute('content', safeContent);
    }

    static _extractTextFromHtml(htmlString) {
        if (!htmlString) return '';
        const parser = new DOMParser();
        const doc = parser.parseFromString(htmlString, 'text/html');
        return doc.body.textContent || "";
    }

    static _extractImageFromHtml(htmlString) {
        if (!htmlString) return null;
        const parser = new DOMParser();
        const doc = parser.parseFromString(htmlString, 'text/html');
        const img = doc.querySelector('img');
        
        if (img) {
            return {
                src: img.src,
                width: img.getAttribute('width'),
                height: img.getAttribute('height')
            };
        }
        return null;
    }

    static _formatDate(dateObj) {
        if (!dateObj) return '';
        return dateObj.toLocaleDateString('cs-CZ', {
            day: 'numeric', 
            month: 'numeric', 
            year: 'numeric'
        });
    }
}
