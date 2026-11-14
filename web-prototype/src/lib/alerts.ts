// Ported from SportsKit's GameEventDetector, NotificationRules and QuietHours: turns two snapshots of a game into
// alert-worthy events, decides which to send, and holds them through quiet hours.
import type { Game, League } from './espn';

export type EventType = 'gameStart' | 'scoreUpdate' | 'periodEnd' | 'halftime' | 'final' | 'redZone' | 'closeGame' | 'overtime' | 'leadChange';
export type GameEvent = { type: EventType; key: string; headline: string; body: string };

export const events: { type: EventType; title: string; onByDefault: boolean }[] = [
	{ type: 'gameStart', title: 'Game start', onByDefault: true },
	{ type: 'scoreUpdate', title: 'Score updates', onByDefault: true },
	{ type: 'periodEnd', title: 'Period end', onByDefault: false },
	{ type: 'halftime', title: 'Halftime', onByDefault: false },
	{ type: 'final', title: 'Final score', onByDefault: true },
	{ type: 'redZone', title: 'Red zone', onByDefault: false },
	{ type: 'closeGame', title: 'Close game, final minutes', onByDefault: false },
	{ type: 'overtime', title: 'Overtime', onByDefault: true },
	{ type: 'leadChange', title: 'Lead changes', onByDefault: false }
];

/** Innings and halves would spam or duplicate halftime; red zone is football only. */
export function applies(type: EventType, l: League): boolean {
	switch (type) {
		case 'redZone': return l.sport === 'football';
		case 'closeGame': return l.sport !== 'soccer' && l.sport !== 'baseball';
		case 'periodEnd': return l.periodStyle === 'quarters' || l.periodStyle === 'periods';
		case 'halftime': return l.periodStyle === 'quarters' || l.periodStyle === 'halves';
		default: return true;
	}
}

/** Where a league's or followed team's own alert setting is kept, as NotificationPreference's scopes. */
export const scopePrefix = (leagueID: string, teamID?: string) => (teamID ? `team/${leagueID}:${teamID}/` : `league/${leagueID}/`);

/** The setting in effect: the team's own, else its league's, else the one for everything (NotificationRules.resolved). */
export function resolvedAlert(s: { alerts: Record<EventType, boolean>; overrides: Record<string, boolean> }, type: EventType, leagueID: string, teamID?: string): boolean {
	return (teamID ? s.overrides[scopePrefix(leagueID, teamID) + type] : undefined) ?? s.overrides[scopePrefix(leagueID) + type] ?? s.alerts[type];
}

/** e.g. "WSH 3 – 27 SF · 7:25 - 3rd" */
export const scoreLine = (g: Game) => `${g.away.team.abbreviation} ${g.away.score ?? 0} – ${g.home.score ?? 0} ${g.home.team.abbreviation} · ${g.statusDetail}`;

/** Short period for the menu bar: "Q3", "P2", "OT", "Half", or ESPN's text where it says more ("67'"). */
export function compactPeriod(g: Game): string {
	if (g.statusName === 'STATUS_HALFTIME') return 'Half';
	const l = g.league;
	if (l.sport === 'soccer' || l.periodStyle === 'innings') return g.statusDetail;
	if (g.period > l.regulationPeriods) {
		const ot = g.period - l.regulationPeriods;
		return ot === 1 ? 'OT' : `${ot}OT`;
	}
	return `${l.periodStyle === 'quarters' ? 'Q' : l.periodStyle === 'halves' ? 'H' : 'P'}${g.period}`;
}

/** Menu bar text, e.g. "WSH 3 – 13 SF · Q2". */
export const compactScore = (g: Game) => `${g.away.team.abbreviation} ${g.away.score ?? 0} – ${g.home.score ?? 0} ${g.home.team.abbreviation} · ${compactPeriod(g)}`;

const closeGame: Record<string, { margin: number; seconds: number }> = {
	nfl: { margin: 8, seconds: 300 }, cfb: { margin: 8, seconds: 300 }, nba: { margin: 5, seconds: 120 }, wnba: { margin: 5, seconds: 120 }, ncaab: { margin: 5, seconds: 120 }, nhl: { margin: 1, seconds: 300 }
};

/** Within the league's margin with its last minutes left in the final regulation period or later. */
function isClose(g: Game): boolean {
	const rule = closeGame[g.league.id];
	const [m, s] = g.clock.split(':').map(Number);
	if (!rule || g.status !== 'live' || g.period < g.league.regulationPeriods || isNaN(m) || isNaN(s)) return false;
	return m * 60 + s <= rule.seconds && Math.abs((g.away.score ?? 0) - (g.home.score ?? 0)) <= rule.margin;
}

