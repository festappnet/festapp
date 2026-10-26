/**
 * Base Component class to standardize lifecycle management.
 */
export class Component {
    constructor(hostIdOrElement) {
        if (typeof hostIdOrElement === 'string') {
            this.host = document.getElementById(hostIdOrElement);
        } else {
            this.host = hostIdOrElement; // Assume Element
        }
        
        if (!this.host) {
             console.warn(`Component: Host element not found for ${this.constructor.name}`);
        }
    }

    /**
     * Initializes the component. Call this after constructor.
     */
    init() {
        // Override me
    }

    /**
     * Renders data into the host element.
     * @param {any} data 
     */
    render(data) {
        // Override me
    }

    /**
     * Clears the host element.
     */
    clear() {
        if (this.host) this.host.innerHTML = '';
    }

    /**
     * Safe HTML setting that can be overridden for security.
     * @param {string} html 
     */
    setHtml(html) {
        if (this.host) this.host.innerHTML = html;
    }
}
