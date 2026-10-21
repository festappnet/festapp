// Retire the historical bulk writer on the canonical mutation target. Metadata
// is readable without granting the legacy CLI access to private policy rows.
export async function assertLegacyUrlRewriteAllowed(pool, {dryRun = false} = {}) {
  if (dryRun) return;
  const {rows} = await pool.query("SELECT to_regclass('public.canonical_mutation_write_release_gate') IS NOT NULL AS canonical_mutations");
  if (rows.length !== 1 || rows[0].canonical_mutations !== false) {
    throw new Error('Legacy URL rewrite is disabled on the canonical mutation target; use its typed commands or a separately approved data repair.');
  }
}
