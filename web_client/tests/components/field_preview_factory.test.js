
import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert';
import { FieldPreviewFactory } from '../../src/components/forms/previews/field_preview_factory.js';
import { LocalizationService } from '../../src/services/localization_service.js';

describe('FieldPreviewFactory', () => {

    describe('Default Strategy', () => {
        it('should return raw value if no options', () => {
             const field = { type: 'text', title: 'Name' };
             const result = FieldPreviewFactory.format(field, 'John', {});
             assert.strictEqual(result.value, 'John');
        });

        it('should resolve option title', () => {
            const field = { 
                type: 'select', 
                options: [
                    { id: 'opt1', title: 'Option 1' },
                    { id: 'opt2', title: 'Option 2' }
                ]
            };
            const result = FieldPreviewFactory.format(field, 'opt1', {});
            assert.strictEqual(result.value, 'Option 1');
            assert.strictEqual(result.price, null);
        });

        it('should append price to title if context has currency', () => {
            const field = { 
                type: 'select', 
                options: [
                    { id: 'opt1', title: 'Premium', price: 100 }
                ]
            };
            const result = FieldPreviewFactory.format(field, 'opt1', { currency: 'CZK' });
            assert.strictEqual(result.value, 'Premium');
            // formatPrice uses NBSP usually, let's match loose or copy NBSP
            // 100\u00A0Kč
            assert.match(result.price, /100.*Kč/);
        });

        it('should handle multi-select (joined strings)', () => {
            const field = { 
                type: 'select_many', 
                options: [
                    { id: 'a', title: 'A' },
                    { id: 'b', title: 'B' }
                ]
            };
            // FormDataReader joins with ' | '
            const result = FieldPreviewFactory.format(field, 'a | b', {});
            assert.strictEqual(result.value, 'A, B');
        });
    });

    describe('Product Type Strategy', () => {
        it('should resolve product title from nested product_type_data', () => {
            const field = { 
                type: 'product_type', 
                data: {
                    product_type_data: {
                        products: [
                            { id: 'p1', title: 'Shirt', price: 200 }
                        ]
                    }
                }
            };
            const result = FieldPreviewFactory.format(field, 'p1', { currency: 'CZK' });
            assert.strictEqual(result.value, 'Shirt');
            assert.match(result.price, /200.*Kč/);
        });
    });

    describe('ID Document Strategy', () => {
        it('should format simple ID number string (Legacy/Simple)', () => {
            const field = { type: 'id_document' };
            const result = FieldPreviewFactory.format(field, '12345', {});
            assert.strictEqual(result.value, '12345');
        });

        it('should format nested object with Number and Expiry', () => {
            const field = { type: 'id_document' };
            const val = {
                id_document_number: '987654',
                id_document_expiry_date: '2028-06-25T00:00:00.000'
            };
            
            // Default locale is 'cs' in AppConfig, usually.
            // But we can force locale for test if we mocked LocalizationService better.
            // Currently LocalizationService.currentLocale is static property.
            LocalizationService.currentLocale = 'cs';
            
            const result = FieldPreviewFactory.format(field, val, {});
            
            // Enforce CS format: d. m. yyyy -> 25. 6. 2028
            // Note: Intl.DateTimeFormat might behave slightly differently on different Node versions/locales installed
            // But usually '25. 6. 2028' or '25.6.2028'
            
            // To be safe against minor space differences in Intl:
            assert.ok(result.value.includes('987654'));
            assert.ok(result.value.includes('2028'));
            assert.ok(result.value.includes('6.')); 
            
            // Verify structure "Number (Date)"
            // 987654 (25. 6. 2028)
            const regex = /^987654 \(\d{1,2}\. ?\d{1,2}\. ?2028\)$/;
            assert.match(result.value, regex);
        });

        it('should switch format based on locale', () => {
            const field = { type: 'id_document' };
            const val = {
                id_document_number: 'ABC',
                id_document_expiry_date: '2028-12-31T00:00:00.000'
            };
            
            LocalizationService.currentLocale = 'en';
            const result = FieldPreviewFactory.format(field, val, {});
            
            // US Format: 12/31/2028
            assert.ok(result.value.includes('ABC'));
            assert.match(result.value, /12\/31\/2028/);
        });

        it('should handle missing expiry gracefully', () => {
            const field = { type: 'id_document' };
            const val = {
                id_document_number: 'ONLY_ID'
            };
            const result = FieldPreviewFactory.format(field, val, {});
            assert.strictEqual(result.value, 'ONLY_ID');
        });
    });

});
