
import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert';
import { FormDataReader } from '../../src/components/forms/form_data_reader.js';
import { JSDOM } from 'jsdom';

// Setup global JSDOM
const dom = new JSDOM('<!DOCTYPE html><html><body><form id="test-form"></form></body></html>', {
    url: 'http://localhost/',
});

global.window = dom.window;
global.document = dom.window.document;
global.FormData = dom.window.FormData;
global.HTMLElement = dom.window.HTMLElement;

describe('FormDataReader', () => {
    let mockFormModel;
    let formElement;

    beforeEach(() => {
        document.body.innerHTML = '<form id="test-form"></form>';
        formElement = document.getElementById('test-form');

        mockFormModel = {
            key: 'test_form',
            secret: 'test_secret',
            visibleFields: [
                { id: '10', type: 'text', options: [] },
                { 
                    id: '99', 
                    type: 'ticket', 
                    subFields: [] 
                },
                { id: 'email_field', type: 'email' }
            ],
            relatedFields: [
                { id: '10', type: 'text' },
                { id: 'email_field', type: 'email' }
            ]
        };
    });

    it('should read standard fields correctly', () => {
        // Setup Field
        const input = document.createElement('input');
        input.name = '10';
        input.value = 'Hello World';
        formElement.appendChild(input);

        // Execute
        const fd = new FormData(formElement);
        const result = FormDataReader.getPayload(formElement, mockFormModel);

        // Verify
        assert.equal(result.fields.length, 1);
        assert.equal(result.fields[0]['10'], 'Hello World');
    });

    it('should hoist email field to top level', () => {
        // Setup Email Field
        const input = document.createElement('input');
        input.name = 'email_field';
        input.value = 'test@example.com';
        formElement.appendChild(input);

        // Execute
        const fd = new FormData(formElement);
        const result = FormDataReader.getPayload(formElement, mockFormModel);

        // Verify
        assert.equal(result.email, 'test@example.com');
    });

    it('should parse a single ticket with basic subfields', () => {
        // Define subfields
        mockFormModel.visibleFields[1].subFields = [
            { id: 'sub1', type: 'text' }
        ];

        // ticketId_index_subId
        // 99_0_sub1
        const input = document.createElement('input');
        input.name = '99_0_sub1';
        input.value = 'Guest Name';
        formElement.appendChild(input);

        const fd = new FormData(formElement);
        const result = FormDataReader.getTicketDataFromDom(formElement, mockFormModel);

        assert.ok(result);
        assert.equal(result.length, 1);
        assert.equal(result[0].fields.length, 1);
        assert.equal(result[0].fields[0]['text'], 'Guest Name');
    });

    it('should parse multiple tickets', () => {
        // Define subfields
        mockFormModel.visibleFields[1].subFields = [
            { id: 'sub1', type: 'text' }
        ];

        // Ticket 0
        const input0 = document.createElement('input');
        input0.name = '99_0_sub1';
        input0.value = 'Guest 1';
        formElement.appendChild(input0);

        // Ticket 1
        const input1 = document.createElement('input');
        input1.name = '99_1_sub1';
        input1.value = 'Guest 2';
        formElement.appendChild(input1);

        const fd = new FormData(formElement);
        const result = FormDataReader.getTicketDataFromDom(formElement, mockFormModel);

        assert.equal(result.length, 2);
        
        // Order shouldn't be strictly guaranteed by Object.keys, but usually is for integers
        // We find by value
        const t1 = result.find(t => t.fields[0]['text'] === 'Guest 1');
        const t2 = result.find(t => t.fields[0]['text'] === 'Guest 2');
        
        assert.ok(t1);
        assert.ok(t2);
        assert.notEqual(t1, t2);
    });

    it('should handle spot tickets with data-price and data-name', () => {
        mockFormModel.visibleFields[1].subFields = [
            { id: 'spot_sub', type: 'spot' }
        ];

        // 99_0_spot_sub
        const input = document.createElement('input');
        input.name = '99_0_spot_sub';
        input.value = '12345'; // Spot ID
        input.dataset.price = '500';
        input.dataset.name = 'A1';
        formElement.appendChild(input);

        const fd = new FormData(formElement);
        const result = FormDataReader.getTicketDataFromDom(formElement, mockFormModel);

        assert.equal(result.length, 1);
        assert.equal(result[0].spot, 12345);
        assert.equal(result[0].spotPrice, 500);
        assert.equal(result[0].spotName, 'A1');
    });

    it('should handle product_type fields with products array', () => {
         // Mock schema for product type
         const productData = {
             product_type_data: {
                 products: [
                     { id: 'p1', name: 'T-Shirt', price: 200, currency: 'CZK' },
                     { id: 'p2', name: 'Cap', price: 100, currency: 'CZK' }
                 ]
             }
         };

         mockFormModel.visibleFields[1].subFields = [
             { id: 'prod_sub', type: 'product_type', data: productData }
         ];

         // 99_0_prod_sub -> p1
         const input = document.createElement('input');
         input.name = '99_0_prod_sub';
         input.value = 'p1';
         formElement.appendChild(input);

         const fd = new FormData(formElement);
         const result = FormDataReader.getTicketDataFromDom(formElement, mockFormModel);

         assert.equal(result.length, 1);
         const field = result[0].fields[0];
         
         // Helper adds product_type property
         assert.equal(field['product_type'], 'p1');
         assert.equal(field['currency_code'], 'CZK');
    });

    it('should handle multiple products for the same subfield (checkbox list)', () => {
         const productData = {
             product_type_data: {
                 products: [
                     { id: 'p1', name: 'T-Shirt', price: 200 },
                     { id: 'p2', name: 'Cap', price: 100 }
                 ]
             }
         };

         mockFormModel.visibleFields[1].subFields = [
             { id: 'multi_prod', type: 'product_type', data: productData }
         ];

         // Simulate multiple FormData entries for same name (checkboxes)
         // JSDOM FormData reads form inputs. 
         // We need two inputs with same name.
         const input1 = document.createElement('input');
         input1.name = '99_0_multi_prod';
         input1.value = 'p1';
         formElement.appendChild(input1);

         const input2 = document.createElement('input');
         input2.name = '99_0_multi_prod';
         input2.value = 'p2';
         formElement.appendChild(input2);

         const fd = new FormData(formElement); 
         // Verify FormData construction
         assert.equal(fd.getAll('99_0_multi_prod').length, 2);

         const result = FormDataReader.getTicketDataFromDom(formElement, mockFormModel);
         
         assert.equal(result.length, 1);
         // Should have 2 field entries locally for product_type?
         // FormDataReader logic: "rawVals.forEach(v => ticketObj.fields.push(...) )"
         // So we expect 2 objects in fields array.
         assert.equal(result[0].fields.length, 2);
         
         const p1 = result[0].fields.find(f => f.product_type === 'p1');
         const p2 = result[0].fields.find(f => f.product_type === 'p2');
         
         assert.ok(p1);
         assert.ok(p2);
    });

    it('should skip tickets without data', () => {
        // 99_0_sub is empty
        mockFormModel.visibleFields[1].subFields = [{ id: 'sub1', type: 'text' }];
        
        const input = document.createElement('input');
        input.name = '99_0_sub1';
        input.value = ''; // empty
        formElement.appendChild(input);

        const fd = new FormData(formElement);
        const result = FormDataReader.getTicketDataFromDom(formElement, mockFormModel);

        assert.equal(result.length, 0);
    });
    it('should correctly structure id_document fields with nested number and expiry', () => {
        // Setup ID Document Field
        mockFormModel.relatedFields.push({ id: '583', type: 'id_document' });
        
        // Setup ID Input (Standard logic)
        const idInput = document.createElement('input');
        idInput.name = '583';
        idInput.value = '209729950';
        formElement.appendChild(idInput);

        // Setup Expiry Input (Web Client specific naming)
        const expiryInput = document.createElement('input');
        expiryInput.name = '583_expiry';
        expiryInput.value = '2028-06-28T00:00:00.000';
        formElement.appendChild(expiryInput);

        // Execute
        const result = FormDataReader.getPayload(formElement, mockFormModel);
        
        const fieldEntry = result.fields.find(f => f['583'] !== undefined);
        assert.ok(fieldEntry);
        
        assert.deepStrictEqual(fieldEntry['583'], {
             "id_document_number": "209729950",
             "id_document_expiry_date": "2028-06-28T00:00:00.000"
        });
    });
});
