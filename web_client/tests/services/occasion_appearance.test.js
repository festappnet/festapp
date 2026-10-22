import test from 'node:test';
import assert from 'node:assert/strict';
import { JSDOM } from 'jsdom';
import { ThemeService } from '../../src/services/theme_service.js';
import { FormModel } from '../../src/components/forms/form_models.js';

test('saved shared appearance reaches real public form theme and clears on another form', () => {
    const dom = new JSDOM('<!doctype html><head></head><body></body>', {url:'http://localhost/'});
    globalThis.window=dom.window; globalThis.document=dom.window.document;
    const form = new FormModel({data:{design:{primary_color:'#14284B',secondary_color:'#A87F28',background_mode:'gradient',font_family:'Roboto Slab'}}});
    ThemeService.applyThemeFromModel(form);
    assert.match(document.body.style.background,/linear-gradient/);
    assert.match(document.body.style.getPropertyValue('--font-family-base'),/Roboto Slab/);
    ThemeService.applyThemeFromModel(new FormModel({data:{}}));
    assert.doesNotMatch(document.body.style.background,/linear-gradient/);
});
