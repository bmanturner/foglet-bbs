#!/usr/bin/env node
// FOG-256 (C8) — Multi-session SSH/TUI harness suite.
//
// Runs all nine FOG-256 scenarios end-to-end against a running Foglet SSH
// daemon. Prereqs (see the C8 QA report on FOG-256 for the full prep recipe):
//
//   1. Postgres reachable, foglet_bbs_dev migrated.
//   2. `mix run priv/repo/seeds.exs && mix run priv/repo/seeds/c8_qa_boards.exs`
//      to insert the QA category, the qa-no-chat / qa-perm-chat / qa-eph-chat
//      boards, and the qa1 / qa2 users (password: qapassword123!).
//   3. `FOGLET_SSH_PORT=2230 mix phx.server` running.
//
// Then:
//
//   node tools/qa/c8-suite.mjs --port 2230
//
// Pass `--scenarios 1,2,5` to run a subset. The script prints a per-scenario
// PASS / FAIL summary, the raw screens captured for the multi-session
// scenarios, and exits non-zero if any scenario fails.

import { Session, chatCount, hasTabStrip, hasEphemeralNotice } from './multi-session.mjs';

const argv = process.argv.slice(2);
const opts = { port: 2222, host: '127.0.0.1', scenarios: null, ephemeralWaitMs: 75_000 };
for (let i = 0; i < argv.length; i += 1) {
  if (argv[i] === '--port') opts.port = Number.parseInt(argv[++i], 10);
  else if (argv[i] === '--host') opts.host = argv[++i];
  else if (argv[i] === '--scenarios') opts.scenarios = argv[++i].split(',').map(s => Number.parseInt(s.trim(), 10));
  else if (argv[i] === '--eph-wait-ms') opts.ephemeralWaitMs = Number.parseInt(argv[++i], 10);
  else if (argv[i] === '--help' || argv[i] === '-h') {
    console.log('usage: node tools/qa/c8-suite.mjs [--port N] [--host H] [--scenarios 1,2,3] [--eph-wait-ms 75000]');
    process.exit(0);
  } else throw new Error(`unknown arg: ${argv[i]}`);
}

const QA1 = { username: 'qa1', password: 'qapassword123!' };
const QA2 = { username: 'qa2', password: 'qapassword123!' };
const NO_CHAT_BOARD = 'QA No Chat';
const PERM_BOARD = 'QA Perm Chat';
const EPH_BOARD = 'QA Eph Chat';

const results = [];
const sessions = [];

function newSession(name, creds, { width = 100, height = 30 } = {}) {
  const s = new Session({
    name,
    host: opts.host,
    port: opts.port,
    username: creds.username,
    password: creds.password,
    width,
    height,
    readyMs: 350
  });
  sessions.push(s);
  return s;
}

function record(num, title, status, notes, screens = {}) {
  results.push({ num, title, status, notes, screens });
  const tag = status === 'PASS' ? '✅ PASS' : status === 'FAIL' ? '❌ FAIL' : '⚠️ SKIP';
  console.log(`\n[${num}] ${tag} — ${title}\n     ${notes}`);
}

async function safeRun(num, title, fn) {
  if (opts.scenarios && !opts.scenarios.includes(num)) {
    record(num, title, 'SKIP', 'not selected via --scenarios');
    return;
  }
  try {
    await fn();
  } catch (err) {
    record(num, title, 'FAIL', `threw: ${err.message}`);
  }
}