const leader = (g: Game) => {
	const a = g.away.score ?? 0, h = g.home.score ?? 0;
	return a === h ? undefined : a > h ? g.away.team : g.home.team;
};

/** Diffs consecutive snapshots of a game. Keeps a little state for red zone, which fires once per drive. */
export class EventDetector {
	private redZoneAlerted = new Map<string, string>();

	/** Pass undefined for `old` on the first sighting of a game; that only records state. */
	events(old: Game | undefined, game: Game): GameEvent[] {
		const redZone = this.redZone(game);
		if (!old) return [];
		const out: GameEvent[] = [];
		const add = (type: EventType, key: string, headline: string, body = scoreLine(game)) => out.push({ type, key, headline, body });
		const l = game.league;
		if (old.status === 'scheduled' && game.status === 'live') add('gameStart', 'start', 'Kickoff', `${game.away.team.shortName} at ${game.home.team.shortName} has started.`);
		// Not started counts as 0, so kickoff isn't a score change.
		if (game.status !== 'scheduled' && ((game.away.score ?? 0) !== (old.away.score ?? 0) || (game.home.score ?? 0) !== (old.home.score ?? 0))) {
			const score = `${game.away.score ?? 0}-${game.home.score ?? 0}`;
			add('scoreUpdate', `score-${score}`, 'Score Update');
			const before = leader(old), after = leader(game);
			if (before && after && before.id !== after.id) add('leadChange', `lead-${score}`, 'Lead Change', `${after.shortName} lead ${scoreLine(game)}`);
		}
		if (game.statusName === 'STATUS_END_PERIOD' && old.statusName !== 'STATUS_END_PERIOD') add('periodEnd', `period-${game.period}`, `End of ${periodName(game)}`);
		if (game.statusName === 'STATUS_HALFTIME' && old.statusName !== 'STATUS_HALFTIME') add('halftime', 'halftime', 'Halftime');
		if (game.status === 'live' && game.period > l.regulationPeriods && old.period <= l.regulationPeriods) add('overtime', 'overtime', 'Overtime');
		if (isClose(game) && !isClose(old)) add('closeGame', 'close', 'Close Game');
		if (game.status === 'final' && old.status !== 'final') add('final', 'final', 'Final');
		if (redZone) out.push(redZone);
		return out;
	}

	private redZone(game: Game): GameEvent | undefined {
		const s = game.situation, offense = s?.possessionTeamID;
		if (game.status !== 'live' || !s || !offense) return;
		// A new possession is a new drive, so it may alert again.
		if (this.redZoneAlerted.has(game.id) && this.redZoneAlerted.get(game.id) !== offense) this.redZoneAlerted.delete(game.id);
		if (!s.isRedZone || this.redZoneAlerted.has(game.id)) return;
		this.redZoneAlerted.set(game.id, offense);
		const team = offense === game.home.team.id ? game.home.team : game.away.team;
		const spot = s.downAndDistance ? `: ${s.downAndDistance.replaceAll('&', 'and')}` : '';
		return { type: 'redZone', key: `redzone-${offense}-${game.period}-${game.clock}`, headline: 'Red Zone', body: `${team.shortName} in the red zone${spot}` };
	}
}

function periodName(g: Game): string {
	const l = g.league;
	if (g.period > l.regulationPeriods) return g.period - l.regulationPeriods === 1 ? 'Overtime' : `Overtime ${g.period - l.regulationPeriods}`;
	return `${l.periodStyle === 'quarters' ? 'Quarter' : 'Period'} ${g.period}`;
}

/** Each league's fresh games, or its last ones where its fetch failed, so the next good poll still sees what changed. */
export function withLastKnown(ids: string[], results: PromiseSettledResult<Game[]>[], last: Game[]): Game[] {
	return results.flatMap((r, i) => (r.status === 'fulfilled' ? r.value : last.filter((g) => g.league.id === ids[i])));
}

/** Quiet hours hold alerts until they end. Times are minutes after midnight; a window may cross midnight. */
export function isQuiet(now: Date, enabled: boolean, start: number, end: number): boolean {
	if (!enabled || start === end) return false;
	const minute = now.getHours() * 60 + now.getMinutes();
	return start < end ? start <= minute && minute < end : minute >= start || minute < end;
}
