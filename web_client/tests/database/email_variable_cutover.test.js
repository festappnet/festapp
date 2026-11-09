import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import pg from 'pg';
import { randomUUID } from 'node:crypto';
import { assertLocalDatabaseUrl, assertDisposableDatabase } from './disposable_database.js';

const url = process.env.DATABASE_URL;
const migration = await fs.readFile(new URL('../../../supabase/migrations/20261109160000_canonical_email_variables.sql', import.meta.url), 'utf8');

test('canonical variable cutover preserves custom sources, scopes and history and permanently rejects the retired format', { skip: !url }, async () => {
    assertLocalDatabaseUrl(url);
    const db = new pg.Client({ connectionString: url });
    await db.connect();
    try {
        await assertDisposableDatabase(db);
        await db.query("BEGIN; SET LOCAL statement_timeout='30s'; SET LOCAL lock_timeout='10s'");
        for (const [table, name] of [
            ['email_templates', 'email_templates_canonical_variables'],
            ['email_wrappers', 'email_wrappers_canonical_variables'],
            ['occasion_setup_drafts', 'occasion_setup_drafts_canonical_email_variables'],
        ]) await db.query(`ALTER TABLE public.${table} DROP CONSTRAINT IF EXISTS ${name}`);
        const organization = (await db.query("INSERT INTO public.organizations(title) VALUES('Převod šablon') RETURNING id")).rows[0].id;
        const unit = (await db.query("INSERT INTO public.units(title,organization) VALUES('Pořadatel',$1) RETURNING id", [organization])).rows[0].id;
        const occasion = (await db.query("INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('Slavnost',$1,$2,$3,now(),now()+interval '1 day') RETURNING id", [organization, unit, randomUUID()])).rows[0].id;
        const author = (await db.query('SELECT id FROM auth.users LIMIT 1')).rows[0]?.id;
        assert.ok(author, 'Bootstrap must provide a synthetic account');
        const code = `CUTOVER_${randomUUID().replaceAll('-', '')}`;
        const subject = 'Vlastní {{order_symbol}} - {{ occasion_title }}';
        const html = '<p style="color:red">Vlastní text: {{order_symbol}} / {{orderSymbol}}; {{\noccasion_title\t}}.</p><!-- order_symbol outside a placeholder -->';
        const expectedSubject = 'Vlastní {{orderSymbol}} - {{occasionTitle}}';
        const expectedHtml = '<p style="color:red">Vlastní text: {{orderSymbol}} / {{orderSymbol}}; {{occasionTitle}}.</p><!-- order_symbol outside a placeholder -->';
        const scopes = [[null, null, null], [organization, null, null], [organization, unit, null], [organization, unit, occasion]];
        const ids = [];
        for (const scope of scopes) ids.push((await db.query(
            'INSERT INTO public.email_templates(code,title,subject,html,organization,unit,occasion) VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING id',
            [code, 'Vlastní název', subject, html, ...scope],
        )).rows[0].id);
        const wrapper = (await db.query("INSERT INTO public.email_wrappers(title,organization,unit,occasion,html) VALUES('Vlastní obálka',$1,$2,$3,$4) RETURNING id,created_at", [organization, unit, occasion, '<main>{{occasion_title}} {{content}}</main>'])).rows[0];
        const draftId = randomUUID();
        const data = { title: '{{order_symbol}} is event data, not a template', emailTemplateOverrides: { TICKET_ORDER_CONFIRMATION: { subject, html } }, arbitrary: { note: 'Beze změny' } };
        await db.query('INSERT INTO public.occasion_setup_drafts(id,unit,organization,author,data,revision) VALUES($1,$2,$3,$4,$5,7)', [draftId, unit, organization, author, data]);
        const historicalTables = ['email_messages', 'client_mutation_receipts', 'email_confirmation_receipts'];
        const history = async () => {
            const result = {};
            for (const table of historicalTables) result[table] = (await db.query(`SELECT md5(coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text)::text,'[]')) digest FROM public.${table} t`)).rows[0].digest;
            return result;
        };
        const before = await history();
        // A migration cannot silently continue while sending is enabled.
        await db.query('UPDATE public.email_capacity SET paused=false');
        await db.query('SAVEPOINT unsafe');
        await assert.rejects(db.query(migration), /Pause and drain/);
        await db.query('ROLLBACK TO SAVEPOINT unsafe');
        await db.query('UPDATE public.email_capacity SET paused=true');
        await db.query(migration);
        const rows = (await db.query('SELECT id,title,subject,html,organization,unit,occasion FROM public.email_templates WHERE id=ANY($1::bigint[]) ORDER BY id', [ids])).rows;
        assert.equal(rows.length, 4);
        rows.forEach((row, i) => {
            assert.equal(row.subject, expectedSubject);
            assert.equal(row.html, expectedHtml);
            assert.equal(row.title, 'Vlastní název');
            assert.deepEqual([row.organization, row.unit, row.occasion], scopes[i].map(v => v === null ? null : String(v)));
        });
        const savedWrapper = (await db.query('SELECT html,created_at FROM public.email_wrappers WHERE id=$1', [wrapper.id])).rows[0];
        assert.equal(savedWrapper.html, '<main>{{occasionTitle}} {{content}}</main>');
        assert.deepEqual(savedWrapper.created_at, wrapper.created_at);
        const saved = (await db.query('SELECT data,revision FROM public.occasion_setup_drafts WHERE id=$1', [draftId])).rows[0];
        assert.equal(Number(saved.revision), 8);
        assert.deepEqual(saved.data, { ...data, emailTemplateOverrides: { TICKET_ORDER_CONFIRMATION: { subject: expectedSubject, html: expectedHtml } } });
        assert.deepEqual(await history(), before);
        // Reapplying the exact migration is a no-op for content and optimistic versions.
        await db.query(migration);
        assert.equal(Number((await db.query('SELECT revision FROM public.occasion_setup_drafts WHERE id=$1', [draftId])).rows[0].revision), 8);
        for (const [statement, parameters] of [
            ['UPDATE public.email_templates SET subject=$1 WHERE id=$2', ['{{order_symbol}}', ids[0]]],
            ['UPDATE public.email_templates SET html=$1 WHERE id=$2', ['{{ occasion_title }}', ids[0]]],
            ['UPDATE public.email_wrappers SET html=$1 WHERE id=$2', ['{{order_symbol}}', wrapper.id]],
            ["UPDATE public.occasion_setup_drafts SET data=jsonb_set(data,'{emailTemplateOverrides,TICKET_ORDER_CONFIRMATION,subject}',to_jsonb($1::text)) WHERE id=$2", ['{{occasion_title}}', draftId]],
        ]) {
            await db.query('SAVEPOINT legacy_write');
            await assert.rejects(db.query(statement, parameters), error => error.code === '23514');
            await db.query('ROLLBACK TO SAVEPOINT legacy_write');
        }
        const leftovers = (await db.query("SELECT count(*)::int n FROM public.email_templates WHERE NOT public.email_template_variables_are_canonical(subject) OR NOT public.email_template_variables_are_canonical(html)")).rows[0].n;
        assert.equal(leftovers, 0);
        assert.equal((await db.query("SELECT count(*)::int n FROM pg_proc WHERE proname IN ('rename_email_template_variables','rename_email_template_overrides')")).rows[0].n, 0);
    } finally {
        await db.query('ROLLBACK');
        await db.end();
    }
});
