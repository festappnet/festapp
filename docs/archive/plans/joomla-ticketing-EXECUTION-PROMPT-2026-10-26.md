# Zadání pro budoucí goal: Joomla doplněk

Archivní zadání realizované 2026-10-26. Lokální balíčky a ověření jsou dokončeny.
Aktuální stav: [Joomla readiness](../../../integrations/joomla/READINESS.md).
Nepoužívat jako nové oprávnění k publikaci nebo produkčnímu nasazení.

Po výslovném spuštění uživatelem pracuj v `/Users/miakh/source/festapp`.
Přečti AGENTS.md, CLAUDE.md, docs/architecture/ai_context.md a celý autoritativní plán:

`docs/archive/plans/joomla-ticketing-plan-2026-10-26.md`

Cíl: vytvořit dvě samostatné Joomla distribuce vstupenky.online a Festapp Tickets
ze společného zdroje. Dodat reprodukovatelné instalační ZIPy, české a anglické
nastavení a onboarding, ověřit instalaci a publikaci v reálné izolované Joomle
a předat hashe, výsledky a návod. Checkout a embed protokol zůstávají ve stávající službě.

Před spuštěním přebrat případné uživatelovy úpravy rozsahu. Postupuj etapami
plánu; nepřidávej placeholdery, druhou implementaci nákupu ani spekulativní
kompatibilitu. Použij úsporný pracovní postup a cílené standard ověření
bezpečnosti adaptéru. Neopakuj průzkum a již platné testy nezměněných vstupů.
Pokud nové důkazy vyvrátí předpoklad plánu, nejprve oprav příslušnou část plánu.

Respektuj cizí rozpracované změny a limit jednoho Flutter tasku. Browser musí
být izolovaný a headless. Nepoužívej produkční data k syntetickým nákupům.
Nevytvářej subagenty ani nezávislý audit bez výslovného zadání.

Nedělej commit, push, produkční instalaci, deploy, odeslání do JED ani externí
komunikaci bez samostatného zadání. Goal ukonči jako dokončený až po splnění
všech jeho podmínek; katalogové schválení je oddělený externí krok.

Předej stručně odkazy na ZIPy, jejich SHA-256, ověřené CMS/PHP verze, výsledek
cílených kontrol a případný přesný blocker. Po dokončení aktualizuj readiness
a archivuj plán/prompt podle pravidel repozitáře.
