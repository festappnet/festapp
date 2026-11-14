/** Public presentation data shared by email and web. Contains no signing configuration. */
export const walletPresentation = {
 google: {
  labels: {cs:'Přidat do Peněženky Google',sk:'Pridať do Peňaženky Google',en:'Add to Google Wallet',de:'Zu Google Wallet hinzufügen',pl:'Dodaj do Portfela Google',uk:'Додати в Google Гаманець'},
  widths: {cs:333.12,sk:394.56,en:271.68,de:339.84,pl:307.2,uk:325.44},
  badges: Object.fromEntries(['cs','sk','en','de','pl','uk'].map(locale=>[locale,`https://img.festapp.net/assets/google-wallet/v1/${locale}.png`])),
 },
 apple: {
  labels: {cs:'Přidat do Apple Peněženky',sk:'Pridať do Apple Wallet',en:'Add to Apple Wallet',de:'Zu Apple Wallet hinzufügen',pl:'Dodaj do Apple Wallet',uk:'Додати в Apple Wallet'},
  widths: {en:166},
  badges: {en:'https://img.festapp.net/assets/apple-wallet/v1/en.svg'},
 },
};
