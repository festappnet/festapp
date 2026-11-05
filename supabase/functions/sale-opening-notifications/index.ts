import { supabaseAdmin } from '../_shared/supabaseUtil.ts';
import { saleOpeningHandler } from './handler.ts';
Deno.serve(saleOpeningHandler((name, args) => supabaseAdmin.rpc(name, args)));
