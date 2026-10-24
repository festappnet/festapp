# Fair use - návrh policy v1

Stav 2026-10-16: implementované lokální výchozí hodnoty, dosud neaktivované v produkci. Autoritou je `database/functions/abuse/seeds.sql` a následné auditované revize policy, nikoli tento informační přehled. Organization označuje tenant, Unit pořadatele.

Běžné create/duplicate/finalize běží v existujícím RPC bez nové Edge Function, Deno invocation nebo HTTP požadavku. Kontrola oprávnění a replay předchází admission; doménový výsledek i čerpání se commitnou společně. Draft bootstrap má vlastní budget. Nové UUID, editor, Unit ani změna policy neobnovují již spotřebovaný actor budget. Smazání objektu neruší rolling spotřebu. Obsazenost se počítá podle skutečných zachovaných objektů včetně archivovaných akcí.

Časová pravidla používají serverový čas a konzervativní součet bucketů včetně celého krajního bucketu. Krátké okno může odmítat až o jeden bucket dříve, denní okno až o hodinu; nejde o reset o půlnoci ani povolené překročení capu. Denní kontrola čte nejvýše 25 hodinových bucketů na klíč. Pokusy o Auth/QR se commitují samostatným booleovským RPC i při zamítnutí. Neúspěšná business transakce vrací jen vlastní právě rozpracovanou rezervaci, nikoli minulou spotřebu.

## Rezerva a růst

Běžná pošta Unit má denní limit `min(10000, 500 + 3 * verified_orders)`; Organization současně omezuje běžnou poštu na 2000/den, takže větší pořadatel potřebuje doložený tenantový příděl. Evidence vyžaduje existující paid/sent objednávku s kladnou cenou a bankovními transakcemi s evidovanou identitou, jejichž čistý součet v měně objednávky pokrývá celou cenu. Návštěvy, nové účty, ruční změna stavu nebo nově vytvořené akce růst nepřidávají. Maintenance obslouží nejvýše 20 Unit za minutu; evidence se obnovuje po 5 minutách a po 15 minutách stáří se použije základ. Čte se malý cache řádek, nikoli historie při každém enqueue.

| Příklad | Doložené objednávky | Běžná pošta Unit/den | Dopad |
| --- | ---: | ---: | --- |
| Malá akce | 50 | 650 | Rezerva nad jednou informační zprávou každé objednávce |
| Střední akce | 500 | 2000 | Sdílí tenantových 2000 s dalšími Unit |
| Velká akce | 3000 | 9500 | Vyžaduje schválené tenantové navýšení; provider cap se nemění |

Jde o návrhové scénáře, nikoli naměřené provozní rozložení. Read-only produkční kontrola potvrdila 29 Unit u kontrolované Organization a nejvýše 4 uložené akce na Unit; navržených 50 uložených akcí na Unit má rezervu. Prodejní špičky a velké anonymní akce nejsou těmito agregáty kalibrované. Nové limity musí před aktivací projít provozním porovnáním a schválením. Sdílená Wi-Fi nezvyšuje proof limity; reset může při neprokázaném proxy řetězci konzervativně sdílet unknown-source budget.

## Pošta a přijaté závazky

Existuje jediná fronta a stávající provider gate. Běžný backlog má zvláštní početní i bajtový strop, Auth vlastní omezený backlog a recipient cooldown. Ověřený automatický intent placené objednávky se uloží jednou i při plné běžné frontě. Výjimka vychází ze skutečné paid objednávky nebo automatického potvrzení jejího storna, verze, příjemce a canonical dedupe; klientská priorita ani ruční resend ji nevytvoří. Nové objednávky mají vlastní rolling a outstanding stropy v existujícím order modelu. Snížení policy neruší zaplacené závazky. Provider pause, fencing a account/region strop platí i pro závazky.

V rámci priority se střídají Organization a Unit podle posledního claim; po maximálním čekání 3600 s se bulk posune do prioritní třídy. Tato hodnota je scheduling cíl, nikoli záruka doručení při výpadku či plném provider stropu. Produkční read-only snapshot: sdílený provider 50000/den, příděl Festapp 10000/den a 2/s, stávající rezerva dává efektivně 9000/den a 1.6/s. Nejde o nové přidělení ani globální kapacitu pro všechny aplikace.

## Zobrazení a změna limitů

