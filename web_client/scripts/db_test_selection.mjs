import path from 'node:path';

// Match repository paths, never a checkout/worktree directory's name.
export function selectSqlTests(files, filters, root) {
    const normalized = filters.map(filter => path.isAbsolute(filter)
        ? path.relative(root, filter) : filter);
    return files.filter(file => normalized.length === 0 ||
        normalized.some(filter => path.relative(root, file).includes(filter)));
}
