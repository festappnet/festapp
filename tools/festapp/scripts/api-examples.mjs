// Deterministic synthetic examples. Runtime Zod schemas validate every example;
// this helper never invents an executor, actor credential or real customer data.
const UUID = '11111111-1111-4111-8111-111111111111';
export function schemaExample(schema, root = schema, key = '', depth = 0) {
    if (depth > 24) throw new Error('Example schema recursion: ' + key);
    if (schema.$ref) {
        const target = schema.$ref.slice(2).split('/').reduce((value, part) => value?.[part.replaceAll('~1','/').replaceAll('~0','~')], root);
        if (!target) throw new Error('Unresolved example reference: ' + schema.$ref);
        return schemaExample(target, root, key, depth + 1);
    }
    if (Object.hasOwn(schema, 'const')) return schema.const;
    if (schema.enum) return schema.enum[0];
    if (schema.default !== undefined) return structuredClone(schema.default);
    if (schema.anyOf || schema.oneOf) return schemaExample((schema.anyOf ?? schema.oneOf)[0], root, key, depth + 1);
    if (Array.isArray(schema.type)) return schemaExample({...schema,type:schema.type[0]},root,key,depth+1);
    if (schema.type === 'null') return null;
    if (schema.type === 'boolean') return false;
    if (schema.type === 'number' || schema.type === 'integer') {
        let value = Math.max(0,schema.minimum ?? 0);
        if (schema.exclusiveMinimum !== undefined) value = Math.max(value,schema.exclusiveMinimum+1);
        if (/(?:Id|_id)$/.test(key) && !/version/i.test(key)) value = Math.max(value,/second|target/i.test(key)?2:1);
        return Math.min(value,schema.maximum ?? Infinity);
    }
    if (schema.type === 'array') return Array.from({length:schema.minItems ?? 0},()=>schemaExample(schema.items,root,key,depth+1));
    if (schema.type === 'object' || schema.properties) return Object.fromEntries((schema.required ?? []).map(name=>[name,schemaExample(schema.properties[name],root,name,depth+1)]));
    if (schema.type === 'string') {
        if (schema.format === 'email') return 'synthetic@example.invalid';
        if (schema.format === 'uuid') return UUID;
        if (schema.format === 'date-time') return /to|end/i.test(key)?'2026-11-14T12:00:00Z':'2026-11-13T12:00:00Z';
        if (schema.format === 'date') return '2026-11-13';
        if (schema.format === 'uri' || schema.format === 'url') return 'https://example.invalid/reference';
        if (schema.pattern?.includes('festapp-export')) return 'festapp-export://artifact/'+'a'.repeat(64)+'.json';
        if (schema.pattern?.includes('festapp-')) return 'festapp-preview://artifact/'+'a'.repeat(64)+'.pdf';
        if (schema.pattern?.includes('\\d')) return schema.pattern.includes('\\.') ? '0.00' : '0';
        if (schema.pattern?.includes('{64}')) return 'a'.repeat(64);
        if (schema.pattern?.includes('{10}')) return 'ABCDE12345';
        if (schema.pattern?.includes('[A-Z]{3}') || /currency/i.test(key)) return 'CZK';
        if (schema.pattern?.includes('[A-Z]{2}')) return 'CZ';
        if (/amount|price|paid|returned|received|gross|net|pending|fee|balance/i.test(key)) return '0.00';
        return 'example'.slice(0,schema.maxLength ?? Infinity).padEnd(schema.minLength ?? 0,'a');
    }
    return null; // Unconstrained JSON.
}
export function operationExamples(descriptor, inputSchema, outputSchema) {
    const request = descriptor.id === 'products.save' ? {occasionId:7,commandId:UUID,product:{title:'Admission',price:'100.00',currency_code:'CZK',product_type:1}} : schemaExample(inputSchema);
    const response = {...schemaExample(outputSchema),ok:true};
    delete response.error;
    if (outputSchema.properties?.data) response.data = schemaExample(outputSchema.properties.data,outputSchema,'data');
    if (descriptor.id === 'ticket_layouts.preview') response.data.image={mimeType:'image/png',data:'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a6ZsAAAAASUVORK5CYII='};
    if (descriptor.id === 'seats.preview_swap') {
        response.data.sourceSpotIds = [response.data.firstSpotId];
        response.data.targetSpotIds = [response.data.secondSpotId];
        const seatSchema = outputSchema.properties.data.properties.seats.items;
        response.data.seats = [response.data.firstSpotId,response.data.secondSpotId].map(spotId=>({
            ...schemaExample(seatSchema,outputSchema),spotId,orderId:null,ticketId:null,productId:null,
        }));
        response.data.orders = [];
    }
    const input = descriptor.input.safeParse(request),output=descriptor.output.safeParse(response);
    if (!input.success || !output.success) throw new Error('Invalid canonical example for '+descriptor.id+': '+JSON.stringify((!input.success?input.error:output.error).issues));
    return {request,response};
}
