// The app-wide live scores, as SportsApp.swift's liveScores poller: today's games for what you follow, polled for as
// long as the app runs, driving the menu-bar item (tray) and notifications. Desktop app only.
import { goto } from '$app/navigation';
import { leagues, scoreboard, startOfDay, type Game } from './espn';
import { follows, isFollowingTeam, teamKey } from './follows.svelte';
import { settings } from './settings.svelte';
import { EventDetector, applies, compactScore, isQuiet, type GameEvent } from './alerts';

let games: Game[] = [];
const detector = new EventDetector();
/** Alerts held through quiet hours: the latest per game, so the morning brings current state rather than a pile. */
const held = new Map<string, { title: string; body: string }>();

const includes = (g: Game) =>
	isFollowingTeam(g.league.id, g.home.team.id) || isFollowingTeam(g.league.id, g.away.team.id) || follows.leagues.includes(g.league.id);
const gameLink = (g: Game) => `/game?league=${g.league.id}&id=${g.id}&day=${new Date(g.startDate).setHours(0, 0, 0, 0)}`;

/** Followed teams decide (any unmuted one); otherwise a followed league does. */
function shouldNotify(e: GameEvent, g: Game): boolean {
	if (!settings.alerts[e.type] || !applies(e.type, g)) return false;
	const teams = [g.home.team.id, g.away.team.id].filter((id) => isFollowingTeam(g.league.id, id));
	if (teams.length) return teams.some((id) => !settings.muted.includes(teamKey(g.league.id, id)));
	return follows.leagues.includes(g.league.id);
}

// Sent alerts, so a refresh or relaunch never repeats one; kept a week.
const sentKey = 'alertLog';
function markSent(id: string): boolean {
	let log: Record<string, number> = {};
	try {
		log = JSON.parse(localStorage.getItem(sentKey) ?? '{}');
	} catch {}
	if (log[id]) return false;
	const week = Date.now() - 7 * 86_400_000;
	log = Object.fromEntries(Object.entries(log).filter(([, t]) => t > week));
	log[id] = Date.now();
	try {
		localStorage.setItem(sentKey, JSON.stringify(log));
	} catch {
		// A failed save skips the alert rather than risking repeats every poll.
		return false;
	}
	return true;
}

async function notify(title: string, body: string) {
	const n = await import('@tauri-apps/plugin-notification');
	if (!(await n.isPermissionGranted()) && (await n.requestPermission()) !== 'granted') return;
	n.sendNotification({ title, body });
}

function process(old: Game[], fresh: Game[]) {
	const previous = new Map(old.map((g) => [g.id, g]));
	const quiet = isQuiet(new Date(), settings.quietHours.enabled, settings.quietHours.start, settings.quietHours.end);
	for (const g of fresh) {
		for (const e of detector.events(previous.get(g.id), g)) {
			if (!shouldNotify(e, g) || !markSent(`${g.id}-${e.key}`)) continue;
			const title = `${g.away.team.shortName} at ${g.home.team.shortName} · ${e.headline}`;
			if (quiet) held.set(g.id, { title, body: e.body });
			else notify(title, e.body);
		}
	}
	if (!quiet) {
		for (const { title, body } of held.values()) notify(title, body);
		held.clear();
	}
}

async function fetchToday(): Promise<Game[]> {
	const ids = new Set([...follows.leagues, ...follows.teams.map((t) => t.leagueID)]);
	const today = startOfDay(0);
	const results = await Promise.allSettled(leagues.filter((l) => ids.has(l.id)).map((l) => scoreboard(l, today)));
	if (results.length && results.every((r) => r.status === 'rejected')) throw new Error('No scores');
	const fresh = results.flatMap((r) => (r.status === 'fulfilled' ? r.value : []));
	// A game still live from before midnight stays until a poll sees it end, so its final alert still fires.
	for (const g of games.filter((g) => g.status === 'live' && g.startDate < today && !fresh.some((f) => f.id === g.id))) {
		const day = new Date(g.startDate);
		day.setHours(0, 0, 0, 0);
		fresh.push((await scoreboard(g.league, day).catch(() => [] as Game[])).find((f) => f.id === g.id) ?? g);
	}
	return fresh.sort((a, b) => a.startDate.getTime() - b.startDate.getTime());
}