async function main() {
  console.log(`# FOG-256 C8 Multi-Session SSH/TUI Harness Suite`);
  console.log(`# host=${opts.host} port=${opts.port}\n`);

  // ---- Scenario 1: Disabled-chat board preserves current behavior. ----
  await safeRun(1, 'Disabled-chat board preserves current behavior', async () => {
    const s = newSession('s1.qa1', QA1);
    await s.open();
    await s.login(QA1.username, QA1.password);
    await s.openBoardByName(NO_CHAT_BOARD);
    const screen = s.screen();
    const tabPresent = hasTabStrip(screen);
    if (tabPresent) {
      record(1, 'Disabled-chat board preserves current behavior', 'FAIL',
        'tab strip rendered on a chat-disabled board (regression)', { board: screen });
    } else if (!/Foglet ▸ QA No Chat/.test(screen)) {
      record(1, '...', 'FAIL', 'did not land on QA No Chat screen', { board: screen });
    } else {
      record(1, 'Disabled-chat board preserves current behavior', 'PASS',
        'no tab strip; thread list renders standalone', { board: screen });
    }
    await s.close();
  });

  // ---- Scenario 2: Enabled-chat board shows tabs, count = 1. ----
  await safeRun(2, 'Enabled-chat board shows tabs, count = 1', async () => {
    const s = newSession('s2.qa1', QA1);
    await s.open();
    await s.login(QA1.username, QA1.password);
    await s.openBoardByName(PERM_BOARD);
    const screen = s.screen();
    const count = chatCount(screen);
    if (!hasTabStrip(screen)) {
      record(2, '...', 'FAIL', 'tab strip missing on chat-enabled board', { board: screen });
    } else if (count !== 1) {
      record(2, '...', 'FAIL', `expected CHAT count 1, got ${count}`, { board: screen });
    } else {
      record(2, 'Enabled-chat board shows tabs, count = 1', 'PASS',
        'THREADS / CHAT (1) tab strip present', { board: screen });
    }
    await s.close();
  });

  // ---- Scenario 3: Two-session presence (count rises to 2, falls to 1). ----
  let scenario3SessionA, scenario3SessionB;
  await safeRun(3, 'Two-session presence rises to 2, falls to 1 on leave', async () => {
    const a = newSession('s3.qa1', QA1);
    const b = newSession('s3.qa2', QA2);
    scenario3SessionA = a; scenario3SessionB = b;
    await Promise.all([a.open(), b.open()]);
    await a.login(QA1.username, QA1.password);
    await b.login(QA2.username, QA2.password);
    await a.openBoardByName(PERM_BOARD);
    await b.openBoardByName(PERM_BOARD);
    // Allow PubSub presence broadcast.
    await Promise.all([
      a.waitFor(s => chatCount(s) === 2, { timeoutMs: 5000 }),
      b.waitFor(s => chatCount(s) === 2, { timeoutMs: 5000 })
    ]).catch(() => {});
    const aScr1 = a.screen(); const bScr1 = b.screen();
    const aCount1 = chatCount(aScr1); const bCount1 = chatCount(bScr1);
    if (aCount1 !== 2 || bCount1 !== 2) {
      record(3, '...', 'FAIL',
        `both sessions should see CHAT (2); got a=${aCount1} b=${bCount1}`,
        { sessionA_joined: aScr1, sessionB_joined: bScr1 });
      return;
    }
    // B leaves the board screen.
    await b.leaveBoard();
    await a.waitFor(s => chatCount(s) === 1, { timeoutMs: 5000 }).catch(() => {});
    const aScr2 = a.screen();
    const aCount2 = chatCount(aScr2);
    if (aCount2 !== 1) {
      record(3, '...', 'FAIL',
        `after B leaves, A should see CHAT (1); got ${aCount2}`,
        { sessionA_joined: aScr1, sessionB_joined: bScr1, sessionA_after_b_left: aScr2 });
      return;
    }
    record(3, 'Two-session presence rises to 2, falls to 1 on leave', 'PASS',
      'count tracks board-screen presence in both directions',
      { sessionA_joined: aScr1, sessionB_joined: bScr1, sessionA_after_b_left: aScr2 });
  });

  // ---- Scenario 4: Tab presence is board-screen-scoped (switching tabs does not change other session's count). ----
  await safeRun(4, 'Tab switching does not change other session count', async () => {
    // Reuse session A from scenario 3 if still alive; otherwise re-open.
    let a = scenario3SessionA;
    let b = scenario3SessionB;
    let createdHere = false;
    if (!a || !a.stream || a.stream.destroyed || !b || !b.stream || b.stream.destroyed) {
      a = newSession('s4.qa1', QA1);
      b = newSession('s4.qa2', QA2);
      createdHere = true;
      await Promise.all([a.open(), b.open()]);
      await a.login(QA1.username, QA1.password);
      await b.login(QA2.username, QA2.password);
      await a.openBoardByName(PERM_BOARD);
      await b.openBoardByName(PERM_BOARD);
      await a.waitFor(s => chatCount(s) === 2, { timeoutMs: 5000 }).catch(() => {});
    } else {
      // From scenario 3, B is back on Boards. Re-enter PERM_BOARD on B.
      await b.openBoardByName(PERM_BOARD);
      await a.waitFor(s => chatCount(s) === 2, { timeoutMs: 5000 }).catch(() => {});
    }
    const beforeB = chatCount(b.screen());
    // A switches tab THREADS -> CHAT.
    await a.type('2');
    await a.wait(600);
    // A switches back to THREADS.
    await a.type('1');
    await a.wait(600);
    const afterB = chatCount(b.screen());
    if (beforeB !== 2 || afterB !== 2) {
      record(4, '...', 'FAIL',
        `B's CHAT count must stay at 2 across A's tab switches; got before=${beforeB} after=${afterB}`,
        { sessionB_after_a_tab_toggle: b.screen() });
    } else {
      record(4, 'Tab switching does not change other session count', 'PASS',
        'B\'s CHAT (2) is unchanged while A toggles tabs',
        { sessionB_after_a_tab_toggle: b.screen() });
    }
    if (createdHere) { await a.close(); await b.close(); }
  });

  // ---- Scenario 5: Send + receive (A on CHAT sends, B on CHAT sees within budget). ----
  await safeRun(5, 'Send + receive within broadcast latency budget', async () => {
    const a = newSession('s5.qa1', QA1);
    const b = newSession('s5.qa2', QA2);
    await Promise.all([a.open(), b.open()]);
    await a.login(QA1.username, QA1.password);
    await b.login(QA2.username, QA2.password);
    await a.openBoardByName(PERM_BOARD);
    await b.openBoardByName(PERM_BOARD);
    await a.type('2'); await a.wait(400);
    await b.type('2'); await b.wait(400);
    const marker = `c8s5-${Date.now().toString(36).replace(/q/g, 'z')}`;
    await a.type(`hi ${marker}`);
    await a.key('enter');
    const start = Date.now();
    let bSawIt = false;
    try {
      await b.waitFor(s => s.includes(marker), { timeoutMs: 3000, pollMs: 100 });
      bSawIt = true;
    } catch {}
    const latencyMs = Date.now() - start;
    if (!bSawIt) {
      record(5, '...', 'FAIL',
        `B did not see message "${marker}" within 3000ms`,
        { sessionA_after_send: a.screen(), sessionB_observed: b.screen() });
    } else {
      record(5, 'Send + receive within broadcast latency budget', 'PASS',
        `B observed message in ~${latencyMs}ms (marker=${marker})`,
        { sessionA_after_send: a.screen(), sessionB_observed: b.screen() });
    }
    await a.close(); await b.close();
  });

  // ---- Scenario 6: Permanent reload (recent ≤100 history reloads on re-enter). ----
  await safeRun(6, 'Permanent board reload preserves recent history', async () => {
    const a = newSession('s6.qa1', QA1);
    await a.open();
    await a.login(QA1.username, QA1.password);
    await a.openBoardByName(PERM_BOARD);
    await a.type('2'); await a.wait(400);
    const marker = `c8s6-${Date.now().toString(36).replace(/q/g, 'z')}`;
    await a.type(`reload ${marker}`);
    await a.key('enter');
    await a.wait(800);
    // Leave the board screen.
    await a.type('1'); await a.wait(300); // back to THREADS tab
    await a.type('Q'); await a.wait(600); // back to Boards
    // Re-enter and switch to CHAT.
    await a.openBoardByName(PERM_BOARD);
    await a.type('2'); await a.wait(800);
    const screen = a.screen();
    if (!screen.includes(marker)) {
      record(6, '...', 'FAIL',
        `re-entered chat did not show prior message marker ${marker}`,
        { afterReload: screen });
    } else {
      record(6, 'Permanent board reload preserves recent history', 'PASS',
        `marker ${marker} present in recent history after re-entry`,
        { afterReload: screen });
    }
    await a.close();
  });

  // ---- Scenario 7: Ephemeral expiry (TTL=60s seed; messages disappear from `recent` and DB). ----
  await safeRun(7, 'Ephemeral expiry — messages drop from recent past TTL', async () => {
    const a = newSession('s7.qa1', QA1);
    await a.open();
    await a.login(QA1.username, QA1.password);
    await a.openBoardByName(EPH_BOARD);
    await a.type('2'); await a.wait(400);
    const marker = `c8s7-${Date.now().toString(36).replace(/q/g, 'z')}`;
    await a.type(`bye ${marker}`);
    await a.key('enter');
    await a.wait(800);
    const sentScreen = a.screen();
    if (!sentScreen.includes(marker)) {
      record(7, '...', 'FAIL',
        'message did not appear in own session after send',
        { afterSend: sentScreen });
      await a.close();
      return;
    }
    console.log(`     [scenario 7] waiting ${opts.ephemeralWaitMs}ms for TTL expiry...`);
    await a.wait(opts.ephemeralWaitMs);
    // Force fresh history pull: leave and re-enter chat.
    await a.type('1'); await a.wait(400);
    await a.type('Q'); await a.wait(600);
    await a.openBoardByName(EPH_BOARD);
    await a.type('2'); await a.wait(800);
    const reentered = a.screen();
    if (reentered.includes(marker)) {
      record(7, '...', 'FAIL',
        `marker ${marker} still present after TTL expiry + re-enter (should have been swept)`,
        { afterSend: sentScreen, afterTtlReentry: reentered });
    } else {
      record(7, 'Ephemeral expiry — messages drop from recent past TTL', 'PASS',
        `marker ${marker} swept from recent after ${opts.ephemeralWaitMs}ms wait`,
        { afterSend: sentScreen, afterTtlReentry: reentered });
    }
    await a.close();
  });

  // ---- Scenario 8: Ephemeral notice present on ephemeral, absent on permanent. ----
  await safeRun(8, 'Ephemeral notice gating', async () => {
    const a = newSession('s8.qa1', QA1);
    await a.open();
    await a.login(QA1.username, QA1.password);
    await a.openBoardByName(EPH_BOARD);
    await a.type('2'); await a.wait(500);
    const ephScreen = a.screen();
    const ephHas = hasEphemeralNotice(ephScreen);
    await a.type('Q'); await a.wait(500);
    await a.openBoardByName(PERM_BOARD);
    await a.type('2'); await a.wait(500);
    const permScreen = a.screen();
    const permHas = hasEphemeralNotice(permScreen);
    if (!ephHas) {
      record(8, '...', 'FAIL',
        'ephemeral notice missing on chat-enabled ephemeral board',
        { ephChat: ephScreen, permChat: permScreen });
    } else if (permHas) {
      record(8, '...', 'FAIL',
        'ephemeral notice incorrectly rendered on permanent board',
        { ephChat: ephScreen, permChat: permScreen });
    } else {
      record(8, 'Ephemeral notice gating', 'PASS',
        'notice present on ephemeral board, absent on permanent board',
        { ephChat: ephScreen, permChat: permScreen });
    }
    await a.close();
  });

  // ---- Scenario 9: Sidebar collapse at narrow widths + toggle keybinding. ----
  await safeRun(9, 'Sidebar collapse + toggle keybinding', async () => {
    const a = newSession('s9.qa1', QA1, { width: 100 });
    await a.open();
    await a.login(QA1.username, QA1.password);
    await a.openBoardByName(PERM_BOARD);
    await a.type('2'); await a.wait(500);
    const wide = a.screen();
    const wideHasSidebar = /Online\b/.test(wide);
    // Toggle hide via Ctrl+B.
    await a.key('ctrl-b'); await a.wait(500);
    const wideToggled = a.screen();
    const toggledHidesSidebar = !/Online\b/.test(wideToggled);
    // Re-show, then resize narrow to confirm auto-collapse.
    await a.key('ctrl-b'); await a.wait(400);
    await a.resize(60, 30);
    await a.wait(500);
    const narrow = a.screen();
    const narrowHidesSidebar = !/Online\b/.test(narrow);

    const checks = [
      ['wide-shows-sidebar', wideHasSidebar],
      ['ctrl-b hides sidebar', toggledHidesSidebar],
      ['narrow auto-collapses sidebar', narrowHidesSidebar]
    ];
    const failed = checks.filter(([, ok]) => !ok).map(([n]) => n);
    if (failed.length === 0) {
      record(9, 'Sidebar collapse + toggle keybinding', 'PASS',
        'all three sidebar visibility checks held', { wide, wideToggled, narrow });
    } else {
      record(9, '...', 'FAIL', `failed checks: ${failed.join(', ')}`, { wide, wideToggled, narrow });
    }
    await a.close();
  });

  // ---- Report ----
  for (const s of sessions) { try { await s.close(); } catch {} }

  console.log('\n\n================ FOG-256 C8 SUITE SUMMARY ================');
  for (const r of results) {
    console.log(`[${r.num}] ${r.status}  ${r.title}`);
    console.log(`      ${r.notes}`);
  }
  const failed = results.filter(r => r.status === 'FAIL');
  console.log(`\n${results.length - failed.length}/${results.length} scenarios passed.\n`);

  // Emit raw screen captures for the multi-session scenarios so the QA report
  // can quote them directly.
  for (const r of results) {
    const screens = Object.entries(r.screens || {});
    if (screens.length === 0) continue;
    console.log(`\n--- raw screens, scenario ${r.num} ---`);
    for (const [label, body] of screens) {
      console.log(`# ${label}`);
      console.log(body);
      console.log('');
    }
  }

  process.exit(failed.length === 0 ? 0 : 1);
}

main().catch(err => {
  console.error(`c8 suite crashed: ${err.stack || err.message}`);
  for (const s of sessions) { try { s.close(); } catch {} }
  process.exit(2);
});
