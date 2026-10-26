

export class Modal extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
    }

    connectedCallback() {
        this.render();
    }

    render() {
        const style = `
            :host {
                position: fixed;
                top: 0;
                left: 0;
                width: 100%;
                height: 100%;
                z-index: 10000;
                display: flex;
                align-items: center;
                justify-content: center;
                opacity: 0;
                visibility: hidden;
                transition: opacity 0.3s ease, visibility 0.3s;
            }
            :host(.open) {
                opacity: 1;
                visibility: visible;
            }
            .backdrop {
                position: absolute;
                top: 0;
                left: 0;
                width: 100%;
                height: 100%;
                background: rgba(0, 0, 0, 0.5);
                backdrop-filter: blur(4px);
            }
            .modal-content {
                position: relative;
                background: var(--bg-color, #fff); /* Fallback or theme var */
                width: 90%;
                max-width: 400px; /* Default max width */
                border-radius: 12px;
                box-shadow: 0 4px 20px rgba(0,0,0,0.2);
                z-index: 1;
                max-height: 90vh;
                overflow-y: auto;
                display: flex;
                flex-direction: column;
                transform: scale(0.9);
                transition: transform 0.3s cubic-bezier(0.18, 0.89, 0.32, 1.28);
            }
            :host(.open) .modal-content {
                transform: scale(1);
            }
            /* Dark mode support if parent has dark theme */
            /* Dark mode support: rely on body class, not media query directly */
            :host-context(body.dark) .modal-content,
            :host-context(body.dark-mode) .modal-content {
                background: #1e1e1e;
                color: white;
            }
        `;

        this.shadowRoot.innerHTML = `
            <style>${style}</style>
            <div class="backdrop"></div>
            <div class="modal-content">
                <slot></slot>
            </div>
        `;

        this.shadowRoot.querySelector('.backdrop').addEventListener('click', () => {
            this.close();
        });
    }

    open() {
        document.body.appendChild(this);
        // Force reflow
        this.offsetHeight; 
        this.classList.add('open');
        this.setAttribute('open', '');
        document.body.style.overflow = 'hidden'; // Prevent background scrolling
    }

    close() {
        this.classList.remove('open');
        this.removeAttribute('open');
        document.body.style.overflow = '';
        setTimeout(() => {
            if (this.parentNode) {
                this.parentNode.removeChild(this);
            }
        }, 300); // Wait for transition
    }
}

customElements.define('app-modal', Modal);