// MARK: The menu-bar item.

let tray: import('@tauri-apps/api/tray').TrayIcon | undefined;

async function showWindow(path?: string) {
	const { getCurrentWindow } = await import('@tauri-apps/api/window');
	const win = getCurrentWindow();
	await win.show();
	await win.unminimize();
	await win.setFocus();
	if (path) goto(path);
}

async function updateTray() {
	const { Menu } = await import('@tauri-apps/api/menu');
	const followed = games.filter(includes);
	// The pinned game is the earliest live followed one; otherwise just the icon.
	const pinned = followed.find((g) => g.status === 'live');
	const shown = followed.filter((g) => g.status !== 'final');
	const nothing = follows.leagues.length === 0 && follows.teams.length === 0;
	const items = [
		{ text: 'Today', enabled: false },
		...(nothing
			? [{ text: 'Nothing followed yet', enabled: false }]
			: shown.length === 0
				? [{ text: 'No live or upcoming games', enabled: false }]
				: shown.map((g) => ({
						text: g.status === 'live' ? compactScore(g) : `${g.away.team.abbreviation} @ ${g.home.team.abbreviation} · ${g.startDate.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}`,
						action: () => showWindow(gameLink(g))
					}))),
		{ item: 'Separator' as const },
		{ text: 'Open Halftime', action: () => showWindow() },
		{ text: 'Settings…', action: () => showWindow('/settings') },
		{ item: 'Separator' as const },
		{ text: 'Quit Halftime', action: async () => (await import('@tauri-apps/api/window')).getCurrentWindow().destroy() }
	];
	const menu = await Menu.new({ items });
	if (!tray) {
		const { TrayIcon } = await import('@tauri-apps/api/tray');
		// A dev reload re-runs this module; reuse the tray it made rather than adding a second.
		tray = (await TrayIcon.getById('halftime')) ?? undefined;
	}
	if (!tray) {
		const { TrayIcon } = await import('@tauri-apps/api/tray');
		const { defaultWindowIcon } = await import('@tauri-apps/api/app');
		// shortcut: uses the app icon; a monochrome template image (like the Swift sports-court symbol) would sit better in the menu bar.
		tray = await TrayIcon.new({ id: 'halftime', icon: (await defaultWindowIcon()) ?? undefined, menu, showMenuOnLeftClick: true, tooltip: 'Halftime' });
	} else {
		await tray.setMenu(menu);
	}
	// macOS shows the title beside the icon; Windows has no tray text, so the score goes in the hover tooltip there.
	await tray.setTitle(pinned ? compactScore(pinned) : null);
	await tray.setTooltip(pinned ? compactScore(pinned) : 'Halftime');
}

/** Starts polling, the tray and Close to Menu; call once, in the desktop app. */
export async function startLive() {
	// Once per app run, even across dev reloads of this module.
	const w = window as unknown as { halftimeLive?: boolean };
	if (w.halftimeLive) return;
	w.halftimeLive = true;
	const { getCurrentWindow } = await import('@tauri-apps/api/window');
	getCurrentWindow().onCloseRequested((e) => {
		if (!settings.closeToMenu) return;
		e.preventDefault();
		getCurrentWindow().hide();
	});
	// Covers follows made before alerts existed; the system only asks once.
	if (follows.leagues.length || follows.teams.length) {
		import('@tauri-apps/plugin-notification').then(async (n) => {
			if (!(await n.isPermissionGranted())) await n.requestPermission();
		});
	}

	let failures = 0;
	const tick = async () => {
		try {
			const fresh = await fetchToday();
			const old = games;
			games = fresh;
			process(old, fresh);
			failures = 0;
		} catch {
			failures++;
		}
		await updateTray().catch((e) => console.error('Menu-bar item failed:', e));
		// 15 s while anything followed is live or to come today, a minute otherwise; backs off after errors (capped at 2 min).
		const busy = games.some((g) => includes(g) && g.status !== 'final');
		setTimeout(tick, failures ? Math.min(15_000 * 2 ** (failures - 1), 120_000) : busy ? 15_000 : 60_000);
	};
	tick();
}

/** Re-reads follows at once, so the tray and polling pick up a new star without waiting for the next poll. */
export const refreshLive = () => updateTray().catch((e) => console.error('Menu-bar item failed:', e));
