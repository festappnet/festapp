# Product price grouping and occasion terminology

Decision: each product variant gets one outlined block, including its default selector. Name, stock count and actions form the header. Price and deposit/surcharge have separate adjacent fields with their own currencies on wide screens and stack on narrow or enlarged-text screens. Compared separator-only rows, grouped blocks and a table in a disposable prototype; grouped blocks provide the clearest ownership of an optional surcharge while preserving mobile editing. Prototype absorbed into production widgets.

The valid-ticket filter now follows the occasion's ticket feature, displaying “Platné přihlášky” when tickets are disabled.

Validation: 14 targeted Flutter tests passed (narrow/wide layout, both themes, surcharge editing without changing price/currency, terminology and existing form layout/editor checks). Application-theme light/dark captures inspected; temporary visual harness passed and was removed. No database or money calculation changes.
