# Unicode properties for Edge workers

Vendored from the MIT-licensed `unicode-properties` 2.0.1 package. The property
tables, trie and lookup functions are unchanged. Its upstream browser loader
embeds the exact same trie bytes instead of calling `fs.readFileSync`, which
production Supabase Edge workers block. Importing the npm package chooses the
Node loader in that runtime, even though host Deno tests choose another loader.

Regenerate with `python3 automation/vendor_layout_unicode.py /path/to/unicode-properties/2.0.1`.
The generator checks the version and recorded upstream hashes. Keep the data,
loader and license together in the Function bundle. Runtime verification must
exercise the real preview handler's cold `layout-text` request without enabling
`useReadSyncFileAPI` or replacing the trie loader in a test bundle.
