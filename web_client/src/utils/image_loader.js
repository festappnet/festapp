
/**
 * Utility to handle smooth image loading animations globally.
 * Uses MutationObserver to detect new images and fades them in once loaded.
 */
export class ImageLoader {
    static init() {
        // Observer config
        const observerConfig = {
            childList: true,
            subtree: true
        };

        // Create observer
        const observer = new MutationObserver((mutations) => {
            mutations.forEach((mutation) => {
                mutation.addedNodes.forEach((node) => {
                    // Check if node is an image
                    if (node.nodeName === 'IMG') {
                        ImageLoader.handleImage(node);
                    }
                    // Check if node has images inside (e.g. innerHTML injection)
                    else if (node.querySelectorAll) {
                        const images = node.querySelectorAll('img');
                        images.forEach(img => ImageLoader.handleImage(img));
                    }
                });
            });
        });

        // Start observing document body
        observer.observe(document.body, observerConfig);

        // Also handle existing images (in case we run after some content is there)
        document.querySelectorAll('img').forEach(img => ImageLoader.handleImage(img));
    }

    static handleImage(img) {
        // Prevent double handling
        if (img.dataset.smoothLoaded) return;
        
        // Mark as handled
        img.dataset.smoothLoaded = 'true';

        // Accessibility: Enforce alt attribute
        if (!img.hasAttribute('alt')) {
            console.warn('ImageLoader: Image missing alt attribute, adding empty alt="" for decoration.', img);
            img.setAttribute('alt', '');
        }

        // Helper to reveal
        const reveal = () => {
            // Force reflow/paint before adding class to ensure transition triggers if needed?
            // Actually requestAnimationFrame is better.
            requestAnimationFrame(() => {
                img.classList.add('loaded');
            });
        };

        // If explicitly requested to skip (e.g. tracking pixels or critical UI icons?)
        // For now apply to all.
        
        // Check for high priority (LCP)
        if (img.getAttribute('fetchpriority') === 'high') {
             img.classList.add('loaded'); // Ensure it's marked as loaded immediately
             return; 
        }

        // Initial state: hidden
        img.classList.add('smooth-load');

        // Check if already complete
        if (img.complete && img.naturalHeight > 0) {
            reveal();
        } else {
            // Wait for load
            img.onload = () => {
                reveal();
            };
            img.onerror = () => {
                // Determine what to do on error. 
                // Reveal anyway so alt text shows? Or keep hidden?
                // Usually better to show something.
                reveal();
            };
        }
    }
}
