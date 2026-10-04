CREATE OR REPLACE FUNCTION public.format_occasion_report_text(report jsonb)
RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path = public, extensions AS $$
DECLARE result text; item jsonb; section text;
BEGIN
  result := (report->'occasion'->>'title') || E'\n' || (report->>'generated_at') || E'\n';
  FOREACH section IN ARRAY ARRAY['orders','tickets'] LOOP
    result := result || CASE section WHEN 'orders' THEN 'Počet objednávek celkem: ' ELSE 'Počet vstupenek celkem: ' END || (report->section->>'total') || E'\n';
    FOR item IN SELECT value FROM jsonb_array_elements(report->section->'by_state') LOOP
      result := result || '  ' || (item->>'state') || ': ' || (item->>'count') || E'\n';
    END LOOP;
  END LOOP;
  result := result || 'Místa (obsazená / celkem): ' || (report->'spots'->>'occupied') || ' / ' || (report->'spots'->>'total') || E'\n';
  FOR item IN SELECT value FROM jsonb_array_elements(report->'money_by_currency') LOOP
    result := result || E'\n' || (item->>'currency') || E'\n'
      || 'Aktuální hodnota objednávek: ' || (item->>'current_order_value') || E'\n'
      || 'Přijato: ' || (item->>'received') || E'\n'
      || 'Vráceno: ' || (item->>'returned') || E'\n'
      || 'Čistý příjem: ' || (item->>'net_received') || E'\n'
      || 'Ručně evidováno: ' || (item->>'manual_received') || E'\n'
      || 'Ostatní příjmy: ' || (item->>'other_received') || E'\n';
    IF (item->>'has_deposits')::boolean THEN
      result := result || 'Přijaté zálohy (hrubé): ' || (item->>'deposit_received_gross') || E'\n'
        || 'Přijato nad zálohu (hrubé): ' || (item->>'beyond_deposit_received_gross') || E'\n';
    END IF;
  END LOOP;
  IF report ? 'timeline' THEN
    result := result || E'\nNové objednávky po dnech (Europe/Prague, včetně později stornovaných):\n';
    FOR item IN SELECT value FROM jsonb_array_elements(report->'timeline'->'orders') LOOP
      result := result || (item->>'day') || ' ' || (item->>'currency') || ': ' || (item->>'count') || E'\n';
    END LOOP;
    result := result || E'\nZaevidované platby po dnech (datum transakce; včetně částečných plateb):\n';
    FOR item IN SELECT value FROM jsonb_array_elements(report->'timeline'->'payments') LOOP
      result := result || (item->>'day') || ' ' || (item->>'currency') || ': přijato ' || (item->>'received') || ', vráceno ' || (item->>'returned') || E'\n';
    END LOOP;
  END IF;
  result := result || E'\nProdukty v potvrzených objednávkách (paid/sent/used, včetně záloh):\n';
  FOR item IN SELECT value FROM jsonb_array_elements(report->'products') LOOP
    result := result || coalesce(item->>'type_title','Bez typu') || ' / ' || (item->>'product_title') || ': ' || (item->>'confirmed_count') || E'\n';
  END LOOP;
  result := result || E'\nSouhrn stavů odpovídá aktuálnímu stavu, nikoli historickým přechodům. Denní platby obsahují pouze zaevidované transakce. Stav paid může znamenat jen uhrazenou zálohu.\nMísta nezahrnují dočasné blokace. Ruční příjmy nejsou nutně hotovost; ostatní nejsou nutně banka.\nZálohy jsou hrubé platby před vratkami, pouze u plateb se zálohou.\n';
  FOR item IN SELECT value FROM jsonb_array_elements(report->'warnings') LOOP
    result := result || 'Upozornění: ' || (item->>'code') || ' (' || (item->>'count') || E')\n';
  END LOOP;
  RETURN result;
END;
$$;
REVOKE ALL ON FUNCTION public.format_occasion_report_text(jsonb) FROM PUBLIC, anon, authenticated, service_role;
