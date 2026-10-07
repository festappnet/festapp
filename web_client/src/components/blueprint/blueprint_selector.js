
import { FormStrings } from '../forms/form_strings.js';
import { CommonStrings } from '../shared/common_strings.js';
import { DbForms } from '../forms/db_forms.js';
import { BlueprintRenderer } from './blueprint_renderer.js';
import { SeatStates } from './blueprint_config.js';

// Dynamically load CSS for non-bundler environments
// Basic style injection
// Only run if document is available
if (typeof document !== 'undefined') {
    const cssUrl = new URL('./blueprint.css', import.meta.url).href;
    if (!document.querySelector(`link[href="${cssUrl}"]`)) {
        const link = document.createElement('link');
        link.rel = 'stylesheet';
        link.href = cssUrl;
        document.head.appendChild(link);
    }
}

export class BlueprintSelector {
    constructor() {
        this.renderer = null;
    }

    async open(session, field, initialSeats) {
        // Extract from session
        const formModel = session.formModel;
        // --- Viewport Lock ---
        // Removed global viewport modification which risks breaking host page


        // --- Container Setup (Full Screen) ---
        const container = document.createElement('div');
        container.className = 'blueprint-modal-container';
        // Double enforce via inline style
        container.style.touchAction = 'none';
        
        document.body.appendChild(container);

        // --- Layout Mode ---
        document.body.classList.add('blueprint-active'); 
        document.documentElement.classList.add('blueprint-active'); 
        
        // Removed manual hack for #form-page-container and #floating-price-widget
        // Handled by CSS: body.blueprint-active ...

        // --- Back/Continue Button ---
        const confirmBtn = document.createElement('button');
        confirmBtn.className = 'btn btn-primary btn-submit blueprint-btn-confirm'; 
        confirmBtn.type = 'button';
        confirmBtn.textContent = FormStrings.buttonContinue; 
        
        // --- Content Area ---
        const content = document.createElement('div');
        content.className = 'blueprint-content';
        
        container.appendChild(content);
        container.appendChild(confirmBtn);

        // --- API & State ---
        let blueprintData = null;
        this.selectedSeats = initialSeats ? [...initialSeats] : []; // Local state
        
        // --- History / Navigation ---
        // Push a new state so the back button closes the modal instead of navigating away
        const stateId = 'seat-selection';
        window.history.pushState({ overlay: stateId }, '', '#seat-selection');

        // Global Event Killer removed in favor of CSS handling (touch-action: none on container)
        // and targeted gesture handling in BlueprintRenderer/GestureController


        const popHandler = (event) => {
            // If we are popping state (back button), we clean up
            // Check if we are back to expected state or just general back
            cleanup();
        };

        const cleanup = () => {
             // Restore Viewport - not needed as we didn't touch it


             // 1. Collect selected seats before destroying if this was a valid exit?
             // Actually, popstate means CANCEL usually, or just "Close".
             // But in mobile app behavior, back button might mean "Done" if selection is immediate.
             // Here we treat explicit "Continue" as confirm, and Back as "Cancel/Confirm" depending on logic.
             // Flutter app: Back button confirms if not cancelled explicitly.
             // Let's invoke callback with current selection on cleanup?
             // Logic: If user clicks Back, they might expect their selection to be saved.
             // Replicating Flutter: _hideSeatReservation completes with selectedSeats.
             
             // Replicating Flutter: _hideSeatReservation completes with selectedSeats.
             // We no longer use callback. Session events drive the UI.

             if (this.renderer) this.renderer.destroy();
             
             document.body.classList.remove('blueprint-active');
             document.documentElement.classList.remove('blueprint-active');
             container.remove();
             window.removeEventListener('popstate', popHandler);
        };

        // When clicking continue/back explicitly
        confirmBtn.onclick = () => {
             // Invokes cleanup via history back, which triggers popHandler
             window.history.back(); 
        };
        
        window.addEventListener('popstate', popHandler);

        // --- Load Data ---
        try {
            content.innerHTML = `<div class="blueprint-loading"><div class="sp-loader"></div></div>`;

            let blueprintId = null;
            if (field && field.data && field.data.blueprintId) {
                blueprintId = field.data.blueprintId;
            } else if (formModel.blueprint) {
                blueprintId = (typeof formModel.blueprint === 'object') ? formModel.blueprint.id : formModel.blueprint;
            }

            if (!blueprintId) throw new Error("Blueprint ID missing");

            blueprintData = await DbForms.getBlueprint(
                formModel.secret,
                formModel.key,
                blueprintId
            );

            // --- Fix: Adoption of Blueprint Secret ---
            // The backend may return a persistent secret if we sent a partial/empty one.
            // We must adopt this secret for the session.
            if (blueprintData && blueprintData.secret) {
                formModel.secret = blueprintData.secret;
                this.reservationSecret = blueprintData.secret;
                
                // Update Session Payload for submit
                if (session && session.payload) {
                    session.payload[DbForms.metaSecret] = blueprintData.secret;
                }
            } else {
                 this.reservationSecret = formModel.secret; 
            }

            if (this.selectedSeats.length > 0) {
                this.selectedSeats.forEach(initialSeat => {
                    // Update Spots (Data Source for Renderer Merge)
                    if (blueprintData.spots) {
                        const spot = blueprintData.spots.find(s => String(s.id) === String(initialSeat.id));
                        if (spot) {
                            spot.state = SeatStates.SELECTED_BY_ME;
                        }
                    }
                    
                    // Update Objects (Direct Renderer Targets)
                    if (blueprintData.objects) {
                        const match = blueprintData.objects.find(obj => String(obj.id) === String(initialSeat.id));
                        if (match) {
                            match.state = SeatStates.SELECTED_BY_ME;
                        }
                    }
                });
            }

            // --- Render ---
            this.renderer = new BlueprintRenderer(content);
            this.renderer.render(blueprintData, (obj) => this.handleSeatClick(obj, session));
            
        } catch (e) {
            console.error(e);
            const errorMessage = document.createElement('div');
            errorMessage.className = 'blueprint-error';
            errorMessage.textContent = `${CommonStrings.error}: ${e.message}`;
            content.replaceChildren(errorMessage);
            import('../ui/toast.js').then(({ Toast }) => {
                new Toast(e.message, 'error').show();
            });
        }
    }

