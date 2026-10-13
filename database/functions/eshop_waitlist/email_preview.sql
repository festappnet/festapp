-- An editor preview resolves the same inherited template/wrapper as delivery.
-- It never creates a capability, offer, intent, or reservation.
CREATE OR REPLACE FUNCTION public.get_waitlist_offer_email_preview(p_form_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=public,extensions AS $$
DECLARE f public.forms; occ public.occasions; resolved jsonb; tone jsonb;
 v_key text; v_value text; html text; subject text; v_timezone text; instructions_html text;
BEGIN
 SELECT * INTO STRICT f FROM public.forms WHERE id=p_form_id;
 PERFORM public.check_is_editor_order_on_occasion(f.occasion);
 SELECT * INTO STRICT occ FROM public.occasions WHERE id=f.occasion;
 resolved:=public.get_email_template_and_wrapper('waitlist_offer',
  jsonb_build_object('organization',occ.organization,'occasion',occ.id,'unit',occ.unit));
 -- Match the trusted delivery context's existing occasion/unit/org fallback.
 v_timezone:=public.get_waitlist_form_timezone_internal(f.id);
 -- Older preview clients know order/count/date variables, but not the new
 -- semantic copy keys. Expand only trusted copy here; leave those old keys.
 tone:=public.get_waitlist_email_tone_substitutions_internal(f.id);
 html:=resolved#>>'{template,html}'; subject:=resolved#>>'{template,subject}';
 instructions_html:=html;
 FOR v_key,v_value IN SELECT key,value FROM jsonb_each_text(tone) LOOP
  v_value:=replace(replace(replace(replace(replace(v_value,'&','&amp;'),'<','&lt;'),'>','&gt;'),'"','&quot;'),chr(39),'&#39;');
  html:=replace(html,'{{'||v_key||'}}',v_value);
  IF v_key<>'waitlist_offer_instructions' THEN
   instructions_html:=replace(instructions_html,'{{'||v_key||'}}',v_value);
  END IF;
  subject:=replace(subject,'{{'||v_key||'}}',v_value);
 END LOOP;
 IF html IS NOT NULL THEN resolved:=jsonb_set(resolved,'{template,html}',to_jsonb(html)); END IF;
 IF subject IS NOT NULL THEN resolved:=jsonb_set(resolved,'{template,subject}',to_jsonb(subject)); END IF;
 RETURN resolved||jsonb_build_object('code',200,'occasionTitle',occ.title,'formLink',f.link,
 'timeZone',v_timezone,'instructionsTemplateHtml',instructions_html,
 'communicationTone',public.get_effective_form_data(f.id)->>'communication_tone',
 'toneSubstitutions',tone);
END $$;
REVOKE ALL ON FUNCTION public.get_waitlist_offer_email_preview(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_waitlist_offer_email_preview(bigint) TO authenticated;