Autorizovaný editor/manager čte svoji Unit a vlastní actor spotřebu přes `get_unit_abuse_policy_v1`; hlášky Flutter/JS vysvětlují dočasné omezení. Povinné admin UI nevzniká. Navýšení provádí operátor přes `set_abuse_policy_v1` s očekávanou revizí a důvodem. Unit override mění pouze Unit pravidla, Organization override pouze Unit/Organization pravidla. Platnost je nejvýše 90 dnů; cap, scope, okno, identita a algoritmus nejsou běžně přepsatelné. Vypršení vrací platný základ. Policy změna nemění usage klíče ani již spotřebované množství.

## Scénáře rezervy a další cesty

Jedna depozitní objednávka vytváří potvrzení a dvě plánované připomínky. Běžný recipient burst je proto 6 za minutu pro dva takové nákupy, současně 20 za den. Samostatná kontrola přímo před provider permit brání souběhu zpráv naplánovaných na stejnou chvíli. Auth má vlastní 1/min a 10/den, ověřené závazky 30/min a 120/den; všechny třídy sdílejí původní provider fence. Odklad vrací zprávu do téže fronty na vypočtený čas uvolnění, nepřidává send attempt a neobnovuje spotřebu. Již čekající zprávy přebírají svou ověřenou třídu bez opakovaného admission.

Scan Unit má 2000 operací/min proti odhadu 20 vstupních linek po jednom odbavení za sekundu (1200/min), s rezervou na čtení a ruční opravy. Nesprávné proofy mají oddělené source/global limity a autentizovaný oprávněný personál má obnovovací cestu. Bezpečnostní proof limity nerostou počtem útočných požadavků.

Push omezuje 50 zpráv Unit/den, 200 Organization/den, 500 globálně a 50 na actor. Target budget je 50000/100000/200000 požadovaných členů za den. Velká akce s 10000 členy může odeslat pět hromadných oznámení za den, malá s 500 členy vyčerpá dříve počet zpráv. Tyto modelové scénáře nejsou měřený provoz. Jedna osoba může mít více provider subscriptions a tagované publikum může zahrnovat anonymní zařízení; target budget není doklad fyzického počtu doručení nebo platebního capu providera. Provider retry nese UUID původního notification logu jako idempotency key, se stropem stáří 1 den.

Push dispatch je explicitní část RPC, nikoli INSERT trigger. Přímý REST zápis do notification logu je odebraný; vydané starší klienty je nutné při aktivaci převést na stejný command. Instalační SQL vytváří pouze updated_at triggery.

Nové kopie obrázků používají stejný upload Worker a SQL IO budget včetně kopií starých Storage URL. Privátní čtení nemá public-bucket fallback. Restrictive Storage policy zakazuje INSERT/UPDATE v public-files, images-temp a editor-files, včetně starých přímých API/copy požadavků. Historical public-files listing/delete vyžaduje skutečné image ownership. Samotný image metadata command má centrální actor/Unit/Organization rolling limity, 10000/100000 uložených záznamů a URL byte cap; přímý REST INSERT/UPDATE images je odebraný. Odmítnutí po R2 put kompenzuje Worker smazáním nového objektu a vrátí 429. Kumulativní kapacitu starých souborů nelze vydávat za změřenou ze samotného rolling upload budgetu. Public image cache miss omezuje native binding 5000/min na lokalitu, hit nemá SQL dependency; toto není globální billing cap.

## Přihlášení, privátní projekty a kapacita

Šestimístné heslo je trvalé a opakovaně použitelné. Přihlášení používá nativní Auth a společný SQL account budget 10/60 s a 30/900 s, nezávislý na doručení a změně hesla. Zamítnutí neodhlašuje aktivní relace. E-mailová expirace je deadline zprávy, nikoli hesla. Native PostgreSQL function hook není trigger.

Nové skutečně uložené bytes mají vedle rolling IO samostatný neexpirující allocation budget: Unit 2 GiB, Organization 20 GiB, global 100 GiB. Historické objects jsou pevný, dosud nezměřený baseline navíc. Konzervativní allocation se automaticky nevrací ani při failed put/delete/overwrite. Nejde o tvrzení změřené celkové R2 obsazenosti.

Read/presign/delete privátních objektů a scope uploadu používají společný projektový RPC podle importní provenance Organization. Zachovává editor sharing uvnitř projektu. DNS pinning byl ověřen na skutečném Edge Runtime v1.74.2, včetně TLS hostname rejection. Dokumenty a preview používají společné centrální vstupní, asset, výstupní a page limity.

