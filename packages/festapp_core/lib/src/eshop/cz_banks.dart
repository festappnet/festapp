// Source: https://www.cnb.cz/cs/platebni-styk/ucty-kody-bank/
// Key: Bank Code (4 digits)
// Value: Bank Name

const Map<String, String> czBanks = {
  "0100": "Komerční banka, a.s.",
  "0300": "Československá obchodní banka, a. s.",
  "0600": "MONETA Money Bank, a.s.",
  "0710": "Česká národní banka",
  "0800": "Česká spořitelna, a.s.",
  "2010": "Fio banka, a.s.",
  "2060": "Citfin, spořitelní družstvo",
  "2070": "TRINITY BANK a.s.",
  "2100": "Hypoteční banka, a.s.",
  "2200": "Peněžní dům, spořitelní družstvo",
  "2220": "Artesa, spořitelní družstvo",
  "2240": "Poštová banka, a.s., pobočka Česká republika",
  "2250": "Banka CREDITAS a.s.",
  "2600": "Citibank Europe plc, organizační složka",
  "2700": "UniCredit Bank Czech Republic and Slovakia, a.s.",
  "3030": "Air Bank a.s.",
  "3050": "BNP Paribas Personal Finance SA, odštěpný závod",
  "3060": "PKO BP S.A., Czech Branch",
  "3500": "ING Bank N.V.",
  "4000": "Max banka a.s.",
  "4300": "Národní rozvojová banka, a.s.",
  "5500": "Raiffeisenbank a.s.",
  "6000": "PPF banka a.s.",
  "6100": "Equa bank a.s. (merged with RB)", // Kept for historical data
  "6200": "COMMERZBANK Aktiengesellschaft, pobočka Praha",
  "6210": "mBank S.A., organizační složka",
  "6300": "BNP Paribas S.A., pobočka Česká republika",
  "6700": "Všeobecná úvěrová banka a.s., pobočka Praha",
  "6810": "Volksbank Raiffeisenbank Nordoberpfalz eG pobočka Cheb",
  "7910": "Deutsche Bank Aktiengesellschaft Filiale Prag, organizační složka",
  "7940": "Waldviertler Sparkasse Bank AG",
  "7950": "Raiffeisenlandesbank Oberösterreich Aktiengesellschaft, pobočka Česká republika",
  "7960": "J&T BANKA, a.s.",
  "7970": "Oberbank AG pobočka Česká republika",
  "7980": "Wüstenrot - stavební spořitelna a.s. (merged with MONETA)",
  "7990": "Modrá pyramida stavební spořitelna, a.s.",
  "8030": "Raiffeisen stavební spořitelna a.s.",
  "8040": "Oberbank AG pobočka Česká republika",
  "8060": "Stavební spořitelna České spořitelny, a.s.",
  "8090": "Česká exportní banka, a.s.",
  "8150": "HSBC Continental Europe, Czech Republic",
  "8200": "Privatbanka, a.s., pobočka Česká republika",
  "8250": "Bank of China (CEE) Ltd. Prague Branch",
  "8255": "Bank of Communications Co., Ltd., Prague Branch",
  "8260": "Industrial and Commercial Bank of China Limited, Prague Branch",
  "8265": "Industrial and Commercial Bank of China Limited, Prague Branch",
};

bool isFioBank(String? input) {
  if (input == null) return false;
  // Case 1: Exact Bank Code
  if (input == '2010') return true;

  // Case 2: Full CZ IBAN (24 chars)
  // Format: CZkk bbbb pppp ppaa aaaa aaaa
  // Bank code is at index 4 (0-based) length 4
  // We can just check if it contains 2010 but safer to check specific position if it looks like IBAN

  String clean = input.replaceAll(' ', '').toUpperCase();
  if (clean.length == 24 && clean.startsWith('CZ')) {
    // Bank Code is substring 4-8
    String bankCode = clean.substring(4, 8);
    return bankCode == '2010';
  }

  return false;
}

/// BankSync notification providers. API synchronization remains Fio-only.
const bankSyncEmailProviders = <String, String>{
  '2010': 'FIO',
  '3030': 'AIRBANK',
  '0300': 'CSOB',
  '0600': 'MONETA',
  '2250': 'CREDITAS',
  '5500': 'RAIFFEISENBANK',
  '2700': 'UNICREDIT',
  '0800': 'CSAS',
};

String? bankSyncProviderForAccount(String? accountNumber) {
  final account = (accountNumber ?? '')
      .replaceAll(RegExp(r'\s'), '')
      .toUpperCase();
  final bankCode = RegExp(r'^CZ[0-9]{22}$').hasMatch(account)
      ? account.substring(4, 8)
      : RegExp(r'/([0-9]{4})$').firstMatch(account)?.group(1);
  return bankSyncEmailProviders[bankCode];
}