    async handleSeatClick(obj, session) {
        // --- Fix: Prevent Double Click / Race Conditions ---
        if (obj.processing) {
            return;
        }
        // STRICTER CHECK: Only allow interaction with AVAILABLE or SELECTED_BY_ME
        if (obj.state !== SeatStates.AVAILABLE && obj.state !== SeatStates.SELECTED_BY_ME) {
            return;
        }

        obj.processing = true; // Lock

        try {
            const isSelecting = (obj.state !== SeatStates.SELECTED_BY_ME);
            const oldState = obj.state;
            const newState = isSelecting ? SeatStates.SELECTED_BY_ME : SeatStates.AVAILABLE; 
            
            // Update Local State (Optimistic)
            obj.state = newState;
            
            if (isSelecting) {
                this.selectedSeats.push(obj);
            } else {
                this.selectedSeats = this.selectedSeats.filter(s => s.id !== obj.id);
            }

            this.renderer.updateSeat(obj); 
            
            // API Call via Session
            // Note: If this is the FIRST click, it might establish the secret.
            // Rapid second clicks are now blocked by 'obj.processing'.
            await session.toggleSpot(obj, isSelecting);
        } catch (e) {
            console.error("Spot selection failed", e);
            // Revert State
            // We need to fetch 'oldState' logic properly or just invert current logic
            // But we have 'oldState' var.
            // obj.state is now dirty.
            
            // Re-calculate toggle intent based on what we TRIED to do.
            const attemptsSelect = (obj.state === SeatStates.SELECTED_BY_ME);
            
            // Revert
            obj.state = attemptsSelect ? SeatStates.AVAILABLE : SeatStates.SELECTED_BY_ME;
             if (!attemptsSelect) {
                this.selectedSeats.push(obj);
            } else {
                this.selectedSeats = this.selectedSeats.filter(s => s.id !== obj.id);
            }
            this.renderer.updateSeat(obj);
            
            import('../ui/toast.js').then(({ Toast }) => {
                new Toast(e.message, 'error').show();
            });
        } finally {
            obj.processing = false; // Unlock
        }
    }
}
