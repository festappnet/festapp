import { z } from 'zod';
import { toolResult } from './protocol.mjs';
import {
    McpServer,
    ResourceTemplate,
} from '@modelcontextprotocol/server';
export function createServer(operations) {
    const server = new McpServer({
        name: 'festapp-operator',
        version: '0.1.0',
    });
    const gated = [];
    const listed = new Map();
    operations.onWriteReadinessChanged = (ready) => {
        for (const tool of gated)
            if (ready) tool.enable();
            else tool.disable();
    };
    for (const operation of operations.catalog) {
        const registered = server.registerTool(
            operation.name,
            {
                title: operation.title,
                description: operation.description,
                inputSchema: operation.input,
                outputSchema: operation.output,
                annotations: {
                    readOnlyHint: operation.domainReadOnly,
                    destructiveHint: operation.destructive ?? false,
                    idempotentHint: operation.idempotent ?? operation.domainReadOnly,
                    openWorldHint: true,
                },
            },
            async (args) => {
                return toolResult(await operations.invoke(operation.id, args), operations.owner, operation.id);
            },
        );
        listed.set(operation.name, { operation, registered });
        if (operation.requiresLayoutWriteContract) gated.push(registered);
    }
    // SDK 2.3.1 omits extension fields in registerTool. Its public low-level
    // handler retains SDK invocation/schema validation and registered enablement.
    // No private SDK fields or patched dependencies are needed.
    server.server.setRequestHandler('tools/list', () => ({ tools: [...listed.values()]
        .filter(({ registered }) => registered.enabled)
        .map(({ operation }) => {
            const schemes = operations.owner?.securitySchemesFor?.(operation.id) ?? operations.owner?.securitySchemes;
            return {
                name: operation.name, title: operation.title, description: operation.description,
                inputSchema: z.toJSONSchema(operation.input, { io: 'input' }),
                outputSchema: z.toJSONSchema(operation.output, { io: 'output' }),
                annotations: {
                    readOnlyHint: operation.domainReadOnly,
                    destructiveHint: operation.destructive ?? false,
                    idempotentHint: operation.idempotent ?? operation.domainReadOnly,
                    openWorldHint: true,
                },
                ...(schemes ? { securitySchemes: schemes, _meta: { securitySchemes: schemes } } : {}),
            };
        }) }));
    server.registerResource(
        'ticket-preview',
        new ResourceTemplate('festapp-preview://artifact/{artifact}', {
            list: undefined,
        }),
        {
            mimeType: 'application/pdf',
            description:
                'Short-lived canonical synthetic preview. Access is reauthorized on every read.',
        },
        (uri) => operations.readArtifact(uri.href),
    );
    return server;
}
