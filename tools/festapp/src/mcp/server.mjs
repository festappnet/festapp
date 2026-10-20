import {
    McpServer,
    ResourceTemplate,
} from '@modelcontextprotocol/sdk/server/mcp.js';
export function createServer(operations) {
    const server = new McpServer({
        name: 'festapp-operator',
        version: '0.1.0',
    });
    const gated = [];
    operations.onWriteReadinessChanged = (ready) => {
        for (const tool of gated)
            if (ready) tool.enable();
            else tool.disable();
    };
    for (const operation of operations.catalog) {
        const registered = server.registerTool(
            operation.name,
            {
                description: operation.description,
                inputSchema: operation.input,
                outputSchema: operation.output,
                ...(operations.owner?.securitySchemes ? {
                    _meta: { securitySchemes: operations.owner.securitySchemes },
                } : {}),
                annotations: {
                    readOnlyHint: operation.domainReadOnly,
                    destructiveHint: false,
                    idempotentHint: operation.domainReadOnly,
                    openWorldHint: true,
                },
            },
            async (args) => {
                const result = await operations.invoke(operation.id, args);
                if (!result.ok)
                    return {
                        isError: true,
                        content: [
                            { type: 'text', text: JSON.stringify(result) },
                        ],
                        structuredContent: result,
                        ...(['AUTHENTICATION_REQUIRED', 'MFA_REQUIRED'].includes(result.error?.code) && operations.owner?.authChallenge
                            ? { _meta: { 'mcp/www_authenticate': [operations.owner.authChallenge] } } : {}),
                    };
                if (!result.data.image)
                    return {
                        content: [
                            { type: 'text', text: JSON.stringify(result) },
                        ],
                        structuredContent: result,
                    };
                const { image, ...data } = result.data;
                const structuredContent = { ...result, data };
                return {
                    content: [
                        {
                            type: 'text',
                            text: JSON.stringify(structuredContent),
                        },
                        {
                            type: 'image',
                            mimeType: image.mimeType,
                            data: image.data,
                        },
                        {
                            type: 'resource_link',
                            uri: data.pdf.uri,
                            name: 'Canonical synthetic ticket preview',
                            mimeType: 'application/pdf',
                        },
                    ],
                    structuredContent,
                };
            },
        );
        if (operation.requiresLayoutWriteContract) gated.push(registered);
    }
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
