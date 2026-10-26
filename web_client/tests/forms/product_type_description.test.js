import { describe, it } from 'node:test';
import assert from 'node:assert';
import { JSDOM } from 'jsdom';

const dom = new JSDOM('<!DOCTYPE html><html><body></body></html>', {
    url: 'http://localhost/',
});
global.window = dom.window;
global.document = dom.window.document;
global.HTMLElement = dom.window.HTMLElement;
global.Event = dom.window.Event;

const { FormModel } = await import('../../src/components/forms/form_models.js');
const { TicketFieldBuilder } = await import('../../src/components/forms/fields/ticket_field_builder.js');

describe('Product type description', () => {
    it('renders the product type description below its form-field title', () => {
        const formModel = new FormModel({
            fields: [
                {
                    id: 10,
                    title: 'Tickets',
                    type: 'ticket',
                    order: 0,
                    data: {},
                },
                {
                    id: 11,
                    title: 'Platby, zálohy:',
                    type: 'product_type',
                    is_ticket_field: true,
                    order: 1,
                    data: {},
                    product_type_data: {
                        id: 12,
                        title: 'Záloha',
                        description: 'Cena se skládá ze zálohy a hotovosti placené na místě.',
                        products: [
                            {
                                id: 13,
                                title: 'Záloha v Kč',
                                price: 1000,
                                currency_code: 'CZK',
                                data: {},
                            },
                        ],
                    },
                },
            ],
        });

        const ticketField = formModel.relatedFields.find(field => field.type === 'ticket');
        const rendered = TicketFieldBuilder.create(ticketField, formModel, null);

        assert.strictEqual(
            rendered.querySelector('.form-field-label')?.textContent,
            'Platby, zálohy:'
        );
        assert.strictEqual(
            rendered.querySelector('.form-field-description')?.textContent,
            'Cena se skládá ze zálohy a hotovosti placené na místě.'
        );
    });
});
