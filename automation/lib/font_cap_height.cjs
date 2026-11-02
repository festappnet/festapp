// OpenType metrics belong to the configured face, never to a tenant name.
function fontCapHeightRatio(bytes) {
  if (bytes.length < 12) return null;
  const tables = new Map();
  const count = bytes.readUInt16BE(4);
  if (12 + count * 16 > bytes.length) return null;
  for (let index = 0; index < count; index++) {
    const entry = 12 + index * 16;
    const offset = bytes.readUInt32BE(entry + 8);
    const length = bytes.readUInt32BE(entry + 12);
    if (offset + length > bytes.length) return null;
    tables.set(bytes.toString('ascii', entry, entry + 4), {offset, length});
  }
  const head = tables.get('head');
  const os2 = tables.get('OS/2');
  if (!head || head.length < 20 || !os2 || os2.length < 90 ||
      bytes.readUInt16BE(os2.offset) < 2) return null;
  const units = bytes.readUInt16BE(head.offset + 18);
  const cap = bytes.readInt16BE(os2.offset + 88);
  return units > 0 && cap > 0 && cap <= 2 * units ? cap / units : null;
}

module.exports = {fontCapHeightRatio};
