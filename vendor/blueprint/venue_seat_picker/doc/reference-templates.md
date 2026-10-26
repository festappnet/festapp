# Approved editable venue templates

The recommended gallery contains Belvedere (110 seats), Lipoltice (186), Kino Brandýs (265), Lucerna (1066), a round-table ball (96), and a blank plan. Existing template IDs remain available through the full catalog.

These layouts reproduce public seating-plan proportions, not measured building surveys. Tables, attached chairs, rows, walls, pillars and labels are native editable objects. Belvedere preserves authored corner-chair positions; other table seating is automatic. Lipoltice includes the requested extra head chair at table 6. Lucerna preserves floor and balcony groups, table numbers and architectural details.

Public references:

- [Hotel Belvedere public seating sale](https://www.smsticket.cz/nakup/krok-1-mistenky/72429-bohemian-burlesque-festival-bohemian-queen-night-hotel-belvedere-praha)
- [Lipoltice ball hall plan](https://vcelariprelouc.webnode.cz/ples/planek-salu/)
- [Kino Brandýs venue hire](https://kinobrandys.cz/pronajem/)
- [Lucerna organizer plans](https://lucpra.com/pro-poradatele/planky)

`reference_geometry.dart` stores traced coordinates; `reference_templates.dart` constructs canonical schema-2 documents. Rectangular tables expose four optional `seating.edgeCounts` preferences (top, right, bottom, left). Color palettes are selectable independently of furniture materials and geometry.
