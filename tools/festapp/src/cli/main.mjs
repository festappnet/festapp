#!/usr/bin/env node
import { readFile } from 'node:fs/promises';
import { profileFromTenant } from '../context/tenant-profile.mjs';
import { createInterface } from 'node:readline/promises';
import { loadProfile, importProfile } from '../context/profile.mjs';
import { SessionOwner } from '../auth/session.mjs';
import { Operations } from '../operations/catalog.mjs';
import { safeError, check } from '../errors.mjs';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { createServer } from '../mcp/server.mjs';
async function hiddenPassword() {
    check(
        process.stdin.isTTY && process.stderr.isTTY,
        'INTERACTIVE_LOGIN_REQUIRED',
    );
    process.stderr.write('Password: ');
    process.stdin.setRawMode(true);
    process.stdin.resume();
    try {
        return await new Promise((resolve, reject) => {
            let password = '';
            const listener = (chunk) => {
                for (const char of chunk.toString()) {
                    if (char === '\u0003') {
                        process.stdin.off('data', listener);
                        reject(new Error('cancelled'));
                        return;
                    }
                    if (char === '\r' || char === '\n') {
                        process.stdin.off('data', listener);
                        resolve(password);
                        return;
                    }
                    if (char === '\u007f' || char === '\b')
                        password = password.slice(0, -1);
                    else if (char >= ' ') password += char;
                }
            };
            process.stdin.on('data', listener);
        });
    } finally {
        process.stdin.setRawMode(false);
        process.stdin.pause();
        process.stderr.write('\n');
    }
}
try {
    const args = process.argv.slice(2);
    if (
        args[0] === 'profile' &&
        args[1] === 'from-tenant' &&
        args.length === 5 &&
        args[3] === '--name'
    ) {
        process.stdout.write(
            JSON.stringify(
                profileFromTenant(await readFile(args[2], 'utf8'), args[4]),
                null,
                2,
            ) + '\n',
        );
    } else if (
        args[0] === 'profile' &&
        args[1] === 'import' &&
        args.length === 3
    ) {
        const p = await importProfile(args[2]);
        process.stdout.write(
            JSON.stringify({ ok: true, profile: p.name }) + '\n',
        );
    } else {
        const option = args.indexOf('--profile');
        check(
            option >= 0 && option === args.length - 2,
            'EXPLICIT_PROFILE_REQUIRED',
        );
        const profile = await loadProfile(args[option + 1]);
        const owner = new SessionOwner(profile);
        const operations = new Operations(owner);
        const command = args.slice(0, option).join(' ');
        if (command === 'mcp serve') {
            await operations.prepare();
            const server = createServer(operations);
            await server.connect(new StdioServerTransport());
        } else if (command === 'auth login') {
            check(process.stdin.isTTY, 'INTERACTIVE_LOGIN_REQUIRED');
            const terminal = createInterface({
                input: process.stdin,
                output: process.stderr,
            });
            const email = await terminal.question('Email: ');
            terminal.close();
            const result = await owner.login(email, await hiddenPassword());
            process.stdout.write(
                JSON.stringify({ ok: true, ...result }) + '\n',
            );
        } else if (command === 'auth logout') {
            await owner.logout();
            process.stdout.write('{"ok":true}\n');
        } else {
            const id =
                command === 'context inspect'
                    ? 'context.inspect'
                    : command === 'ticket-layouts inspect'
                      ? 'ticket_layouts.inspect'
                      : command === 'ticket-layouts preview'
                        ? 'ticket_layouts.preview'
                        : command === 'ticket-layouts save'
                          ? 'ticket_layouts.save'
                          : command === 'ticket-layouts pending'
                            ? 'ticket_layouts.pending'
                            : command === 'ticket-layouts resume'
                              ? 'ticket_layouts.resume'
                              : null;
            check(id, 'INVALID_COMMAND');
            let raw = '';
            if (id !== 'context.inspect')
                for await (const chunk of process.stdin) {
                    raw += chunk;
                    check(Buffer.byteLength(raw) <= 40000, 'INVALID_INPUT');
                }
            if (
                [
                    'context.inspect',
                    'ticket_layouts.save',
                    'ticket_layouts.pending',
                    'ticket_layouts.resume',
                ].includes(id)
            )
                await operations.prepare();
            const result = await operations.invoke(
                id,
                raw ? JSON.parse(raw) : {},
            );
            process.stdout.write(JSON.stringify(result) + '\n');
            if (!result.ok) process.exitCode = 1;
        }
    }
} catch (error) {
    process.stderr.write(
        JSON.stringify({ ok: false, error: safeError(error) }) + '\n',
    );
    process.exitCode = 1;
}
