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
let stressLayout;
if(Deno.args[1]==='heavy') {
    const {defaultTicketTemplate,ticketLayoutByteSize,validateLayout}=await import('../../../supabase/functions/_shared/ticketLayout.ts');
    const template=defaultTicketTemplate('named');
    while(template.elements.length<32)template.elements.push({...structuredClone(template.elements[0]),id:'stress'+template.elements.length,binding:'text',text:'Qualified bounded preview text. '.repeat(32),style:{...template.elements[0].style,maxLines:12}});
    stressLayout={schemaVersion:3,templates:{named:template}};
    while(ticketLayoutByteSize(stressLayout)>32768)for(const element of template.elements)if(element.binding==='text')element.text=element.text!.slice(0,-32);
    validateLayout(stressLayout);
}

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
                scenario: Deno.args[0] ?? 'normal',
                ...(stressLayout?{layout:stressLayout}:{}),
            }),
        }),
        dependencies,
    );
    if (response.status !== 200)
        throw new Error('Canonical renderer fixture failed: '+response.status+' '+(await response.text()).slice(0,500));
    results[mode] = await response.json();
}
console.log(JSON.stringify(results));
