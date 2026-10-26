CREATE OR REPLACE FUNCTION public.get_bank_name_from_code(p_code text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public, extensions
AS $$
BEGIN
    -- Common Czech Banks
    RETURN CASE p_code
        WHEN '0100' THEN 'Komerční banka'
        WHEN '0300' THEN 'ČSOB'
        WHEN '0600' THEN 'MONETA Money Bank'
        WHEN '0800' THEN 'Česká spořitelna'
        WHEN '2010' THEN 'Fio banka'
        WHEN '2060' THEN 'Citfin'
        WHEN '2070' THEN 'Markov'
        WHEN '2200' THEN 'Peněžní dům'
        WHEN '2220' THEN 'Artemis'
        WHEN '2240' THEN 'Poštová banka'
        WHEN '2250' THEN 'Banka CREDITAS'
        WHEN '2260' THEN 'Moravský Peněžní Ústav'
        WHEN '2275' THEN 'Podnikatelská družstevní záložna'
        WHEN '2400' THEN 'The Royal Bank of Scotland'
        WHEN '2600' THEN 'Citibank'
        WHEN '2700' THEN 'UniCredit Bank'
        WHEN '3030' THEN 'Air Bank'
        WHEN '3050' THEN 'BNP Paribas'
        WHEN '3060' THEN 'PKO BP'
        WHEN '3500' THEN 'ING Bank'
        WHEN '4000' THEN 'Max banka' -- Formerly Expobank
        WHEN '4300' THEN 'Českomoravská záruční a rozvojová banka'
        WHEN '5500' THEN 'Raiffeisenbank'
        WHEN '6000' THEN 'PPF banka'
        WHEN '6210' THEN 'mBank'
        WHEN '6300' THEN 'BNP Paribas Fortis'
        WHEN '6700' THEN 'Všeobecná úverová banka'
        WHEN '7910' THEN 'Deutsche Bank'
        WHEN '7940' THEN 'Waldviertler Sparkasse Bank'
        WHEN '7950' THEN 'Raiffeisen stavební spořitelna'
        WHEN '7960' THEN 'Českomoravská stavební spořitelna'
        WHEN '7970' THEN 'Wüstenrot - stavební spořitelna'
        WHEN '7980' THEN 'Wüstenrot hypoteční banka'
        WHEN '7990' THEN 'Modrá pyramida'
        WHEN '8030' THEN 'Raiffeisenbank im Stiftland'
        WHEN '8040' THEN 'Oberbank'
        WHEN '8060' THEN 'Stavební spořitelna České spořitelny'
        WHEN '8090' THEN 'Česká exportní banka'
        WHEN '8150' THEN 'HSBC'
        WHEN '8200' THEN 'Privatbanka'
        WHEN '8220' THEN 'Payment Execution'
        WHEN '8230' THEN 'EEP'
        WHEN '8240' THEN 'Družstevní záložna Kredit'
        WHEN '8250' THEN 'Bank of China'
        WHEN '8255' THEN 'Bank of Communications'
        WHEN '8260' THEN 'Industrial and Commercial Bank of China'
        WHEN '8265' THEN 'China Construction Bank'
        ELSE NULL
    END;
END;
$$;
