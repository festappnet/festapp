# BankSync production activation - 2026-10-04

The user explicitly authorized production cutover and verification of actual paid order 6501 (CZK 1). Scope is festapptickets, canonical organization 3, with the shared BankSync service upgraded compatibly. Other Festapp tenant branches are excluded. Mendelio webhook-v2 work remains authorized separately; it must not block the requested Festapp payment cutover.

Preflight: vstupenky.online activation resolves tenant festapptickets, generation 1, canonical backend. The protected SSH hostname and runtime database match the installed target assertions; canonical organization 3 exists. Migration timestamp changed to 20261004193000 because current upstream already uses 20261004180000 for product price waves.

Operational evidence and final results will be appended after verification. No credentials or bank tokens belong in this document.
