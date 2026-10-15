import { SupabaseService } from '../../services/supabase_service.js';
import { extractPublicOccasions } from './catalog.js';
import { OccasionModel } from './occasion_model.js';

export class DbOccasions {
    
    static async getPublicOccasions(organizationId) {
        const client = SupabaseService.getClient();
        if (!client) throw new Error("Supabase client not initialized");
        
        const { data, error } = await client.rpc('get_available_occasions', {
            p_organization_id: organizationId,
            p_unit_id: null
        });
        
        if (error) {
            console.error("Supabase RPC Error (get_public_occasions):", error);
            throw error;
        }
        
        return extractPublicOccasions(data).map(json => OccasionModel.fromJson(json));
    }
}
