# Approved blueprint template selection - 2026-10-22

The user's exported checkbox selection is the authority for the creation catalogue. Both the setup picker and editor gallery offer these 15 plans in the same order:

1. Blank layout
2. Scout ball - original hall
3. Scout ball - hall with balcony
4. Bus
5. Double-decker bus
6. Two train carriages
7. Round-table ball (`studio-tables`, original archived composition)
8. Garden gala (`studio-gala`)
9. Lipoltice
10. Belvedere
11. Cinema rows (`auditorium`)
12. Galaxy cinema
13. Kino Brandys
14. Concert in the round (`studio-arena`)
15. Lucerna

The order starts with the empty canvas and both requested Scout halls, then groups transport, balls, cinema and large event layouts. Empty canvas is also the default for a new plan. Existing saved plans are unaffected by catalogue membership.

The three selected archived compositions come from the exact documents in the locally reviewed gallery. They were converted once through the canonical schema-1 import boundary and stored as schema-2 template data in the canonical package. Non-rendered legacy fill, stroke and material settings on text were omitted before conversion; authored text colors and geometry were retained. Creation uses the core clone operation to allocate fresh identities and remap all attachments. The revised round-table composition is replaced by the user's chosen original. No runtime fallback to the old schema is introduced.

The dependency is rebuilt from its canonical source and imported through the archive workflow; vendored snapshots are not edited directly. Targeted template tests and the actual pub/npm archive consumer, all-template scene and archived Flutter boot gates cover the updated distribution. Production rollout is limited to vstupenky.online.
