-- Generic fallbacks for routes that previously had only tenant-specific seeds.
-- Content matches the live CSM Ostrava templates (canonical organization 12,
-- verified 2026-10-06). Only subjects use appName instead of a fixed brand.
-- Organization/unit/occasion overrides retain precedence; existing rows are preserved.
INSERT INTO public.email_templates(html, subject, code, title)
SELECT defaults.html, defaults.subject, defaults.code, defaults.title
FROM (VALUES
  (
    '<p>Obdrželi jsme žádost o smazání účtu v {{appName}}.</p><p><a href="{{confirmationUrl}}">Zkontrolovat a potvrdit smazání účtu</a></p><p>Odkaz platí do {{expiresAt}}. Pouhé otevření odkazu účet nesmaže. Nikomu jej nepřeposílejte.</p>',
    'Potvrďte smazání účtu v {{appName}}',
    'ACCOUNT_DELETION_CONFIRM', 'Smazání účtu - potvrzení'
  ),
  (
    '<p>Váš účet v {{appName}} byl smazán. Soukromá účastnická data a propojená push identita byly odstraněny; právně vyžadované záznamy mohou zůstat pouze bez přímé identity.</p>',
    'Účet v {{appName}} byl smazán',
    'ACCOUNT_DELETION_COMPLETE', 'Smazání účtu - dokončeno'
  ),
  (
    '{{appLinks}}', 'Aplikace {{appName}}', 'APP_LINKS', 'Odkazy na aplikaci'
  )
) AS defaults(html, subject, code, title)
WHERE NOT EXISTS (
  SELECT 1 FROM public.email_templates existing
  WHERE existing.code = defaults.code AND existing.organization IS NULL
    AND existing.unit IS NULL AND existing.occasion IS NULL
);
