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


test('solid ignores the retained second color and incomplete gradients use the primary color', t => {
    const dom = new JSDOM('<!doctype html><head></head><body></body>', {url:'http://localhost/'});
    const previous = {window: globalThis.window, document: globalThis.document};
    Object.assign(globalThis, {window:dom.window, document:dom.window.document});
    t.after(() => {Object.assign(globalThis, previous); dom.window.close();});
    const apply = design => ThemeService.applyThemeFromModel(new FormModel({data:{design}}));
    apply({primary_color:'#216445', secondary_color:'#146475', background_mode:'solid'});
    assert.equal(document.body.style.background, 'rgb(33, 100, 69)');
    apply({primary_color:'#216445', background_mode:'gradient'});
    assert.equal(document.body.style.background, 'linear-gradient(90deg, rgb(33, 100, 69), rgb(33, 100, 69))');
    apply({background_mode:'gradient'});
    assert.doesNotMatch(document.body.style.background, /linear-gradient/);
    assert.equal(document.body.dataset.sharedAppearance, undefined);
});
