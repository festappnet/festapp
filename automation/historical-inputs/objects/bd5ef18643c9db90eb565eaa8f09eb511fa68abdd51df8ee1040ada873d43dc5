import {
  bold,
  generatePaymentDetails,
  styledParagraph,
  verticalSpacer,
  spaceBeforeText,
  spaceAfterText
} from './payment-details.helpers.ts';
import type { Tone } from './payment-details.helpers.ts';

export const csTranslations = {
  overpaid: (amount: string, tone: Tone) => [
      verticalSpacer(spaceBeforeText),
      styledParagraph(`Evidujeme na ní přeplatek ve výši ${bold(amount)}, který ${tone === 'formal' ? 'Vám' : 'Ti'} bude brzy vrácen.`),
      verticalSpacer(spaceAfterText),
  ].join(''),
  underpaid: (
    paid: string, remaining: string, accountNumber: string, iban: string | null, variableSymbol: string, deadline: string | null, tone: Tone
  ) => {
    const mainText = deadline
      ? `Pro úplné dokončení objednávky, prosíme, uhraďte zbývající částku ${bold(remaining)} do ${bold(deadline)}.`
      : `Pro úplné dokončení objednávky, prosíme, uhraďte zbývající částku ${bold(remaining)}. Platbu můžete provést online podle údajů níže (doporučeno) nebo v hotovosti na místě.`;

    const formalMainText = deadline
      ? `Pro úplné dokončení objednávky, prosíme, uhraďte zbývající částku ${bold(remaining)} do ${bold(deadline)}.`
      : `Pro úplné dokončení objednávky, prosíme, uhraďte zbývající částku ${bold(remaining)}. Platbu můžete provést online podle údajů níže (doporučeno) nebo v hotovosti na místě.`;

    const informalMainText = deadline
      ? `Pro úplné dokončení objednávky, prosíme, uhraď zbývající částku ${bold(remaining)} do ${bold(deadline)}.`
      : `Pro úplné dokončení objednávky, prosíme, uhraď zbývající částku ${bold(remaining)}. Platbu můžeš provést online podle údajů níže (doporučeno) nebo v hotovosti na místě.`;

    return [
      verticalSpacer(spaceBeforeText),
      styledParagraph(`Děkujeme za ${tone === 'formal' ? 'Vaši' : 'Tvou'} platbu ve výši ${bold(paid)}. ${tone === 'formal' ? formalMainText : informalMainText} Jakmile platbu obdržíme, pošleme ${tone === 'formal' ? 'Vám' : 'Ti'} potvrzení.`),
      verticalSpacer('15px'),
      styledParagraph(`Pro zjednodušení platby přikládáme QR kód.`),
      verticalSpacer(spaceAfterText),
      generatePaymentDetails({ accountNumber, iban, variableSymbol, amount: remaining, lang: 'cs' }),
    ].join('');
  },
  unpaid: (
    total: string, accountNumber: string, iban: string | null, variableSymbol: string, deadline: string | null, tone: Tone
  ) => {
    const formalMainText = deadline
      ? `Pro dokončení objednávky ji, prosíme, uhraďte do ${bold(deadline)}.`
      : `Pro dokončení objednávky, prosíme, proveďte platbu online podle údajů níže (doporučeno) nebo v hotovosti na místě.`;

    const informalMainText = deadline
      ? `Pro dokončení objednávky ji, prosíme, uhraď do ${bold(deadline)}.`
      : `Pro dokončení objednávky, prosíme, proveď platbu online podle údajů níže (doporučeno) nebo v hotovosti na místě.`;

    return [
      verticalSpacer(spaceBeforeText),
      styledParagraph(`Zbývá uhradit celkovou částku ${bold(total)}. ${tone === 'formal' ? formalMainText : informalMainText} Jakmile platbu obdržíme, pošleme ${tone === 'formal' ? 'Vám' : 'Ti'} potvrzení.`),
      verticalSpacer('15px'),
      styledParagraph(`Pro zjednodušení platby přikládáme QR kód.`),
      verticalSpacer(spaceAfterText),
      generatePaymentDetails({ accountNumber, iban, variableSymbol, amount: total, lang: 'cs' }),
    ].join('');
  },
  fullyPaid: (_tone: Tone) => [
      verticalSpacer(spaceBeforeText),
      styledParagraph("Je kompletně zaplacená. Děkujeme!"),
      verticalSpacer(spaceAfterText),
  ].join(''),
  zeroOrder: (currency: string, _tone: Tone) => [
      verticalSpacer(spaceBeforeText),
      styledParagraph(`Je v hodnotě ${bold(`0 ${currency}`)} a je považována za uhrazenou.`),
      verticalSpacer(spaceAfterText),
  ].join(''),
  reminder_before_deadline: (
    days: number, remaining: string, accountNumber: string, iban: string | null, variableSymbol: string, paid: string, tone: Tone
  ) => {
    const paidAmount = parseFloat(paid.replace(/[^0-9.,]+/g, "").replace(",", "."));
    const paragraphs = [
        styledParagraph(`Připomínáme ${tone === 'formal' ? 'Vám' : 'Ti'} blížící se termín splatnosti ${tone === 'formal' ? 'Vaší' : 'Tvé'} objednávky. Do splatnosti zbývá ${bold(`${days}&nbsp;${days === 1 ? "den" : days < 5 ? "dny" : "dní"}`)}.`)
    ];
    if (paidAmount > 0) {
      paragraphs.push(styledParagraph(`Již ${tone === 'formal' ? 'jste' : 'jsi'} uhradil/a částku ${bold(paid)}.`));
    }
    paragraphs.push(styledParagraph(`Zbývá uhradit částku ${bold(remaining)}.`));

    const textBlock = paragraphs.join('');

    return [
      verticalSpacer(spaceBeforeText),
      textBlock,
      verticalSpacer('15px'),
      styledParagraph(`Pro zjednodušení platby přikládáme QR kód. Jakmile ji obdržíme, pošleme ${tone === 'formal' ? 'Vám' : 'Ti'} potvrzení.`),
      verticalSpacer(spaceAfterText),
      generatePaymentDetails({ accountNumber, iban, variableSymbol, amount: remaining, lang: 'cs' }),
    ].join('');
  },
  reminder_after_deadline: (
    days: number, remaining: string, accountNumber: string, iban: string | null, variableSymbol: string, paid: string, tone: Tone
  ) => {
    const paidAmount = parseFloat(paid.replace(/[^0-9.,]+/g, "").replace(",", "."));
     const paragraphs = [
        styledParagraph(`Upozorňujeme ${tone === 'formal' ? 'Vás' : 'Tě'}, že ${tone === 'formal' ? 'Vaše' : 'Tvá'} objednávka je ${bold(`${days}&nbsp;${days === 1 ? "den" : days < 5 ? "dny" : "dní"}`)} po datu splatnosti.`)
    ];
    if (paidAmount > 0) {
      paragraphs.push(styledParagraph(`Již ${tone === 'formal' ? 'jste' : 'jsi'} uhradil/a částku ${bold(paid)}.`));
    }
    paragraphs.push(styledParagraph(`Zbývá uhradit částku ${bold(remaining)}.`));
    paragraphs.push(styledParagraph(`Prosíme o její co nejrychlejší uhrazení.`));

    const textBlock = paragraphs.join('');
    return [
      verticalSpacer(spaceBeforeText),
      textBlock,
      verticalSpacer('15px'),
      styledParagraph(`Pro zjednodušení platby přikládáme QR kód a jakmile ji obdržíme, pošleme ${tone === 'formal' ? 'Vám' : 'Ti'} potvrzení.`),
      verticalSpacer(spaceAfterText),
      generatePaymentDetails({ accountNumber, iban, variableSymbol, amount: remaining, lang: 'cs' }),
    ].join('');
  },
  days_remaining: (days: number) => {
    return `${days} ${days === 1 ? "den" : (days > 1 && days < 5) ? "dny" : "dní"}`;
  },
  depositRequired: (
    depositAmount: string,
    remainingAmount: string,
    depositDeadline: string,
    accountNumber: string,
    iban: string | null,
    variableSymbol: string,
    tone: Tone
  ) => {
    const isOnSite = depositDeadline === 'na místě' || depositDeadline === 'on site';
    const deadlineText = isOnSite
      ? `zbývající doplatek ve výši ${bold(remainingAmount)} ${tone === 'formal' ? 'uhradíte' : 'uhradíš'} na místě`
      : `zbývající doplatek ve výši ${bold(remainingAmount)} ${tone === 'formal' ? 'uhraďte' : 'uhraď'} nejpozději ${bold(depositDeadline)}`;

    return [
      verticalSpacer(spaceBeforeText),
      styledParagraph(`Pro zajištění místa ${tone === 'formal' ? 'uhraďte, prosíme, zálohu' : 'uhraď zálohu'} ve výši ${bold(depositAmount)}. Poté ${deadlineText}.`),
      verticalSpacer('15px'),
      styledParagraph(`Pro zjednodušení platby přikládáme QR kód.`),
      verticalSpacer(spaceAfterText),
      generatePaymentDetails({ accountNumber, iban, variableSymbol, amount: depositAmount, lang: 'cs' }),
    ].join('');
  },
  depositPaid: (
    depositAmount: string,
    remainingAmount: string,
    depositDeadline: string,
    tone: Tone
  ) => {
    const isOnSite = depositDeadline === 'na místě' || depositDeadline === 'on site';
    const deadlineText = isOnSite ? 'na místě' : `nejpozději ${bold(depositDeadline)}`;

    return [
      verticalSpacer(spaceBeforeText),
      styledParagraph(`Děkujeme za úhradu zálohy ve výši ${bold(depositAmount)}. Zbývající doplatek ve výši ${bold(remainingAmount)} ${tone === 'formal' ? 'uhraďte' : 'uhraď'} ${deadlineText}.`),
      verticalSpacer(spaceAfterText),
    ].join('');
  },
  depositFullyPaid: (totalAmount: string, _tone: Tone) => [
    verticalSpacer(spaceBeforeText),
    styledParagraph(`Děkujeme za úhradu celé částky ${bold(totalAmount)}. Objednávka je plně uhrazena.`),
    verticalSpacer(spaceAfterText),
  ].join(''),
  depositReminder: (
    remainingAmount: string,
    depositDeadline: string,
    accountNumber: string,
    iban: string | null,
    variableSymbol: string,
    tone: Tone
  ) => {
    return [
      verticalSpacer(spaceBeforeText),
      styledParagraph(`Připomínáme, že ${tone === 'formal' ? 'Vaše' : 'Tvá'} objednávka má doplatek ve výši ${bold(remainingAmount)}, který je třeba uhradit do ${bold(depositDeadline)}.`),
      verticalSpacer('15px'),
      styledParagraph(`Pro zjednodušení platby přikládáme QR kód.`),
      verticalSpacer(spaceAfterText),
      generatePaymentDetails({ accountNumber, iban, variableSymbol, amount: remainingAmount, lang: 'cs' }),
    ].join('');
  },
};