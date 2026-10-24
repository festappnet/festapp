# Aktualizace priorit Festapp - 17. 10. 2026

Podklad: čerstvý fetch origin/main `8b1420ea1da7349db68b4a293bb37da049fb9047`. Původní lokální HEAD `eb2304724` není aktuální main. Jiné rozpracované soubory nebyly upraveny.

## Doporučené nejbližší priority

1. Dokončit samoobslužnou cestu pořadatele od existující ukázky po první vlastní zveřejněnou akci a objednávku. Wizard zůstává záměrně skrytý (`a48b56c89`).
2. Jeden konkrétní scénář podmíněných produktů; obecná kapacita a náhradníci už nejsou nový projekt.
3. Vymezit a dokončit pozvání týmu do Unit a správné role.
4. Reprezentativní peak, bezpečný kapacitní budget a úplné RTO/cutover podle novějšího serverového plánu.
5. Využít veřejný web a ověřit malý akviziční pilot Plesuj. Samostatný worktree existuje; jeho stav nebyl auditován.

## Doložené změny

- Kapacita a náhradníci: `280c70281`, `5a7175d6b`, navazující opravy 13.-14. října.
- Přehled objednávky a platby, emailový odkaz, obnova stavu, PDF: `ff51ab12b`, `a73206948`, `e18bf7e2f`, `9e8f388b8`.
- Čitelné veřejné odkazy s historií: `55b1fa5ce` / PR #430.
- Storno read-only: `f65331349` / PR #363.
- Volba produktového typu na vstupence: aktuální ticket_layout README a evidence produkčního product-type cutoveru.
- Demo akce: `72df298ab`, `3f3350bde` a `docs/plans/demo-occasions-evidence-2026-10-14/README.md` na main.
- Veřejný web/SEO: `7939b3910`, `9ea1398d4`, release evidence z 15. října.
- Bezpečnost a obnova: `9b2064fb7`, `64b00a8a1`, `3177a4dc3`; staré P0 RPC/RLS nálezy byly napraveny. Zbývá kapacitní budget, úplné RTO a 50 původních chybějících obrazových referencí. Návrhový rozdíl 530 MB není měření souběžného OOM.

## Rozsah a jistota

Hotovo na main znamená doloženou implementaci. Produkční dokončení uvádíme jen tam, kde existuje novější release/readback evidence; dnes se produkce samostatně nekontrolovala. Výchozí pohled skrývá dokončené karty. Neoznačené položky nebyly automaticky prohlášeny za vyřešené. Zbývající původní seznam není úplný nový audit všech funkcí.

Autoritativní stav každého uvedeného souboru lze číst z [ověřeného main](https://github.com/festappnet/festapp/tree/8b1420ea1da7349db68b4a293bb37da049fb9047/docs). Lokální stejnojmenné plány mohou obsahovat starší stav. Priority vyjadřují úsudek bez nových konverzních a obchodních dat. Nebyly provedeny změny aplikace ani nasazení.
