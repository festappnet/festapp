# Jednička - co ověříme sami bez dalšího dopisování

Historický výzkum a návrh z 29. 10. 2026, začleněný 6. 11. 2026. Nejde o implementaci ani novou autorizaci realizace. Tehdejší záznamy o neodeslání jsou překonané [stavem potvrzeným vlastníkem 1. 11.](shoptet-partner-onboarding-2026-10-26.md): návrh byl odeslán, čeká se na odpověď a další podání se neposílá.

Aktuální architekturu vlastní [společný Commerce Connector](../architecture/commerce-connectors.md) a jeho [realizační plán](commerce-connectors-plan-2026-10-29.md). Shoptet je první adaptér; tento starší průzkum zůstává podkladem, nikoli druhou implementační autoritou.

29. 10. 2026. Zvolený směr: společná kapacita Festappu přes Shoptet shipping-request / digitální doručení. Veřejné čtení a lokální příprava jsou dokončené; chráněný backend nebyl testovaný, nic nebylo odesláno.

## Výsledek dalšího průzkumu

Nemusíme sedm technických bodů posílat jako sedm dotazů podpoře. Mají se přednostně změnit na ověřovací scénáře. Dokumentace a zdroj již část pokrývají; zbytek patří do vlastního oprávněného sandboxu. Chybějící výsledek testu se nesmí nahradit domněnkou o neveřejném backendu.

### Doloženo veřejnými podklady

