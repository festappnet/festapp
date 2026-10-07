# Compact products and read-only defaults

PR #332 preserves compact rows when the deposit feature is disabled. Grouped cards remain for deposit/surcharge editing. Default-product radio and checkbox indicators are disabled; stored values remain visible, and the obsolete click-to-select hint is removed.

Eleven targeted Flutter tests passed, including both selector types, unchanged stored values after clicks, compact field alignment, surcharge layouts and editor regressions.

Released 0.20.131+615, tenant commit abadb4acadef7f51f24ab3a18c026ed2608db706. Canonical tenant drift passed. Deploy workflow succeeded with coherent public-version verification: https://github.com/festappnet/festapp/actions/runs/37514417696

Previous in-turn releases completed: shared copy control 0.20.129+613 (37511992925), product grouping/application terminology 0.20.130+614 (37513072047). Ticketing template visibility migration was independently deployed and verified in the canonical backend; no additional backend change in this release.
