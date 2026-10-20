// Disposable synthetic renderer fixture. No live credentials, asset fetch or mail.
import { handlePreview } from '../../../supabase/functions/preview-ticket-layout/handler.ts';
import {
    futuraId,
    fontMetrics,
} from '../../../supabase/functions/_shared/ticketFonts.ts';
const font = await Deno.readFile(
    'supabase/functions/_shared/ticket-assets/font.ttf',
);
const metrics = fontMetrics(font);
const dependencies = {
    authorize: async () => ({
        abuseLimits: {
            'document.input.bytes': 1048576,
            'document.asset.bytes': 5242880,
            'document.output.bytes': 16777216,
            'document.output.pages': 20,
        },
    }),
    occasion: async () => ({
        id: 7,
        title: 'Synthetic MCP Preview',
        features: [{ code: 'ticket', ticket_type: 'named' }],
        data: {},
    }),
    products: async () => ({ types: new Map(), products: new Map() }),
    resources: async () => ({
        font,
        metrics,
        fonts: {
            [futuraId]: {
                id: futuraId,
                bytes: font,
                metrics,
                family: 'Futura PT',
                weight: 400,
            },
        },
    }),
};
const results: Record<string, unknown> = {};
for (const mode of ['resolve', 'pdf']) {
    const response = await handlePreview(
        new Request('https://fixture.invalid', {
            method: 'POST',
            headers: { Authorization: 'Bearer synthetic-fixture' },
            body: JSON.stringify({
                occasionId: 7,
                type: 'named',
                mode,
                fontProtocol: 2,
                scenario: 'normal',
            }),
        }),
        dependencies,
    );
    if (response.status !== 200)
        throw new Error('Canonical renderer fixture failed');
    results[mode] = await response.json();
}
console.log(JSON.stringify(results));
