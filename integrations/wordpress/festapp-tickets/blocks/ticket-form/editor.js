/* Source distributed directly. WordPress provides dependencies; no build. */
(function (blocks, element, editor, components, i18n) {
    'use strict';
    const el = element.createElement;
    const __ = i18n.__;
    blocks.registerBlockType('festapp-tickets/ticket-form', {
        edit: function (props) {
            const a = props.attributes;
            // Advisory only. PHP validates the exact origin and canonical path.
            const origins = window.festappTicketsEditor.origins;
            const plausible = origins.some((origin) => a.url.startsWith(origin + '/form/') && /^(?:[A-Za-z0-9_-]|%[A-F0-9]{2})+$/.test(a.url.slice(origin.length + 6)));
            return el('div', editor.useBlockProps({className: 'festapp-tickets-editor'}),
                el('h3', null, 'Festapp Tickets'),
                el('p', null, __('Paste the saved public form URL. Manage orders in Festapp Tickets.', 'festapp-tickets')),
                el('p', null, el('a', {href: 'https://tickets.festapp.net/login', target: '_blank', rel: 'noopener noreferrer'}, __('Create an account or sign in', 'festapp-tickets'))),
                el(components.TextControl, {label: __('Form URL', 'festapp-tickets'), value: a.url, type: 'url',
                    placeholder: 'https://tickets.festapp.net/form/saved-slug',
                    onChange: (url) => props.setAttributes({url}),
                    help: __('Use https://tickets.festapp.net/form/saved-slug without query parameters or personal fragments.', 'festapp-tickets')}),
                a.url && !plausible ? el(components.Notice, {status: 'warning', isDismissible: false}, __('Check the public URL. The server accepts only an allowed form address.', 'festapp-tickets')) : null,
                el(components.TextControl, {label: __('Form title', 'festapp-tickets'), value: a.title, onChange: (title) => props.setAttributes({title}),
                    help: __('Describe this form for visitors using screen readers. This does not rename the event.', 'festapp-tickets')}),
                el(components.SelectControl, {label: __('Form height', 'festapp-tickets'), value: a.mode,
                    options: [{label: __('Automatic', 'festapp-tickets'), value: 'auto'}, {label: __('Fixed', 'festapp-tickets'), value: 'fixed'}], onChange: (mode) => props.setAttributes({mode})}),

                el(components.SelectControl, {label: __('Measurement destination', 'festapp-tickets'), value: a.measurement,
                    options: [{label: __('Festapp Unit runtime (existing behavior)', 'festapp-tickets'), value: 'unit'}, {label: __('Website dataLayer', 'festapp-tickets'), value: 'host'}],
                    onChange: (measurement) => props.setAttributes({measurement}),
                    help: __('Website mode is recommended for websites with their own GTM and consent banner. New embeds use Website mode. Existing content without a setting retains Unit mode. Unit mode reads website Consent Mode only after the organizer enables “Use consent from my website banner” in Festapp and confirms that the banner covers the embedded form. Website mode shares conversion contacts and transaction identifiers with page scripts. The website domain must be approved in Festapp.', 'festapp-tickets')}),
                el('p', null, __('Appearance is managed in the saved form. Open Forms, select this form, choose Design and save your changes.', 'festapp-tickets'), ' ', el('a', {href:'https://tickets.festapp.net/events?help=forms',target:'_blank',rel:'noopener noreferrer'}, __('Open forms', 'festapp-tickets'))),
                el(components.RangeControl, {label: a.mode === 'fixed' ? __('Height (px)', 'festapp-tickets') : __('Fallback height without the helper (px)', 'festapp-tickets'), value: a.height, min: 240, max: 4000, step: 10, onChange: (height) => props.setAttributes({height})}),
                el('p', null, __('After publication, visitors connect to Festapp Tickets and enter data directly into the service. Both height modes load its /embed.js. The remote form is not loaded in the editor.', 'festapp-tickets')),
                el('p', null, el('a', {href: 'https://tickets.festapp.net/privacy/', target: '_blank', rel: 'noopener noreferrer'}, __('Service privacy policy', 'festapp-tickets')))
            );
        },
        save: function () { return null; }
    });
    // Inserter defaults are explicit serialized attributes. Old blocks still
    // resolve the block.json default (unit), including when edited and saved.
    blocks.registerBlockVariation('festapp-tickets/ticket-form', {
        name: 'website', title: 'Festapp Tickets', isDefault: true,
        attributes: {measurement: 'host'}, scope: ['inserter'],
    });
})(window.wp.blocks, window.wp.element, window.wp.blockEditor, window.wp.components, window.wp.i18n);
