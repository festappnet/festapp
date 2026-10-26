import { createPublisher } from './runtime.js';

const count = await createPublisher().runOnce();
process.stdout.write(`published_scopes=${count}\n`);
