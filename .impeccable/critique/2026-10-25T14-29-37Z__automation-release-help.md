---
target_identity: "file:/Users/miakh/source/festapp-public-help-20261024/automation/release/help"
timestamp: 2026-10-25T14-29-37Z
slug: automation-release-help
---
Method: dual-agent (A: /root/help_content_critic · B: /root/help_critique_evidence)

# Organizer help: content and context audit

Scope: all fifteen original task guides, the hub and eight categories in Czech
and English at 13c41b7; source/UX audit and independent browser/detector evidence.
The user requested corrections, concise copy and explicit working context.

## Assessment A before corrections

| Heuristic | Score / 4 | Finding |
| --- | --- | --- |
| System status | 3 | Payment, delivery and admission are separate states. |
| Real-world match | 3 | One misleading receiving-account instruction. |
| User control | 3 | Event chooser and normal permission boundaries. |
| Consistency | 2 | Mixed EN seating context and contradictory Form tabs. |
| Error prevention | 3 | Important irreversible actions explained. |
| Recognition | 3 | Context navigation and genuine screenshots. |
| Efficiency | 3 | Door-staff recovery mixed with organizer configuration. |
| Minimalism | 2 | Repeated defensive copy and capture narration. |
| Recovery | 3 | Recovery existed but was buried in scanner settings. |
| Documentation | 3 | Broad coverage with a few incorrect instructions. |
| Total | 28 / 40 | Pre-correction assessment only. |

## Corrected findings

1. P1: existing forms do not offer a receiving-account selector. They use the
   first supporting organizer account by currency and priority. Corrected both
   languages, banking metadata and account/event-settings cross-references.
2. P2: English seating now starts from an existing event and links separately
   to the setup wizard.
3. P2: Form controls fields and availability; Settings controls link/payments;
   Design controls appearance. Both language introductions now agree.
4. P2: WordPress block attributes are saved with the page. Changes to plugin
   functionality ship as plugin releases. Removed the contradictory wording.
5. P2: scanner organizer settings moved into a separate localized guide; the
   door-staff guide keeps operational scanning, results and recovery together.
6. P3: removed unrelated warnings, banking-password/identity contrasts and QA
   narration. Retained consequential cancellation, email and unsent-admission
   guidance at the action that requires it.
7. P2 evidence: shortened scanner captions and retained raw technical capture
   provenance in metadata. Body paragraphs now have a bounded reading measure.

Assessment A's focused readback confirmed the corrections and identified one
remaining payment-lead verb, also corrected. No post-fix numeric score is claimed.

## Independent assessment B

No observed horizontal overflow at 390px or 1280px. Scanner WCAG2A/AA check had
zero violations and one incomplete lazy-dialog aria-controls check. The Fio
player loaded with an accessible title and external fallback; playback was not
certified in this assessment. CLI reported 72 repeated shared stylesheet
findings (contrast/pulsing-dot/glow); rendered overlays did not reproduce those
claims, so they were not treated as real defects. Long wizard lines and scanner
QA captions were useful actionable evidence. Both isolated browsers were closed;
the user-requested HTTP preview server was preserved.

Questions skipped: user explicitly authorized correcting all identified issues.
