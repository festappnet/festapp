/* Source distributed directly. WordPress provides dependencies; no build. */
(function (blocks, element, editor, components, i18n) {
    'use strict';
    const el = element.createElement;
    const __ = i18n.__;
    blocks.registerBlockType('vstupenky-online/ticket-form', {
        edit: function (props) {
            const a = props.attributes;
            // Advisory only. PHP validates the exact origin and canonical path.
            const origins = window.vstupenkyOnlineEditor.origins;
            const plausible = origins.some((origin) => a.url.startsWith(origin + '/form/') && /^(?:[A-Za-z0-9_-]|%[A-F0-9]{2})+$/.test(a.url.slice(origin.length + 6)));
            return el('div', editor.useBlockProps({className: 'vstupenky-online-editor'}),
                el('h3', null, 'vstupenky.online'),
                el('p', null, __('Paste the saved public form URL. Manage orders in vstupenky.online.', 'vstupenky-online')),
                el('p', null, el('a', {href: 'https://vstupenky.online/login', target: '_blank', rel: 'noopener noreferrer'}, __('Create an account or sign in', 'vstupenky-online'))),
                el(components.TextControl, {label: __('Form URL', 'vstupenky-online'), value: a.url, type: 'url',
                    placeholder: 'https://vstupenky.online/form/saved-slug',
                    onChange: (url) => props.setAttributes({url}),
                    help: __('Use https://vstupenky.online/form/saved-slug without query parameters or personal fragments.', 'vstupenky-online')}),
                a.url && !plausible ? el(components.Notice, {status: 'warning', isDismissible: false}, __('Check the public URL. The server accepts only an allowed form address.', 'vstupenky-online')) : null,
                el(components.TextControl, {label: __('Form title', 'vstupenky-online'), value: a.title, onChange: (title) => props.setAttributes({title}),
                    help: __('Describe this form for visitors using screen readers. This does not rename the event.', 'vstupenky-online')}),
                el(components.SelectControl, {label: __('Form height', 'vstupenky-online'), value: a.mode,
                    options: [{label: __('Automatic', 'vstupenky-online'), value: 'auto'}, {label: __('Fixed', 'vstupenky-online'), value: 'fixed'}], onChange: (mode) => props.setAttributes({mode})}),
                el(components.ToggleControl, {label: __('Use the WordPress theme instead of the app appearance', 'vstupenky-online'), checked: a.inheritStyle, onChange: (inheritStyle) => props.setAttributes({inheritStyle}),
                    help: a.inheritStyle
                        ? __('Overrides the app font, background and colors for this block only. The form in the app and the seating map keep their appearance.', 'vstupenky-online')
                        : __('Uses the appearance configured in the app.', 'vstupenky-online')}),
                el(components.RangeControl, {label: a.mode === 'fixed' ? __('Height (px)', 'vstupenky-online') : __('Fallback height without the helper (px)', 'vstupenky-online'), value: a.height, min: 240, max: 4000, step: 10, onChange: (height) => props.setAttributes({height})}),
                el('p', null, __('After publication, visitors connect to vstupenky.online and enter data directly into the service. Automatic height loads its /embed.js. The remote form is not loaded in the editor.', 'vstupenky-online')),
                el('p', null, el('a', {href: 'https://vstupenky.online/privacy/', target: '_blank', rel: 'noopener noreferrer'}, __('Service privacy policy', 'vstupenky-online')))
            );
        },
        save: function () { return null; }
    });
})(window.wp.blocks, window.wp.element, window.wp.blockEditor, window.wp.components, window.wp.i18n);
