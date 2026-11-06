// Registration uses opaque ink mass. Known gradient/translucent paths are
// checked per pixel instead: single-channel rounding can move their centroid.
// Bounds stay exact; every interior discrepancy must satisfy its local rule.
export function classifyRaster(row) {
  const bounds = m => [m.minX, m.minY, m.maxX, m.maxY];
  const sameHardInkBounds = JSON.stringify(bounds(row.masks[0])) === JSON.stringify(bounds(row.masks[1]));
  const centroidDeltaPhysicalPx = Math.hypot(...row.registrationInk.map(m => m.centroid).reduce((a, b) => a.map((v, i) => v - b[i])));
  const scopedFringe = row.otherInteriorDifferences === row.otherInteriorFringe && row.maxOtherChannelDelta <= 1;
  const scopedPaint = row.maxVariablePaintChannelDelta <= 1;
  const accounted = row.variablePaintInteriorDifferences + row.otherInteriorDifferences === row.interiorDifferences;
  return {name: row.name, sameHardInkBounds, centroidDeltaPhysicalPx, scopedFringe, scopedPaint,
    accounted, accepted: sameHardInkBounds && centroidDeltaPhysicalPx <= .5 && scopedFringe && scopedPaint && accounted && row.registrationInk.every(m => m.mass > 0)};
}
