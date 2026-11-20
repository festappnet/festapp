import { z } from 'zod';
import { check, OperationError, upstream } from '../errors.mjs';
import { operatorAccess } from './access.mjs';

export const imageUploadOperation = 'images.upload';
export const imageUploadTool = 'festapp_images_upload';
const maxImageBytes = 1024 * 1024;
const maxBase64Length = Math.ceil(maxImageBytes / 3) * 4;
export const imageUploadBodyLimit = maxBase64Length + 8192;

const contentTypes = {
    jpg: 'image/jpeg',
    jpeg: 'image/jpeg',
    png: 'image/png',
    webp: 'image/webp',
};
const projectHosts = {
    default: 'img.festapp.net',
    a: 'a.img.festapp.net',
    slunovrat: 'img.festapp.net',
};
const uploadOutput = z.strictObject({ url: z.url() });

export const imageUploadDescriptor = {
    id: imageUploadOperation,
    name: imageUploadTool,
    title: 'Upload an occasion image',
    description: 'Upload one approved public JPEG, PNG or WebP image for an occasion. Supply the file bytes as base64, up to 1 MiB. Use the returned Festapp URL in the event description or speaker image field. This operation does not edit a record. A lost response can leave an uploaded asset, so do not retry automatically.',
    domainReadOnly: false,
    input: z.strictObject({
        occasionId: z.number().int().positive().max(Number.MAX_SAFE_INTEGER),
        filename: z.string().min(5).max(120).regex(/^[A-Za-z0-9][A-Za-z0-9._-]*\.(?:jpe?g|png|webp)$/i),
        contentBase64: z.string().min(4).max(maxBase64Length).regex(/^[A-Za-z0-9+/]+={0,2}$/),
        profile: z.enum(['standard', 'portrait']).default('standard'),
    }),
};
export const imageDataSchemas = { [imageUploadOperation]: uploadOutput };

export async function uploadOccasionImage(owner, client, args) {
    const bytes = Buffer.from(args.contentBase64, 'base64');
    check(bytes.length > 0 && bytes.length <= maxImageBytes &&
        bytes.toString('base64') === args.contentBase64, 'INVALID_INPUT');

    const scope = await owner.delegatedContext(client, args.occasionId);
    const access = await operatorAccess(client, scope, { occasionId: args.occasionId, unitId: scope.unitId });
    check(access.occasions.some(occasion => occasion.id === args.occasionId &&
        (scope.unitId == null || occasion.unitId === scope.unitId)), 'FORBIDDEN');

    const projects = await Promise.all(Object.keys(projectHosts).map(async project => {
        const { data, error } = await client.rpc('get_image_project_access_v1', {
            p_project: project, p_occasion: args.occasionId, p_unit: null,
        });
        upstream(error);
        return data === true ? project : null;
    }));
    const allowedProjects = projects.filter(Boolean);
    check(allowedProjects.length === 1, 'FORBIDDEN');
    const [projectId] = allowedProjects;

    const { data, error } = await client.auth.getSession();
    upstream(error);
    check(data?.session?.access_token, 'AUTHENTICATION_REQUIRED');

    const form = new FormData();
    const extension = args.filename.split('.').at(-1).toLowerCase();
    form.set('file', new Blob([bytes], { type: contentTypes[extension] }), args.filename);
    form.set('projectId', projectId);
    form.set('occasionId', String(args.occasionId));
    form.set('profile', args.profile);

    try {
        const response = await (owner.imageUploadFetch ?? fetch)('https://image-api.festapp.net/upload', {
            method: 'POST',
            headers: { Authorization: 'Bearer ' + data.session.access_token },
            body: form,
            redirect: 'error',
            signal: AbortSignal.timeout(45000),
        });
        if (response.status === 401) throw new OperationError('AUTHENTICATION_REQUIRED');
        if (response.status === 403) throw new OperationError('FORBIDDEN');
        if ([400, 413, 415, 422, 429].includes(response.status)) throw new OperationError('IMAGE_UPLOAD_REJECTED');
        if (!response.ok) throw new OperationError('IMAGE_UPLOAD_OUTCOME_UNKNOWN');
        const result = await response.json();
        const url = new URL(result.url);
        check(result.projectId === projectId && url.origin === 'https://' + projectHosts[projectId] &&
            !url.username && !url.password && url.pathname.startsWith('/images/') &&
            !url.search && !url.hash, 'IMAGE_UPLOAD_OUTCOME_UNKNOWN');
        return uploadOutput.parse({ url: url.href });
    } catch (error) {
        if (error instanceof OperationError) throw error;
        throw new OperationError('IMAGE_UPLOAD_OUTCOME_UNKNOWN');
    }
}
