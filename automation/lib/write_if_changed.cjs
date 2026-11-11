const fs = require('node:fs');
const path = require('node:path');
function writeFileSync(file, content, options) {
  const bytes = Buffer.isBuffer(content) ? content : Buffer.from(content, typeof options === 'string' ? options : options?.encoding || 'utf8');
  if (fs.existsSync(file) && fs.readFileSync(file).equals(bytes)) return;
  fs.writeFileSync(file, content, options);
}
function copyFileSync(source, destination) { writeFileSync(destination, fs.readFileSync(source)); }
function syncTree(source, destination) {
  fs.mkdirSync(destination, {recursive:true});
  const names = new Set(fs.readdirSync(source));
  for (const name of fs.readdirSync(destination)) if (!names.has(name)) fs.rmSync(path.join(destination,name),{recursive:true,force:true});
  for (const name of names) {
    const from=path.join(source,name), to=path.join(destination,name);
    if (fs.statSync(from).isDirectory()) syncTree(from,to);
    else copyFileSync(from,to);
  }
}
module.exports = {writeFileSync, copyFileSync, syncTree};
