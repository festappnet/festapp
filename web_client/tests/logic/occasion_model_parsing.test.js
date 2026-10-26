
import { test } from 'node:test';
import assert from 'node:assert';
import { OccasionModel } from '../../src/components/occasion/occasion_model.js';
import { FeatureService } from '../../src/components/features/feature_service.js';

test('OccasionModel: Parsing Logic', async (t) => {

    await t.test('should merge flat properties into data object (Native/Sync Compat)', () => {
        const input = {
            id: 1,
            title: "Test Event",
            features: [
                {
                    code: "form",
                    is_enabled: true,
                    // FLAT PROPERTIES (The Problem Case)
                    use_external_form: true,
                    external_form_link: "https://example.com"
                }
            ]
        };

        const model = new OccasionModel(input);
        const formFeature = model.features.find(f => f.code === 'form');

        assert.ok(formFeature, "Form feature should exist");
        assert.ok(formFeature.data, "Data object should be created");
        
        // CRITICAL CHECK: Flat properties must be reachable via .data
        assert.strictEqual(formFeature.data.use_external_form, true);
        assert.strictEqual(formFeature.data.external_form_link, "https://example.com");
    });

    await t.test('should preserve existing data properties (Standard Nested)', () => {
        const input = {
            features: [
                {
                    code: "form",
                    is_enabled: true,
                    // NESTED PROPERTIES (The Standard Case)
                    data: {
                        use_external_form: false,
                        some_other_config: 123
                    }
                }
            ]
        };

        const model = new OccasionModel(input);
        const formFeature = model.features.find(f => f.code === 'form');

        assert.strictEqual(formFeature.data.use_external_form, false);
        assert.strictEqual(formFeature.data.some_other_config, 123);
    });

    await t.test('FeatureService should retrieve merged data', () => {
        const input = {
            features: [
                {
                    code: "form",
                    is_enabled: true,
                    use_external_form: true // Flat
                }
            ]
        };

        const model = new OccasionModel(input);
        
        // Simulate Dialog Usage
        const featureDetails = FeatureService.getFeatureDetails('form', model.features);
        
        // FeatureService.getFeatureDetails returns feature.data directly
        assert.ok(featureDetails, "Should return data object");
        assert.strictEqual(featureDetails.use_external_form, true, "Should access merged flat property");
    });

    await t.test('should handle missing features gracefully', () => {
        const model = new OccasionModel({});
        assert.deepStrictEqual(model.features, []);
        
        const details = FeatureService.getFeatureDetails('form', model.features);
        assert.strictEqual(details, null);
    });
});
