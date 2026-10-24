// wp-env 12 publishes on every interface by default. Intercept its generated
// compose object before Docker sees it, including transient/random DB ports.
const Module = require('node:module');
const fs = require('node:fs');
const path = require('node:path');
const pins = require('../docker-images.json');
const writeFile = fs.promises.writeFile;
fs.promises.writeFile = function (file, content, ...args) {
  if (String(file).endsWith('.Dockerfile') && typeof content === 'string') {
    content = content.replace(/^FROM (wordpress:[^\s]+)$/m, (_, tag) => {
      if (!pins[tag]) throw Error('Unpinned wp-env PHP image: ' + tag);
      return 'FROM ' + tag + '@' + pins[tag];
    });
  }
  return writeFile.call(this, file, content, ...args);
};
const original = Module._load;
Module._load = function (id, parent, main) {
  const result = original.apply(this, arguments);
  if (!id.endsWith('build-docker-compose-config')) return result;
  return function (...args) {
    const config = result(...args);
    for (const service of Object.values(config.services)) {
      if (service.image && pins[service.image]) service.image += '@' + pins[service.image];
      if (service.ports) service.ports = service.ports.map(port => {
        if (typeof port !== 'string') throw Error('Unexpected wp-env port mapping');
        return `127.0.0.1:${port}`;
      });
    }
    return config;
  };
};
