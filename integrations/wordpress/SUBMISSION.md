# vstupenky.online - podklady pro WordPress.org

Aktuální rozsah je pouze **vstupenky.online 1.0.0**, účet vydavatele
**festappnet**, kontakt **info@festapp.net**. Festapp Tickets se nyní nepodává
ani se neaktualizuje jeho ZIP nebo SVN návrh.

## Současný stav: podání blokuje produkční služba

SaaS integrace je přípustná, pokud služba poskytuje podstatné funkce a závislost
je jasně popsaná. Platí také výjimka pro dokumentovaný servisní JavaScript.
Viz [pravidla 6-8](https://developer.wordpress.org/plugins/wordpress-org/detailed-plugin-guidelines/)
a [externí služby](https://developer.wordpress.org/plugins/wordpress-org/common-issues/).
To není záruka přijetí konkrétního pluginu.

Produkční `https://vstupenky.online/embed.js` při kontrole 2026-10-24 stále
obsahoval starší helper (3009 bytes), bez přebírání fontů, hostitelského cenového
přehledu a nových scroll snapshotů. Před podáním musí být nasazen a přes skutečný
cross-origin embed ověřen odpovídající klient i helper.

Opravy služby nelze nasadit prostým buildem tohoto pracovního stromu.
Feature větev obsahuje další rozpracovanou práci a její formuláře/router se
liší od aktuálního `origin/main`. Je třeba připravit izolovanou integraci,
zachovat novější kanonické změny, ověřit ji a provést běžný release pouze pro
vstupenky.online. Audit neprovedl produkční deploy ani externí zápis na WordPress.org.

## Konkrétní balíček a povinná kontrola před podáním

- ZIP: `dist/vstupenky-online-1.0.0.zip`.
- Offline SVN: `dist/wordpress-org-draft/`.
- Přesné hashe a otevřené brány: `dist/APPROVAL.json`.
- Kritik a výsledky: `evidence/publishability-review-20261024.json`.

Z tohoto adresáře:

```sh
pnpm run package --product vstupenky-online
python3 scripts/stage-submission.py --product vstupenky-online
python3 scripts/verify-submission.py --product vstupenky-online
python3 scripts/verify-submission.py --product vstupenky-online --submit-ready
```

První dva příkazy mění vstupy zapečetěného návrhu. Po změně aktualizujte skutečné
výsledky a seal, nikoli jen hashe. Poslední příkaz musí před odesláním projít;
dokud jsou produkční brány otevřené, záměrně selže.

## Po splnění produkčních bran

Ověřit aktuální stav žádostí na [stránce pro přidání pluginu](https://wordpress.org/plugins/developers/add/),
přihlášení správným účtem a pravidla podání. Odeslat jen vybraný zapečetěný ZIP
v rámci vlastníkem autorizovaného podání. WordPress.org obvykle dovoluje jednu
čekající žádost; [FAQ](https://developer.wordpress.org/plugins/wordpress-org/plugin-developer-faq/)
odmítá obcházení více účty a pouhé duplicitní pluginy. Globální varianta není
součástí tohoto návrhu.

Podání k review není veřejné vydání. Po přijetí ověřit skutečně přidělený slug
a SVN repozitář, připravit diff a v autorizovaném veřejném vydání publikovat
ověřené trunk/tag/assets. Nakonec ověřit instalaci z katalogu a veřejnou stránku.
Schválení, rezervaci slugu ani datum vydání nelze předem slíbit.
