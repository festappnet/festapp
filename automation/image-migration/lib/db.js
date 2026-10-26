/**
 * PostgreSQL connection pool management.
 */

import pg from 'pg';

const { Pool } = pg;

/**
 * Create a PostgreSQL connection pool.
 *
 * @param {string} databaseUrl - PostgreSQL connection string
 * @returns {pg.Pool}
 */
export function createPool(databaseUrl) {
  return new Pool({
    connectionString: databaseUrl,
    max: 5,
  });
}

/**
 * Close the connection pool.
 *
 * @param {pg.Pool} pool
 */
export async function closePool(pool) {
  await pool.end();
}
