import { FormModel } from '../../../src/components/forms/form_models.js';
import { FormSession } from '../../../src/components/forms/form_session.js';
import { FormRenderer } from '../../../src/components/forms/form_renderer.js';
import { FormDataLayer } from '../../../src/components/forms/form_datalayer.js';

// The bridge is a local consent/transport stub; renderer, session and event projection are real.
const policy = {enabled:true, organization_allowed:true, runtime_supported:true, eligible:true, valid_for_seconds:60};
let layer;
window.resetFixture = ({consent = true, restored = false} = {}) => {
    layer?.dispose();
    document.querySelectorAll('input.flatpickr-input').forEach(input => input._flatpickr?.destroy());
    const fields = [
        {id: 1, type: 'email'},
        {id: 5, type: 'birth_date'},
        {id: 2, type: 'ticket', data: {max_tickets: 4}},
        {id: 3, type: 'name', is_ticket_field: true},
        {id: 4, type: 'select_one', is_ticket_field: true, data: {default_value: 'One', options: [{id: 1, value: 'One'}, {id: 2, value: 'Two'}]}},
    ];
    const model = new FormModel({fields, analytics: policy});
    model.data.analytics = policy;
    const session = new FormSession(model);
    if (restored) {
        session.addTicket({fields: [{_subFieldId: 3, name: 'Restored'}]});
        session.addTicket({fields: [{_subFieldId: 3, name: 'Second'}]});
    }
    window.sent = [];
    window.allowed = consent;
    const bridge = {measurementAllowed: () => window.allowed === true,
        track: payload => { window.sent.push(payload); return true; }, revokeMeasurement: () => {}};
    layer = new FormDataLayer({model, bridge, entryAllowed: true, session: () => false});
    FormRenderer.render(document.querySelector('main'), session, model, false, {
        onInput: (event, form) => session.handleInput(event, form),
        onInteraction: ((currentLayer) => () => currentLayer.started())(layer),
    });
};
window.resetFixture();
window.fixtureReady = true;
