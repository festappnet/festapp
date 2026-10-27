# Zkušenosti z WordPress.org review

## 27. 10. 2026: Requires at least není přesná testovaná verze

WordPress.org vrátil verzi 1.0.0 kvůli `Requires at least: 6.6.4` v PHP hlavičce
a readme. Požaduje stabilní major release v jejich číslování, tedy `6.6`.
Přesná testovaná verze patří do důkazů, nikoliv do tohoto pole.

**Proč to kontrolami prošlo:** převzali jsme přesnou verzi minimální testovací
fixture jako katalogový údaj. Obě deklarace se shodovaly a plugin na fixture
fungoval. Naše seal kontrola dokazovala shodu ZIPu, zdrojů a důkazů, ale neměla
sémantickou kontrolu tohoto pole. Plugin Check 2.1.0 v našem skutečném běhu tuto
chybu neoznačil; PASS nástroje tedy není úplná kontrola pravidel katalogu.
Původní review nepodchytilo rozdíl mezi kompatibilitou runtime a formátem
katalogových metadat. Nešlo o závadu WordPressu ani běhu formuláře.

**Náprava:** 1.0.3 má v obou místech `6.6`, prošla čistou instalací/aktivací
a 39 reálnými kontrolami na WP 6.6/PHP 7.4.33. Opravený ZIP je nahraný ve stejné
žádosti, odpověď je ve stejném review vlákně. Historické podání 1.0.0 se nemění.

**Prevence:** generátor i kontrola zapečetěného ZIPu nyní používají stejný
`scripts/metadata_contract.py`: pole musí být právě jednou, mít tvar X.Y
a shodovat se mezi PHP a readme. `scripts/test_metadata_contract.py` zahrnuje
přesně odmítnutou hodnotu 6.6.4, chybějící/duplicitní pole a rozdílné verze.
Build kontrola běží pro každý vybraný produkt, ne pouze jako ruční checklist.

Před dalším podáním oddělit tři důkazy: funkční kompatibilitu na deklarovaném
minimu, sémantiku metadat a pravidla distribuce. Neoznačovat žádný jediný
automatický scanner za záruku přijetí katalogem.

Zdroj požadavku: review email `1a17ebf910d7b0d3`; [číslování WordPressu](https://make.wordpress.org/core/handbook/about/how-the-release-cycle-works/version-numbering/).
