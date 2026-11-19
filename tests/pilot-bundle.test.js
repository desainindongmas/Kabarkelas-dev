import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

// Regression: G10 pilot UI (buildPilotModules) pernah jadi dead code dan
// ter-tree-shake keluar dari bundle produksi — UI modul tidak pernah muncul.
// Test ini mem-build dan memastikan string RPC G10 ada di artefak live.
test('production bundle contains G10 pilot modules', { timeout: 180000 }, () => {
  execFileSync(process.execPath, ['node_modules/vite/bin/vite.js', 'build'], { stdio: 'pipe' });
  const dir = join(process.cwd(), 'dist', 'assets');
  const js = readdirSync(dir)
    .filter((f) => f.endsWith('.js'))
    .map((f) => readFileSync(join(dir, f), 'utf8'))
    .join('\n');
  for (const marker of [
    'kabarkelas_schedule_list',
    'kabarkelas_announce_list',
    'kabarkelas_leave_list',
    'kabarkelas_leave_request',
    'kabarkelas_homework_list',
    'kabarkelas_quiz_list',
    'kabarkelas_p5_list',
  ]) {
    assert.ok(js.includes(marker), `bundle produksi kehilangan ${marker} — kemungkinan dead code ter-tree-shake`);
  }
});
