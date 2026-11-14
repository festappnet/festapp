/** Public presentation data shared by email and web. Contains no signing configuration. */
export const walletPresentation = {
 google: {
  labels: {cs:'Přidat do Peněženky Google',sk:'Pridať do Peňaženky Google',en:'Add to Google Wallet',de:'Zu Google Wallet hinzufügen',pl:'Dodaj do Portfela Google',uk:'Додати в Google Гаманець'},
  emailWidths: {"cs":205.09,"sk":205.09,"en":173.67,"de":173.67,"pl":185.89,"uk":198.11},
  emailBadges: Object.fromEntries(['cs','sk','en','de','pl','uk'].map(locale=>[locale,`https://img.festapp.net/assets/google-wallet/v1/condensed/${locale}.png`])),
  widths: {cs:333.12,sk:394.56,en:271.68,de:339.84,pl:307.2,uk:325.44},
  badges: Object.fromEntries(['cs','sk','en','de','pl','uk'].map(locale=>[locale,`https://img.festapp.net/assets/google-wallet/v1/${locale}.png`])),
 },
 apple: {
  labels: {cs:'Přidat do Apple Peněženky',sk:'Pridať do Apple Wallet',en:'Add to Apple Wallet',de:'Zu Apple Wallet hinzufügen',pl:'Dodaj do Apple Wallet',uk:'Додати в Apple Wallet'},
  handoff: {
   cs:'Pokud se otevřela Peněženka, potvrďte přidání. Pokud se soubor pouze stáhl, otevřete jej ve Stažených souborech. Pro přímé přidání můžete odkaz z e-mailu otevřít v Safari na iPhonu.',
   sk:'Ak sa otvorila Peňaženka, potvrďte pridanie. Ak sa súbor iba stiahol, otvorte ho v Stiahnutých súboroch. Na priame pridanie môžete odkaz z e-mailu otvoriť v Safari na iPhone.',
   en:'If Wallet opened, confirm there. If a file downloaded instead, open it from Downloads. You can also open the email link in Safari on your iPhone to add directly.',
   de:'Wenn sich die Wallet geöffnet hat, bestätigen Sie das Hinzufügen. Wurde stattdessen eine Datei heruntergeladen, öffnen Sie sie unter Downloads. Für direktes Hinzufügen öffnen Sie den E-Mail-Link in Safari auf Ihrem iPhone.',
   pl:'Jeśli otworzył się Portfel, potwierdź dodanie. Jeśli pobrał się plik, otwórz go w Pobranych. Aby dodać bezpośrednio, otwórz link z wiadomości w Safari na iPhonie.',
   uk:'Якщо відкрився Гаманець, підтвердьте додавання. Якщо натомість завантажився файл, відкрийте його в Завантаженнях. Для прямого додавання відкрийте посилання з листа в Safari на iPhone.',
  },
  widths: {en:151.80},
  badges: {en:'https://img.festapp.net/assets/apple-wallet/v1/en.svg'},
 },
};
