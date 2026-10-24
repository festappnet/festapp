// Disposable-only HTTP boundary. Captures real rendering of persisted canonical
// queue rows without dispatch or provider acceptance. Never deployed to a tenant.
import {supabaseAdmin} from '../_shared/supabaseUtil.ts';
import {renderQueuedEmail} from '../_shared/emailRenderer.ts';
import {openEmail} from '../_shared/emailPayload.ts';
Deno.serve(async (req) => {
  try {
    if (Deno.env.get('VO_LOCAL_CAPTURE') !== '1' || !Deno.env.get('SUPABASE_URL')?.includes('kong:8000')) throw Error('local_capture_disabled');
    if (req.headers.get('x-local-capture') !== Deno.env.get('VO_CAPTURE_SECRET')) return new Response('',{status:403});
    const {data:org} = await supabaseAdmin.from('organizations').select('title').eq('id',1).single();
    if (org?.title !== 'Test Organization') throw Error('synthetic_organization_required');
    const {data:rows,error} = await supabaseAdmin.from('email_messages').select('*').not('order_id','is',null).in('message_kind',['order_confirmation','order_tickets']).order('created_at');
    if (error) throw error;
    const captures=[];
    for (const row of rows??[]) {
      if (!row.recipient?.endsWith('@example.invalid')) throw Error('non_synthetic_recipient');
      try {
        const result = row.prepared ? {prepared:await openEmail(row.prepared),postAction:row.post_action} : await renderQueuedEmail(row);
        captures.push({message_id:row.message_id,kind:row.message_kind,order_id:row.order_id,...result});
      } catch(e) { captures.push({kind:row.message_kind,order_id:row.order_id,error:String(e.stack ?? e)}); }
    }
    return Response.json({mode:'capture_only_no_provider_send',captures});
  } catch(e) {return Response.json({error:String(e.stack ?? e)},{status:500});}
});
