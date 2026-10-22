# Lokální screen inventory a hranice akcí

Návrhy: [screens.html](screens.html), responzivní grid, skutečné výchozí light/dark tokeny. Statický návrh není UI QA. Nevytváří vlastní platební workflow.

| Povrch | Existující vlastník | Data / akce |
|---|---|---|
| Unit / Platby kartou | unit settings, AppAlertDialog | obchodní název, charges a payouts zvlášť, checkedAt; správce unit start/pause/resume/replace/disconnect |
| Form editor | FormEditorDraft / EditorActionBar | configuredMethods a availableMethods + důvody, connection; Save/Discard |
| Preview | JS order_preview / Flutter order_preview_screen | cena, email, výběr metody před vytvořením, jedno command ID |
| Výsledek / přehled | JS order_result/order_overview; Flutter order_finish/customer_order_overview | orderState, paymentState, admissionState, deliveryState, serverNow, reservationExpiresAt, allowedActions |
| Admin detail | současné oprávnění editovat objednávku | hrubá platba, refundace, spor, timeline, poslední sync, audit konkrétních vstupenek |

`allowedActions` jsou serverové povolení, nikoli capability: read scope nikdy nevydá write bearer. Pro `order_view` jen read/refresh/contact; pro `order_pay` pouze start/resume téhož serverově uloženého pokusu. Handoff jednorázový, return krátkodobý a jen minimální read. Všechny bearer odkazy ve fragmentu, bez analytics a bez Stripe metadata.

Web: tentýž tab; iframe: explicitní odkaz na tenant handoff v novém tabu s noopener, bez změny embed protokolu. Native: systémový prohlížeč a HTTPS návrat, resume jen read. Finální routy závisejí na autoritativním connection flow; žádná generická callback URL z klienta. Dirty draft neopouští editor bez existujícího Save/Discard guardu.

Připojení zahrnuje pending, potřebné údaje, ready, payouts attention, paused, restricted, unavailable se stářím, revoked a denied. Výsledek zahrnuje preparing, pending, declined/cancel, paid + email pending/accepted/failed/suppressed, expired, late/action_required, refund pending/partial/full, dispute hold, offline a invalid link. Každý má jednu hlavní akci; nejistá platba nikdy nevede na nový nákup. Čas a polling neautorizují platbu; 2/3/5/10/10 s, pause při hidden a dispose listenerů.

Před pilotem zůstává výslovným produktovým předpokladem 31minutová rezervace a hold při sporu. Všechny Stripe přijímací cesty musí být online; bankovní offline režim zachovat. Neověřené native, iframe a CMS nejsou podporované povrchy.
