export * from 'node:fs/promises';
import * as fs from 'node:fs/promises';
import {readFile, writeFile} from './migration_inputs.mjs';
export {readFile, writeFile};
export default {...fs, readFile, writeFile};
