import assert from 'node:assert/strict';
import test from 'node:test';

import {
    OccasionCardAction,
    resolveOccasionCardAction,
} from '../../src/components/occasion/occasion_card_action.js';

test('ticket-only tenants open form actions directly even when an occasion has a description', () => {
    assert.equal(resolveOccasionCardAction({
        hasFormFeature: true,
        isDescriptionEmpty: false,
        isAppSupported: false,
    }), OccasionCardAction.reserve);
});

test('app-backed tenants retain details for described occasions', () => {
    assert.equal(resolveOccasionCardAction({
        hasFormFeature: true,
        isDescriptionEmpty: false,
        isAppSupported: true,
    }), OccasionCardAction.details);
});

test('description-free forms remain direct and non-form occasions remain app links', () => {
    assert.equal(resolveOccasionCardAction({
        hasFormFeature: true,
        isDescriptionEmpty: true,
        isAppSupported: true,
    }), OccasionCardAction.reserve);
    assert.equal(resolveOccasionCardAction({
        hasFormFeature: false,
        isDescriptionEmpty: true,
        isAppSupported: false,
    }), OccasionCardAction.app);
});
