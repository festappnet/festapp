import { z } from 'zod';
import { Operations } from './catalog.mjs';

/** Pure schema/catalog projection shared by MCP help and public API builds.
 * No backend, keys, session, renderer or filesystem operation is performed. */
export function catalogProjection(allowedOperations, orderSummaryOnly = false) {
    const operations = new Operations({ root: '/documentation-only', allowedOperations, orderSummaryOnly });
    operations.setWriteReady(true);
    return operations.catalog;
}
export const schemaProjection = (schema, io = 'input') =>
    z.toJSONSchema(schema, { target: 'draft-2020-12', io });