## Úplný přehled 146 seed hodnot

Tabulka je odečtená z čisté lokální baseline; autoritou zůstává SQL policy. Cumulative pravidla neexpirují, rolling pravidla používají konzervativní buckety. Hard cap není samoobslužné navýšení.

| Pravidlo | Scope | Jednotka | Výchozí limit | Hard cap | Okno s | Bucket s |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| bank.operation.account.burst | recipient | operations | 5 | 20 | 60 | 60 |
| bank.operation.actor.day | actor | operations | 50 | 200 | 86400 | 3600 |
| bank.operation.global.day | global | operations | 1000 | 5000 | 86400 | 3600 |
| cleaning.note.bytes | actor | bytes | 4096 | 16384 | - | - |
| cleaning.report.actor | actor | operations | 5 | 10 | 900 | 300 |
| cleaning.report.bytes | actor | bytes | 65536 | 262144 | - | - |
| document.asset.bytes | global | bytes | 5242880 | 10485760 | - | - |
| document.input.bytes | global | bytes | 1048576 | 4194304 | - | - |
| document.output.bytes | global | bytes | 16777216 | 33554432 | - | - |
| document.output.pages | global | items | 20 | 100 | - | - |
| draft.create.actor.burst | actor | operations | 10 | 30 | 600 | 60 |
| draft.create.actor.day | actor | operations | 40 | 100 | 86400 | 3600 |
| draft.create.organization.day | organization | operations | 200 | 1000 | 86400 | 3600 |
| draft.payload.bytes | unit | bytes | 262144 | 262144 | - | - |
| draft.stored.organization | organization | items | 200 | 1000 | - | - |
| draft.stored.unit | unit | items | 20 | 100 | - | - |
| draft.work.actor.burst | actor | operations | 20 | 60 | 600 | 60 |
| email.actor.day | actor | operations | 2000 | 10000 | 86400 | 3600 |
| email.auth.backlog.organization | organization | items | 1000 | 10000 | - | - |
| email.auth.global.day | global | operations | 10000 | 50000 | 86400 | 3600 |
| email.auth.organization.day | organization | operations | 1000 | 10000 | 86400 | 3600 |
| email.auth.recipient.burst | recipient | operations | 1 | 2 | 60 | 60 |
| email.auth.recipient.day | recipient | operations | 10 | 20 | 86400 | 3600 |
| email.backlog.organization | organization | items | 5000 | 50000 | - | - |
| email.backlog.organization.bytes | organization | bytes | 134217728 | 1073741824 | - | - |
| email.backlog.unit | unit | items | 1000 | 10000 | - | - |
| email.backlog.unit.bytes | unit | bytes | 33554432 | 268435456 | - | - |
| email.bulk.max_wait.seconds | global | seconds | 3600 | 21600 | - | - |
| email.ordinary.organization.day | organization | operations | 2000 | 20000 | 86400 | 3600 |
| email.ordinary.recipient.burst | recipient | operations | 6 | 10 | 60 | 60 |
| email.ordinary.recipient.day | recipient | operations | 20 | 40 | 86400 | 3600 |
| email.ordinary.unit.day | unit | operations | 500 | 10000 | 86400 | 3600 |
| email.payload.bytes | global | bytes | 16777216 | 33554432 | - | - |
| email.prepare.organization.burst | organization | operations | 60 | 300 | 60 | 60 |
| email.prepare.recipient.burst | recipient | operations | 3 | 6 | 60 | 60 |
| email.send.auth.recipient.burst | recipient | operations | 1 | 2 | 60 | 60 |
| email.send.auth.recipient.day | recipient | operations | 10 | 20 | 86400 | 3600 |
| email.send.commitment.recipient.burst | recipient | operations | 30 | 60 | 60 | 60 |
| email.send.commitment.recipient.day | recipient | operations | 120 | 500 | 86400 | 3600 |
| email.send.ordinary.recipient.burst | recipient | operations | 6 | 10 | 60 | 60 |
| email.send.ordinary.recipient.day | recipient | operations | 20 | 40 | 86400 | 3600 |
| google.attempt | recipient | operations | 10 | 10 | 60 | 60 |
| google.client | recipient | operations | 30 | 100 | 60 | 60 |
| google.global | recipient | operations | 100 | 300 | 60 | 60 |
| google.proof | recipient | operations | 5 | 5 | 60 | 60 |
| google.source | recipient | operations | 20 | 40 | 60 | 60 |
| hold.acquire.organization.burst | organization | operations | 5000 | 30000 | 60 | 60 |
| hold.acquire.unit.burst | unit | operations | 1000 | 10000 | 60 | 60 |
| hold.active.buyer | recipient | items | 20 | 20 | - | - |
| hold.duration.seconds | unit | seconds | 900 | 900 | - | - |
| image.fetch.actor.burst | actor | operations | 30 | 100 | 600 | 60 |
| image.fetch.actor.day | actor | operations | 200 | 1000 | 86400 | 3600 |
| image.fetch.organization.day | organization | operations | 5000 | 20000 | 86400 | 3600 |
| image.fetch.payload.bytes | actor | bytes | 10485760 | 10485760 | - | - |
| image.fetch.unit.day | unit | operations | 1000 | 5000 | 86400 | 3600 |
| image.records.actor.burst | actor | operations | 60 | 200 | 600 | 60 |
| image.records.actor.day | actor | operations | 500 | 2000 | 86400 | 3600 |
| image.records.link.bytes | actor | bytes | 2048 | 8192 | - | - |
| image.records.organization.burst | organization | operations | 600 | 2000 | 600 | 60 |
| image.records.organization.day | organization | operations | 10000 | 50000 | 86400 | 3600 |
| image.records.stored.organization | organization | items | 100000 | 1000000 | - | - |
| image.records.stored.unit | unit | items | 10000 | 100000 | - | - |
| image.records.unit.burst | unit | operations | 120 | 500 | 600 | 60 |
| image.records.unit.day | unit | operations | 2000 | 10000 | 86400 | 3600 |
| image.storage.global.bytes | global | bytes | 107374182400 | 500000000000 | - | - |
| image.storage.organization.bytes | organization | bytes | 21474836480 | 107374182400 | - | - |
| image.storage.unit.bytes | unit | bytes | 2147483648 | 21474836480 | - | - |
| image.upload.actor.burst | actor | operations | 30 | 100 | 600 | 60 |
| image.upload.actor.bytes | actor | bytes | 268435456 | 1073741824 | 86400 | 3600 |
| image.upload.organization.bytes | organization | bytes | 10737418240 | 42949672960 | 86400 | 3600 |
| image.upload.unit.burst | unit | operations | 60 | 200 | 600 | 60 |
| image.upload.unit.bytes | unit | bytes | 1073741824 | 4294967296 | 86400 | 3600 |
| monitor.auth.age.seconds | global | seconds | 60 | 300 | - | - |
| monitor.cleanup.age.seconds | global | seconds | 300 | 1800 | - | - |
| monitor.commitment.age.seconds | global | seconds | 300 | 1800 | - | - |
| monitor.growth.age.seconds | global | seconds | 900 | 3600 | - | - |
| monitor.ordinary.age.seconds | global | seconds | 3600 | 21600 | - | - |
| monitor.provider.quota.age.seconds | global | seconds | 3600 | 21600 | - | - |
| occasion.copy.bytes | unit | bytes | 33554432 | 134217728 | - | - |
| occasion.copy.items | unit | items | 30000 | 100000 | - | - |
| occasion.create.actor.burst | actor | operations | 5 | 20 | 600 | 60 |
| occasion.create.actor.day | actor | operations | 20 | 100 | 86400 | 3600 |
| occasion.create.organization.burst | organization | operations | 40 | 200 | 600 | 60 |
| occasion.create.organization.day | organization | operations | 200 | 1000 | 86400 | 3600 |
| occasion.create.unit.burst | unit | operations | 10 | 40 | 600 | 60 |
| occasion.create.unit.day | unit | operations | 40 | 200 | 86400 | 3600 |
| occasion.stored.organization | organization | items | 1000 | 10000 | - | - |
| occasion.stored.unit | unit | items | 50 | 2000 | - | - |
| order.create.organization.day | organization | operations | 10000 | 100000 | 86400 | 3600 |
| order.create.unit.day | unit | operations | 2000 | 20000 | 86400 | 3600 |
| order.mutation.actor.burst | actor | operations | 60 | 300 | 60 | 60 |
| order.mutation.items | unit | items | 2000 | 10000 | - | - |
| order.mutation.organization.burst | organization | operations | 2000 | 10000 | 60 | 60 |
| order.mutation.unit.burst | unit | operations | 600 | 3000 | 60 | 60 |
| order.outstanding.organization | organization | items | 20000 | 100000 | - | - |
| order.outstanding.unit | unit | items | 5000 | 20000 | - | - |
| organization.create.global.day | global | operations | 5 | 20 | 86400 | 3600 |
| password.change.account.window | recipient | operations | 3 | 10 | 900 | 60 |
| password.change.actor.burst | actor | operations | 30 | 100 | 60 | 60 |
| password.change.payload.bytes | actor | bytes | 1024 | 4096 | - | - |
| password.verify.actor.burst | actor | operations | 10 | 20 | 60 | 60 |
| password.verify.actor.window | actor | operations | 30 | 60 | 900 | 60 |
| push.calls.actor.day | actor | operations | 50 | 200 | 86400 | 3600 |
| push.calls.global.day | global | operations | 500 | 2000 | 86400 | 3600 |
| push.calls.organization.day | organization | operations | 200 | 1000 | 86400 | 3600 |
| push.calls.unit.day | unit | operations | 50 | 200 | 86400 | 3600 |
| push.delivery.age.seconds | unit | seconds | 86400 | 172800 | - | - |
| push.delivery.targets | unit | items | 10000 | 20000 | - | - |
| push.dispatch.global.burst | global | operations | 300 | 1000 | 60 | 60 |
| push.dispatch.unit.burst | unit | operations | 30 | 100 | 60 | 60 |
| push.payload.bytes | unit | bytes | 16384 | 65536 | - | - |
| push.targets.global.day | global | operations | 200000 | 1000000 | 86400 | 3600 |
| push.targets.organization.day | organization | operations | 100000 | 500000 | 86400 | 3600 |
| push.targets.unit.day | unit | operations | 50000 | 200000 | 86400 | 3600 |
| qr.exchange.global.burst | global | operations | 600 | 1200 | 60 | 60 |
| qr.exchange.proof.burst | recipient | operations | 30 | 30 | 60 | 60 |
| qr.payload.bytes | global | bytes | 1024 | 4096 | - | - |
| reception.cancel.actor | actor | operations | 30 | 60 | 60 | 60 |
| reception.create.actor | actor | operations | 20 | 40 | 60 | 60 |
| reception.issue.actor | actor | operations | 30 | 60 | 60 | 60 |
| reception.revoke.actor | actor | operations | 30 | 60 | 60 | 60 |
| reset.account | recipient | operations | 3 | 3 | 900 | 300 |
| reset.global | global | operations | 300 | 600 | 60 | 60 |
| reset.source | recipient | operations | 20 | 40 | 900 | 300 |
| scan.export.bytes | unit | bytes | 33554432 | 67108864 | - | - |
| scan.export.items | unit | items | 30000 | 100000 | - | - |
| scan.invalid.global.burst | global | operations | 600 | 3000 | 60 | 60 |
| scan.invalid.source.burst | recipient | operations | 30 | 60 | 60 | 60 |
| scan.operation.organization.burst | organization | operations | 10000 | 30000 | 60 | 60 |
| scan.operation.unit.burst | unit | operations | 2000 | 10000 | 60 | 60 |
| scan.password.account | recipient | operations | 3 | 3 | 900 | 300 |
| scan.password.unit.burst | unit | operations | 30 | 60 | 60 | 60 |
| sync.snapshot.bytes | global | bytes | 4194304 | 16777216 | - | - |
| sync.snapshot.items | global | items | 1000 | 5000 | - | - |
| sync.work.source.burst | actor | operations | 10 | 30 | 600 | 60 |
| ticket.document.actor.burst | actor | operations | 30 | 100 | 60 | 60 |
| ticket.document.actor.day | actor | operations | 500 | 2000 | 86400 | 3600 |
| ticket.document.organization.day | organization | operations | 10000 | 50000 | 86400 | 3600 |
| ticket.document.unit.day | unit | operations | 2000 | 10000 | 86400 | 3600 |
| ticket.preview.actor.burst | actor | operations | 20 | 60 | 60 | 60 |
| ticket.preview.organization.day | organization | operations | 5000 | 20000 | 86400 | 3600 |
| ticket.preview.payload.bytes | actor | bytes | 40000 | 40000 | - | - |
| ticket.preview.unit.day | unit | operations | 1000 | 5000 | 86400 | 3600 |
| unit.create.actor.day | actor | operations | 3 | 10 | 86400 | 3600 |
| unit.create.global.day | global | operations | 100 | 1000 | 86400 | 3600 |
| unit.create.organization.day | organization | operations | 30 | 200 | 86400 | 3600 |
