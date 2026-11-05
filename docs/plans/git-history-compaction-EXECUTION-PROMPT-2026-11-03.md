# Completed: Festapp Git history compaction

The owner-authorized execution is complete and published. Read
`docs/plans/git-history-compaction-RESULT-2026-11-03.md` for the final receipt.
Do not rerun the old rewrite/publication scripts. Remote main is
`ccb42e2de4ef65a4900df23a8a4993d056c2e664` with 2,661 reachable commits.

Use `/Users/miakh/source/festapp-compacted-20261103` for clean current work.
The original checkout deliberately preserves pending work and old history;
never merge its old main/tags back into rewritten main or reset it implicitly.
External original recovery and all evidence live in
`/Users/miakh/festapp-history-compaction-20261103`.

All six automatic CI workflows succeeded. Main protections are restored.
No application deployment, production write, shared-workspace GC or unlisted
ref deletion occurred. Joomla's public tag/release/ZIP remains functional via
an identical-tree source snapshot. There is no pending publication approval.
