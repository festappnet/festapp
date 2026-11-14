import { restoreApiArchive } from './api-artifacts.mjs';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';

const equal = (a,b) => JSON.stringify(a) === JSON.stringify(b);
/** Request shapes may widen; response shapes may narrow. Unknown schema
 * constructs are conservatively incompatible, rather than silently accepted. */
export function schemaBreaks(before, after, direction, at = '$') {
    if (equal(before, after)) return [];
    if (!before || !after) return [at + ': schema removed'];
    const issues = [], request = direction === 'request';
    const fail = reason => issues.push(at + ': ' + reason);
    const types = s => new Set([s.type].flat().filter(Boolean));
    const a = types(before), b = types(after);
    if ((request ? [...a].some(v=>!b.has(v)) : [...b].some(v=>!a.has(v))) && (a.size || b.size)) fail('incompatible type');
    const values = s => s.enum ?? ('const' in s ? [s.const] : undefined);
    const av = values(before), bv = values(after);
    if (request ? bv && (!av || av.some(v=>!bv.some(w=>equal(v,w)))) : av && (!bv || bv.some(v=>!av.some(w=>equal(v,w))))) fail('incompatible enum/const');
    const ar = before.required ?? [], br = after.required ?? [];
    if (request ? br.some(v=>!ar.includes(v)) : ar.some(v=>!br.includes(v))) fail('incompatible required fields');
    for (const [key, sign] of [['minimum',1],['exclusiveMinimum',1],['minLength',1],['minItems',1],['minProperties',1],['maximum',-1],['exclusiveMaximum',-1],['maxLength',-1],['maxItems',-1],['maxProperties',-1]]) {
        const x = before[key] ?? (sign === 1 ? -Infinity : Infinity), y = after[key] ?? (sign === 1 ? -Infinity : Infinity);
        if (request ? sign*y > sign*x : sign*y < sign*x) fail('incompatible ' + key);
    }
    for (const [name, schema] of Object.entries(before.properties ?? {})) {
        if (!after.properties?.[name]) fail('property removed: ' + name);
        else issues.push(...schemaBreaks(schema, after.properties[name], direction, at + '.' + name));
    }
    if (!request && before.additionalProperties === false && Object.keys(after.properties ?? {}).some(k=>!before.properties?.[k])) fail('strict response property added');
    if (request && before.additionalProperties !== false && after.additionalProperties === false) fail('additional input fields rejected');
    if (before.items || after.items) issues.push(...schemaBreaks(before.items, after.items, direction, at + '[]'));
    if (typeof before.additionalProperties === 'object' || typeof after.additionalProperties === 'object') issues.push(...schemaBreaks(before.additionalProperties, after.additionalProperties, direction, at + '.*'));
    const handled = new Set(['$schema','title','description','examples','example','deprecated','type','enum','const','required','properties','items','additionalProperties','minimum','maximum','exclusiveMinimum','exclusiveMaximum','minLength','maxLength','minItems','maxItems','minProperties','maxProperties']);
    for (const key of new Set([...Object.keys(before),...Object.keys(after)])) if (!handled.has(key) && !equal(before[key],after[key])) fail('changed schema constraint: ' + key);
    return issues;
}
export function compatibilityBreaks(before, after) {
    const issues = [];
    for (const [path, item] of Object.entries(before.paths)) {
        const old = item.post, next = after.paths[path]?.post;
        if (!next) { issues.push(path + ': operation removed'); continue; }
        if (old.operationId !== next.operationId || !equal(old.security,next.security)) issues.push(path + ': identity/security changed');
        issues.push(...schemaBreaks(old.requestBody.content['application/json'].schema,next.requestBody?.content?.['application/json']?.schema,'request',path + '.request'));
        for (const [status,response] of Object.entries(old.responses)) {
            const newer = next.responses?.[status];
            if (!newer) { issues.push(path + ': response removed: ' + status); continue; }
            if (!equal(response.headers,newer.headers)) issues.push(path + ': response headers changed: ' + status);
            for (const [mime,body] of Object.entries(response.content ?? {})) issues.push(...schemaBreaks(body.schema,newer.content?.[mime]?.schema,'response',path + '.' + status + '.' + mime));
        }
    }
    for (const [name, schema] of Object.entries(before.components?.schemas ?? {}))
        issues.push(...schemaBreaks(schema, after.components?.schemas?.[name], name.endsWith('.Input') || name === 'ArtifactInput' ? 'request' : 'response', '#/components/schemas/' + name));
    for (const key of ['x-oauth-resource','x-oauth-issuer','x-data-profile']) if (!equal(before[key],after[key])) issues.push(key + ': binding changed');
    for (const [name, scheme] of Object.entries(before.components?.securitySchemes ?? {})) {
        const next = structuredClone(after.components?.securitySchemes?.[name]);
        // Advertising an additional optional OAuth scope does not change any
        // existing operation's exact security requirement (checked above).
        if (scheme.type === 'oauth2' && next?.type === 'oauth2') {
            for (const [flow, definition] of Object.entries(scheme.flows ?? {})) {
                const scopes = next.flows?.[flow]?.scopes;
                if (scopes) next.flows[flow].scopes = Object.fromEntries(
                    Object.keys(definition.scopes ?? {}).filter(scope => Object.hasOwn(scopes,scope)).map(scope => [scope,scopes[scope]]));
            }
        }
        if (!equal(scheme,next)) issues.push('security scheme changed: ' + name);
    }
    return issues;
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
    await restoreApiArchive();
    const baseline = JSON.parse(fs.readFileSync(new URL('../api-release-baseline.json', import.meta.url)));
    if (!['released', 'approved-initial'].includes(baseline.state)) throw new Error('No published API baseline exists. Initial baseline approval is a publication gate; do not mark compatibility with a released contract as verified.');
    if (!baseline.contracts.length) throw new Error('Baseline must seal all approved projections.');
    const issues = baseline.contracts.flatMap(c => {
        const previous = c.openapi ?? JSON.parse(fs.readFileSync(new URL('../contracts/api-v1/' + c.snapshot, import.meta.url)));
        const current = JSON.parse(fs.readFileSync(new URL('../contracts/api-v1/' + c.file, import.meta.url)));
        if (baseline.state === 'approved-initial' && !equal(previous, current)) return [c.file + ': approved initial projection changed'];
        return compatibilityBreaks(previous, current);
    });
    if (issues.length) throw new Error(issues.join('\n'));
    console.log(baseline.state === 'released' ? 'API released baseline compatible.' : 'API initial projections match explicit publication approval; no prior released baseline exists.');
}
