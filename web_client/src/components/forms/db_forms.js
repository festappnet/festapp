import { SupabaseService } from '../../services/supabase_service.js';
import { FormModel, FormFieldModel } from './form_models.js';

export class DbForms {
    
    static get metaSecret() { return 'secret'; }
    static get metaForm() { return 'form'; }

    static async getFormByLink(link) {
        const client = SupabaseService.getClient();
        if (!client) throw new Error("Supabase client not initialized");

        // Embedded browsers can leave a fetch pending indefinitely. Bound the
        // public read even when the transport does not settle after aborting.
        const controller = new AbortController();
        let timeout;
        let result;
        try {
            result = await Promise.race([
                client.rpc('get_form_by_link', { form_link: link }).abortSignal(controller.signal),
                new Promise((_, reject) => {
                    timeout = setTimeout(() => {
                        reject(new Error('Form loading timed out'));
                        controller.abort();
                    }, 20000);
                }),
            ]);
        } finally {
            clearTimeout(timeout);
        }
        const { data, error } = result;
        
        if (error) {
            throw new Error(error.message || 'Form loading failed');
        }
        
        if (data && data.code === 200) {
            return new FormModel(data.data);
        } else if (data && data.code === 400) {
             return new FormModel(data.data);
        }
        
        console.warn("Form fetch returned non-200 code:", data?.code, data?.message);
        return null;
    }

    static async getAllFormFields(formLink) {
        const client = SupabaseService.getClient();
        const { data, error } = await client.rpc('get_all_form_fields', { form_link: formLink });

        if (error) {
            console.error("Error fetching form fields:", error);
            return [];
        }

        if (Array.isArray(data)) {
            return data.map(f => new FormFieldModel(f));
        }
        
        return [];
    }
    static async getBlueprint(secret, formKey, blueprintId) {
        const client = SupabaseService.getClient();
        if (!client) throw new Error("Supabase client not initialized");

        const { data, error } = await client.rpc('get_blueprint', {
            my_secret: secret,
            form_key: formKey,
            blueprint_id: blueprintId
        });

        if (error) {
            console.error("Error fetching blueprint:", error);
            throw new Error(error.message || 'Blueprint data unavailable');
        }

        if (data && data.code === 200 && data.data) {
            return data.data; // Return the inner data object
        }
        
        throw new Error(data?.message || 'Blueprint data unavailable');
    }

    static async selectSpot(formKey, secret, spotId, selecting) {
        const client = SupabaseService.getClient();
        if (!client) throw new Error("Supabase client not initialized");

        const { data, error } = await client.rpc('select_spot', {
            form_key: formKey,
            secret_id: secret,
            spot_id: spotId,
            selecting: selecting
        });

        if (error) {
            console.error("Error selecting spot:", error);
            throw new Error(error.message);
        }

        if (data && data.code !== 200) {
            throw new Error(data.message || "Selection failed");
        }
        
        return data.data;
    }
}
