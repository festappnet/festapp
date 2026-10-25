import { RightsService } from '../services/rights_service.js';
import { RouterService } from '../services/router_service.js';
import { helpActionFromWebPath, helpActionFlutterPath } from '../services/help_action_routes.js';

// Authentication belongs to the same web modal used by UserHeader. Event
// selection and first-event setup remain owned by the administration boundary.
export async function handleHelpAction() {
    const intent = helpActionFromWebPath(window.location.pathname + window.location.search);
    if (!intent) return false;
    if (RightsService.currentUser?.id) {
        await RouterService.navigateToFlutterRoute(helpActionFlutterPath(intent));
        return 'navigated';
    }
    await import('../components/users/login_modal.js');
    if (!document.querySelector('login-modal')) document.body.appendChild(document.createElement('login-modal'));
    return 'catalog';
}
