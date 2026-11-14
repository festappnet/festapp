
import { TextFieldBuilder } from '../../src/components/forms/fields/text_field_builder.js';
import { FormStrings } from '../../src/components/forms/form_strings.js';
import { strict as assert } from 'assert';
import { JSDOM } from 'jsdom';

const dom = new JSDOM('<!DOCTYPE html><html><body></body></html>');
global.document = dom.window.document;
global.window = dom.window;
global.HTMLElement = dom.window.HTMLElement;

// Mock FormStrings since we can't easily load full LocalizationService in unit test without setup
// We hijack the getters to return predictable values for testing
Object.defineProperty(FormStrings, 'typeHere', {
    get: () => 'Formal Placeholder'
});
Object.defineProperty(FormStrings, 'typeHere_informal', {
    get: () => 'Informal Placeholder'
});

export default async function test() {
  const field = {
    id: 'test_field',
    type: 'text',
    title: 'Test Field',
    isRequired: false,
    isHidden: false
  };

  // Test Case 1: Formal (Default)
  {
    const formModel = { communicationTone: 'formal' };
    const element = TextFieldBuilder.create(field, formModel);
    const input = element.querySelector('input');
    
    assert.equal(input.placeholder, 'Formal Placeholder', 'Should use formal placeholder for formal tone');
  }

  // Test Case 2: Informal
  {
    const formModel = { communicationTone: 'informal' };
    const element = TextFieldBuilder.create(field, formModel);
    const input = element.querySelector('input');
    
    assert.equal(input.placeholder, 'Informal Placeholder', 'Should use informal placeholder for informal tone');
  }

  // Test Case 3: Undefined/Null Settings (Fallback to Formal)
  {
    const formModel = {}; // No settings
    const element = TextFieldBuilder.create(field, formModel);
    const input = element.querySelector('input');
    
    assert.equal(input.placeholder, 'Formal Placeholder', 'Should fallback to formal placeholder if settings are missing');
  }
  
  // Years keep numeric entry/validation without the browser's scroll-to-step control.
  {
    const element = TextFieldBuilder.create({
      ...field, type: 'birth_year', value: 2000, isRequired: true
    }, {});
    document.body.append(element);
    const input = element.querySelector('input');
    assert.equal(input.type, 'text');
    assert.equal(input.inputMode, 'numeric');
    assert.equal(input.autocomplete, 'bday-year');
    assert.equal(input.value, '2000');
    assert.equal(input.checkValidity(), true);
    input.focus();
    const wheel = new dom.window.WheelEvent('wheel', { bubbles: true, cancelable: true, deltaY: 100 });
    input.dispatchEvent(wheel);
    assert.equal(input.value, '2000');
    assert.equal(document.activeElement, input);
    assert.equal(wheel.defaultPrevented, false, 'Page scrolling must remain available');
    for (const invalid of ['', 'abc', '2000.5', '2e3', '-2000']) {
      input.value = invalid;
      assert.equal(input.checkValidity(), false, `Reject invalid year: ${invalid}`);
    }
    input.required = false;
    input.value = '';
    assert.equal(input.checkValidity(), true, 'An optional year can be empty');
    element.remove();
  }

  console.log('TextFieldBuilder tests passed!');
}

test().catch(err => {
    console.error(err);
    process.exit(1);
});
