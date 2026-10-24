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
                el(components.ToggleControl, {label: __('Match website style', 'festapp-tickets'), checked: a.inheritStyle, onChange: (inheritStyle) => props.setAttributes({inheritStyle}),
                    help: __('Use the website font family and colors. Seat map keeps its own appearance. Website fonts must allow loading from the service.', 'festapp-tickets')}),
                el(components.RangeControl, {label: a.mode === 'fixed' ? __('Height (px)', 'festapp-tickets') : __('Fallback height without the helper (px)', 'festapp-tickets'), value: a.height, min: 240, max: 4000, step: 10, onChange: (height) => props.setAttributes({height})}),
                el('p', null, __('After publication, visitors connect to Festapp Tickets and enter data directly into the service. Automatic height loads its /embed.js. The remote form is not loaded in the editor.', 'festapp-tickets')),
                el('p', null, el('a', {href: 'https://tickets.festapp.net/privacy/', target: '_blank', rel: 'noopener noreferrer'}, __('Service privacy policy', 'festapp-tickets')))
            );
        },
        save: function () { return null; }
    });
})(window.wp.blocks, window.wp.element, window.wp.blockEditor, window.wp.components, window.wp.i18n);