- **Vazba checkoutu na nabídku:** oficiální dokumentace popisuje serverové porovnání verificationCode a kontrolu expirace. Ve veřejném `checkoutShared.js` je skutečně zápis kódu do checkout inputu a nastavení časovače expirace. Není to důkaz kontroly SKU/množství při změně košíku. [Kontrakt](https://developers.shoptet.com/shipping-addons/), [zdroj na pevné revizi](https://github.com/shoptet/templates-assets/blob/3c10e28c25994039b86c5efd4401fb090b4dda20/shared/js/libs/checkoutShared.js#L895).
- **Omezení nabízené dopravy:** produkt/variantu lze označit jako atypickou dopravu a pak se nabízejí jen metody označené pro atypické produkty. Navrhujeme označit vstupenky a jedinou odpovídající metodou učinit naše digitální doručení. Jde o kandidátní použití existujícího nastavení; přímé podvržení jiné metody backendem jsme nezkoušeli. [Produkty](https://podpora.shoptet.cz/produkty-zaklady/), [dopravy](https://podpora.shoptet.cz/dopravy/).
- **Zotavení ze ztraceného webhooku:** existuje GET shipping-request status vracející stav a orderCode. To umožňuje samostatné srovnání, ale veřejné schéma neuvádí revizi nabídky ani konečnost stavů při souběhu. [API](https://api.docs.shoptet.com/shoptet-api/openapi/shipping-requests/getshippingrequestforgettingorderstatus).
- **Finanční stav:** veřejné schéma detailu objednávky obsahuje paid a paymentTransactions. Vlastní test může porovnat reálné události a tyto hodnoty pro podporovanou platební metodu. Nevyžaduje to obecný dotaz na každé pole. [API](https://api.docs.shoptet.com/shoptet-api/openapi/orders/getorderdetail).

Zdrojový repozitář byl ověřen na commitu `3c10e28c25994039b86c5efd4401fb090b4dda20` z 27. 10. 2026. Git blob hashe čtyř stažených souborů odpovídají této revizi. [Důkaz](shoptet-direction-evidence-2026-10-29/frontend-contract.json).

### Důležité omezení nalezeného kódu

Funkce `setExternalShippingMethod` při browserové invalidaci mění zvolený popisek/stav. V této větvi nepředstavuje veřejný JS důkaz zrušení nabídky v serveru; původní verificationCode se tam explicitně nemaže. Proto „klikli jsme Zrušit“ ani klientský timeout není autoritativní revokace rezervace.

V prohlédnutých souborech nebyl doložen automatický backendový otisk všech položek nebo compare-and-swap revize nabídky. To není tvrzení, že ho Shoptet nemá. Kód checkoutu na klientovi takový důkaz ani nemůže poskytnout.

## Vlastní testy místo korespondence

Následující scénáře jsou připravené, ale nebyly provedené. Vyžadují vlastní výslovně určený testovací e-shop s aktivním shipping-addon kontraktem, přístupem API a testovacími platbami. Veřejné demo jiného provozovatele není naše testovací prostředí. Samotná běžná trial prodejna nemusí mít potřebná oprávnění.

| Scénář | Konkrétní průběh | Co musí být vidět |
| --- | --- | --- |
| S1. Základní nabídka | V sandboxu autorizovaně načíst košík, uložit krátkou nabídku a dokončit podporovaný checkout. | Server přiřadí nabídku ke konkrétnímu orderCode; stav se shodne s detailem objednávky. |
| S2. Jiná doprava | U vstupenkové položky zkusit běžnou jinou dopravu a také podvržený přímý submit. | Neplatná cesta je odmítnuta backendem, nikoli pouze skryta JS. |
| S3. Jiný obsah | Po platné nabídce změnit množství, SKU, variantu nebo měnu; původní kód nechat nezměněný. | Stará nabídka není použitelná pro jinou rezervaci. Pokud je, zastavit tuto podobu návrhu. |
| S4. Dvě záložky | Dvě okna stejného košíku, nabídka A a následně B; potom submit ze starého okna. | Výsledek odpovídá známé nabídce a její alokaci; staré okno nepřevezme jiná místa. |
| S5. Opožděné PUT | Zadržet odpověď staršího požadavku, nechat projít novější a následně vrátit starou odpověď. | Naše serverová serializace a stav nabídky nemohou ztratit krytí kapacity. Neznámý výsledek ponechá kapacitu blokovanou. |
| S6. Expirace | Submit s platností těsně před i po hranici; zvlášť vypnout browserový timer. | Rozhoduje backendová expirace. Klientské vypnutí timeru nákup neodemkne. |
| S7. Pozdní oznámení | Shoptet přijme objednávku těsně před expirací, náš webhook sink ji záměrně zadrží. | Stavový dotaz odhalí přijetí a naše rezervace mezitím nebyla uvolněna přímému prodeji. |
| S8. Zrušení a návrat | Změnit dopravu, vrátit původní, obnovit starou stránku a zkusit dřívější kód. | Určí se, zda cancelled je stav konkrétní nabídky, či znovupoužitelný stav košíku. Do té doby není cancelled samo povolením uvolnit. |
| S9. Smíšený košík | Vstupenka a fyzické zboží při nastavení atypické dopravy. | Buď smluvně a technicky správné doručení obou, nebo serverově vynucený samostatný nákup. Neřešit jen textovou hláškou. |
| S10. Úhrada a změny | Testovací platba, pending/failed, ruční příznak paid, storno a podporovaná refundace. | Konkrétní definice finančního faktu, právě jedna vstupenka a správné zneplatnění. |

Naše návrhová ochrana pro S4-S8: jedna zpracovávaná změna nabídky na externí košík, trvalá revize, neměnný snapshot, evidence každého nejistého externího výsledku. Starou alokaci nevracet jen proto, že požadavek doběhl pomalu, vypršel browserový čas nebo přišlo upozornění na zrušení. Pokud nelze prokázat, která nabídka ještě může být přijata, ponechat dotčenou kapacitu blokovanou a řešit srovnání. To zaručí konzervativní zacházení s kapacitou, nikoli samo o sobě plně funkční Shoptet checkout s proměnným košíkem.

Předpoklad sandboxu se ověří jeho skutečnou identitou a oprávněními. V této session takový ověřený přístup nemáme, takže nyní nepředkládáme fiktivní výsledky S1-S10. Vzdálené mutace ani případné placené kapacity nejsou součástí této přípravy.

## Kdy by bylo opravdu potřeba Shoptet kontaktovat

Dokumentace vyžaduje schválení speciálního shipping-addon typu API týmem. To lze připojit k jednomu standardnímu partnerskému onboardingu, až vlastník podání dovolí. Není důvod předem vést samostatnou korespondenci o každém testu.

Další cílený dotaz dává smysl až při konkrétním rozporu mezi dokumentací a naměřeným chováním nebo tam, kde potřebujeme stabilní závazek neveřejného kontraktu. Testem lze doložit pozorované chování konkrétní verze; nelze z několika úspěšných pokusů dokázat všechny možné souběhy ani slíbit budoucí kompatibilitu. Pro nejasné výsledky zůstává konzervativní blokace a nikoli automatické uvolnění.

## Rozhodnutí pro další práci

Jednička je zvolený směr. Q1-Q7 v rozhodovacím dokumentu jsou seznamem ověřovaných vlastností, ne frontou zpráv k odeslání. Přednost má dokumentace, veřejný zdroj a vlastní kontrolovaný sandbox. Neměníme směr automaticky na kvótu. Odesílání a podání zůstávají zakázané.
