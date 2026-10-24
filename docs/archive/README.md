# Documentation archive

This directory retains decision rationale, completed plans, superseded procedures
and dated evidence. It is historical reference, not the installation or release
path. Current instructions start at [the documentation map](../README.md).

- `plans/`: original designs, execution prompts and release receipts, including
  the completed backend switch, email gateway replacement, Material 3 adoption,
  product price scheduling and ticket product-field migration.
- `operations/supabase-self-hosted/`: the original backend consolidation,
  rehearsals, tenant-readiness snapshots, freeze/merge sequence and deletion
  inventory. The production switch completed on 2026-09-10; old NO-GO statuses
  describe the preparation phase. Retained resources and later cleanup have
  their own [closed operational records](../operations/work-items/completed/README.md).
- `operations/`: historical client-sync implementation evidence.
- `audits/`: branch-consolidation evidence.
- `setup/`: superseded bank receiving/SNS guides. Current ownership is in
  [BankSync setup](../setup/bank_import.md) and [outbound SES](../setup/aws_ses.md).

Recorded versions, counts and live checks apply only to their date and scope.
Archiving does not prove an unverified gate passed or a retained resource was
removed. Do not execute an archived prompt, replay an applied migration or treat
historical authorization as permission for a new rollout.
