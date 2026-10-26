
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
  
  console.log('TextFieldBuilder tests passed!');
}

test().catch(err => {
    console.error(err);
    process.exit(1);
});
