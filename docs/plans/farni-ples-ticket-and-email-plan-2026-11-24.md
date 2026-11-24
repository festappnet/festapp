# Farní ples 2027 - vstupenky a e-maily

Rozsah je vstupenky.online a čtyři hlášení Petra Pražáka. Změny mají projít běžným editorem, náhledem a vykreslováním bez úprav zákaznických objednávek.

1. **Platební QR v náhledu.** Ověřit živý build a běžící `send-custom-email` proti opravě 6694608582. Náhled má zobrazit obrázek z kanonického QR rendereru při zapnutém QR v těle e-mailu. Ověření použije syntetický náhled bez odeslání.
2. **Uložení grafiky.** Prověřit verzi, uložený layout a vazby kopie Farní ples 2027 na živém backendu jen pro čtení. Uložený layout 3 již prošel validací a obrázek je v povoleném rozsahu. Reprodukovat konkrétní chybu na přechodu z editoru přes versioned save do databáze, prověřit konflikty souběžných změn a uložení galerie i vlastního pozadí. Opravu ověřit regresí v prokázané vrstvě.
3. **Cena.** Použít pravidlo formátování podle měny v existujících prezentačních modulech. Na vstupence zobrazit celé CZK bez desetinných míst, zejména `Cena: 0 Kč`. Prověřit PDF, náhled a případné použití ve Wallet. Účetní hodnoty a platební formáty ponechat přesné.
4. **Mobilní banner.** Najít šablonu použitou u zděděného banneru a vztah šířky obrázku k obalu. Upravit centrální vykreslování pro mobilní klienty včetně dříve uložených generovaných obalů. Ověřit symetrické okraje na mobilní šířce a rozložení na desktopu.

Použít standardní cílenou validaci a zdokumentovat, které varianty byly skutečně ověřeny. Produkční změny provádět pouze obvyklým release postupem s ověřením přesné verze a povinnými CI kontrolami.

## Výsledek ověření

- **QR.** Živá verze 0.20.652+1207 je postavená nad opravou 6694608582. Otisk běžícího `send-custom-email/authoringContext.ts` odpovídá zdroji opravy. Deno ověřilo obrázek PNG z autorizačního vstupu a Flutter jeho zobrazení v úzkém náhledu. Šlo o syntetické ověření.
- **Grafika.** Na akci i kopii jsou uložené layouty verze 3 bez osiřelých produktových vazeb. Produkční funkce jen pro čtení odmítla identifikátor grafiky Festival · malý plakát a prázdný řetězec, ale přijala NULL. Test v izolované databázi uložil grafiku galerie přes běžný versioned příkaz na kopii akce. Prázdné pozadí se převádí na NULL a cizí obrázek nadále vyžaduje vlastnictví v rozsahu akce nebo jednotky.
- **Cena.** Regresní test před opravou zobrazil `Cena: 0,00 Kč`. Po opravě serverový render i Flutter náhled zobrazují `Cena: 0 Kč`. Nenulové ceny v ostatních měnách na vstupenkách používají standardní počet desetinných míst. Nulová částka se zobrazuje bez desetinných míst ve sdílených formátovačích měn pro Flutter, web a Edge Functions. V nativních Wallet šablonách cena samostatné pole nemá.
- **Banner.** SQL test prokázal, že převod starého obalu dává shodný HTML výstup s novým generátorem a zachová vlastní i výslovně prázdné obaly. Flutter a izolovaný Chromium náhled ověřily symetrické okraje. Rozměry v Chromium byly ověřeny při 320, 400 a 800 px. Konkrétní mobilní poštovní klient nebyl ověřen.
- **Publikace.** Šest cílených databázových testů včetně porovnání účinných SQL funkcí se zdroji prošlo. Souhrnná kontrola historických migrací hlásí už na výchozí hlavní větvi zastaralé generované bloky v migracích pro přijímání transakčních e-mailů, počty objednávek a výchozí nastavení QR. Pracovní větev je v repozitáři s vypnutým pushem. Nová migrace a klientské změny jsou ověřené lokálně.

Vybraná produkční větev je `prod/festapptickets`. Připravená generace 0.20.653+1208 vyžaduje schválené sloučení a úspěšné kontroly přesného hlavního commitu.
