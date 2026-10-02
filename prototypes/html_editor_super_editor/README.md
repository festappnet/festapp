# Test Super Editoru a formátovaného vložení

Prototyp nyní po otevření ukazuje konkrétní obrázek Rufuse Millera dodaný uživatelem. Jeho lokální kopie je ve `web/imported_images/rufus-miller.jpeg`; při vykreslení i exportu se původní externí URL nahradí URL této kopie ze stejného originu. Tím se pro tuto ukázku odstraní CORS blokace. Jde o mapování tohoto konkrétního obrázku; ostatní externí URL se automaticky nestahují. Produkční cesta `fetch-http-data` vyžaduje přihlášení a occasionId, které samostatný prototyp nemá.

Spusť z tohoto adresáře `./run.sh`, otevři `http://127.0.0.1:8766`, klikni do levého panelu a vlož obsah z webové stránky pomocí Ctrl/Cmd+V. Pravý panel ukazuje přesné HTML vytvořené editorem. Vyzkoušej tučný text, nadpis, seznam, odkaz, barvu a tabulku a porovnej zdroj s výsledkem. Jiný port lze zvolit například `PORT=8770 ./run.sh`.

Použité bezplatné balíčky: `super_editor` 0.3.0-dev.52 a `super_editor_clipboard` 0.2.10. Tento experiment nemění editor ani ukládání ve Festappu.

**Ověřeno 30. 9. 2026 na macOS s FVM / Flutter 3.47.2:** `flutter pub get` uspěl, webový prototyp se zkompiloval a vykreslil v prohlížeči. Psaní do editoru aktualizuje HTML v pravém panelu. Předchozí chybu spojení s pub.dev se v této session nepodařilo reprodukovat; její původní příčina není doložená.

**Přímý test převodu HTML:** `fvm flutter test test/html_paste_test.dart` používá skutečné API `pasteHtml` a `toHtml` obou balíčků. Zachovává nadpis, tučný text, kurzívu (exportovanou jako `<i>`), odkaz a seznam. Barva textu se ztratí. Jednoduchá tabulka zůstane tabulkou, ale původní první řádek z `<td>` se změní na záhlaví `<th>` s centrováním. Původní odhad, že se tabulka úplně ztratí, byl nesprávný. Doplněk převádí HTML přes Markdown; test nezaručuje zachování složitějších tabulek nebo jejich stylů.

**Dosud neověřeno:** úspěšné formátované vložení z reálné schránky v Chrome. Automatizovaný test narazil na oprávnění pro čtení schránky a následně na neodpovídající izolovaný prohlížeč. Přímý test převodu neověřuje webovou cestu přes schránku. Prohlížeč použitý pro test byl ukončen.

**Oprava exportu obrázků:** obrázek ze schránky doplněk vloží jako `BitmapImageNode`, který výchozí HTML export tiše vynechává. Prototyp ho nyní exportuje jako `<img src="data:image/…;base64,…">` se skutečným formátem a původními bajty. Jde o lokální experiment; obrázek se nenahrává na server. Test `test/image_export_test.dart` ověřuje vložení bitmapy do dokumentu a její export i zachování textu a URL obrázku při vložení HTML. Samotný přístup webového prohlížeče ke schránce tím není ověřen.

**Vykreslení obrázků ve Flutteru:** vlastní komponenta editoru přebírá předchozí řešení z `lib/components/html/html_view.dart` (commit `d6b877680`): URL obrázky vykresluje přes `CachedNetworkImage` s `ImageRenderMethodForWeb.HttpGet`, data URI přes `Image.memory`. Test `test/image_render_test.dart` ověřuje tento výběr přímo v dokumentu Super Editoru. Externí URL stále potřebují povolené CORS, stejně jako v původním byte loaderu. Chyba síťového obrázku se zobrazí přímo v editoru.
