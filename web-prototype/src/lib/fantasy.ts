// Ported from SportsKit's Fantasy, Sleeper and ESPNFantasy: the Lineup tab's data for both providers.

export type Injury = { status: string; detail?: string };
export type Player = { id: string; name: string; position?: string; team?: string; espnID?: string; photo?: string; injury?: Injury };
export type Slot = { label: string; player?: Player };
export type Team = { lineup: Slot[]; bench: Player[] };
export type Side = { teamName: string; manager?: string; avatar?: string; points: number; projected: number };
export type Matchup = { me: Side; opponent?: Side };
export type Provider = 'sleeper' | 'espn';
/** memberID is your Sleeper user ID, or your team's ID in an ESPN league. */
export type LeagueRef = { provider: Provider; leagueID: string; name: string; memberID: string };
export type Credentials = { espnS2: string; swid: string };

// Saved leagues. shortcut: ESPN cookies sit in localStorage in plain text; move them to the Keychain / Credential Manager (a keyring plugin) before shipping.
const read = <T>(key: string, fallback: T): T => {
	try {
		return JSON.parse(localStorage.getItem(key) ?? '') as T;
	} catch {
		return fallback;
	}
};
export const store = {
	leagues: (): LeagueRef[] => read('fantasyLeagues', []),
	saveLeagues: (l: LeagueRef[]) => localStorage.setItem('fantasyLeagues', JSON.stringify(l)),
	activeID: (): string | null => localStorage.getItem('fantasyActive'),
	setActive: (id: string) => localStorage.setItem('fantasyActive', id),
	credentials: (leagueID: string): Credentials | undefined => read(`espnCookies:${leagueID}`, undefined),
	setCredentials: (leagueID: string, c?: Credentials) =>
		c ? localStorage.setItem(`espnCookies:${leagueID}`, JSON.stringify(c)) : localStorage.removeItem(`espnCookies:${leagueID}`)
};
export const refID = (l: LeagueRef) => `${l.provider}:${l.leagueID}`;

export const headshot = (espnID: string) => `https://a.espncdn.com/i/headshots/nfl/players/full/${espnID}.png`;

/** Your chance of winning from the two projected totals, against a typical 45-point spread (a normal curve). */
export function winProbability(m: Matchup): number | undefined {
	if (!m.opponent) return;
	return 0.5 * (1 + erf((m.me.projected - m.opponent.projected) / 45 / Math.SQRT2));
}

/** Abramowitz–Stegun 7.1.26, good to 1.5e-7, since JavaScript has no erf. */
function erf(x: number): number {
	const t = 1 / (1 + 0.3275911 * Math.abs(x));
	const y = 1 - ((((1.061405429 * t - 1.453152027) * t + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * Math.exp(-x * x);
	return x >= 0 ? y : -y;
}

async function getJSON(url: string, init?: RequestInit): Promise<any> {
	const response = await fetch(url, init);
	if (!response.ok) throw Object.assign(new Error(`HTTP ${response.status}`), { status: response.status });
	return response.json();
}

// MARK: Sleeper (public, read-only, open to browsers)

const sleeper = 'https://api.sleeper.app/v1/';

export type NFLState = { season: string; seasonStart: Date };

export async function nflState(): Promise<NFLState> {
	const s = await getJSON(`${sleeper}state/nfl`);
	// Midnight Eastern on the season's start date.
	return { season: s.season, seasonStart: new Date(`${s.season_start_date}T05:00:00Z`) };
}

/** The NFL week a date falls in: weeks run seven days from the season's start. */
export const weekOf = (date: Date, state: NFLState) => Math.max(1, Math.floor((date.getTime() - state.seasonStart.getTime()) / (7 * 86_400_000)) + 1);

export async function sleeperUserID(username: string): Promise<string | undefined> {
	return (await getJSON(`${sleeper}user/${encodeURIComponent(username.trim())}`))?.user_id;
}

export async function sleeperLeagues(userID: string, season: string): Promise<{ id: string; name: string }[]> {
	return (await getJSON(`${sleeper}user/${userID}/leagues/nfl/${season}`)).map((l: any) => ({ id: l.league_id, name: l.name }));
}

const ownedBy = (userID: string) => (r: any) => r.owner_id === userID || (r.co_owners ?? []).includes(userID);

// shortcut: the ~15 MB player list is fetched once per launch and kept in memory; cache it on disk (as the Swift app does, 3 h) if launches feel slow.
let playersPromise: Promise<Record<string, Player>> | undefined;
function sleeperPlayers(): Promise<Record<string, Player>> {
	playersPromise ??= getJSON(`${sleeper}players/nfl`).then((all: Record<string, any>) => {
		const players: Record<string, Player> = {};
		for (const [id, p] of Object.entries(all)) {
			const espnID = p.espn_id ? String(p.espn_id) : undefined;
			const detail = [p.injury_body_part, p.practice_participation && `${p.practice_participation} practice`].filter(Boolean).join(' · ');
			players[id] = {
				id,
				name: p.full_name ?? [p.first_name, p.last_name].filter(Boolean).join(' '),
				position: p.position,
				// Sleeper and ESPN agree on NFL abbreviations except Washington.
				team: p.team === 'WAS' ? 'WSH' : p.team,
				espnID,
				photo: espnID ? headshot(espnID) : `https://sleepercdn.com/content/nfl/players/thumb/${id}.jpg`,
				injury: p.injury_status ? { status: p.injury_status, detail: detail || undefined } : undefined
			};
		}
		return players;
	});
	playersPromise.catch(() => (playersPromise = undefined));
	return playersPromise;
}

async function sleeperTeam(leagueID: string, userID: string): Promise<Team | undefined> {
	const [rosters, league, players] = await Promise.all([getJSON(`${sleeper}league/${leagueID}/rosters`), getJSON(`${sleeper}league/${leagueID}`), sleeperPlayers()]);
	const mine = rosters.find(ownedBy(userID));
	if (!mine) return;
	const slots: string[] = (league.roster_positions ?? []).filter((s: string) => !['BN', 'IR', 'TAXI'].includes(s));
	// "0" marks an empty starting slot.
	const starters: (string | undefined)[] = (mine.starters ?? []).map((id: string) => (id === '0' ? undefined : id));
	const starting = new Set(starters);
	return {
		lineup: slots.map((label, i) => ({ label, player: starters[i] ? players[starters[i]!] : undefined })),
		bench: (mine.players ?? []).filter((id: string) => !starting.has(id)).map((id: string) => players[id]).filter(Boolean)
	};
}

/** Each projected stat times the league's own scoring rule for it, so totals match Sleeper's app. */
async function sleeperProjections(leagueID: string, season: string, week: number): Promise<Record<string, number>> {
	const league = await getJSON(`${sleeper}league/${leagueID}`);
	const scoring: Record<string, number> = league.scoring_settings ?? {};
	const positions = ['QB', 'RB', 'WR', 'TE', 'K', 'DEF'].map((p) => `position[]=${p}`).join('&');
	const rows = await getJSON(`https://api.sleeper.com/projections/nfl/${season}/${week}?season_type=regular&${positions}`);
	const result: Record<string, number> = {};
	for (const row of rows) {
		if (!row.stats) continue;
		result[row.player_id] = Object.entries(scoring).reduce((total, [stat, value]) => total + value * (row.stats[stat] ?? 0), 0);
	}
	return result;
}

async function sleeperPoints(leagueID: string, week: number): Promise<Record<string, number>> {
	const matchups = await getJSON(`${sleeper}league/${leagueID}/matchups/${week}`);
	return Object.assign({}, ...matchups.map((m: any) => m.players_points ?? {}));
}

async function sleeperMatchup(leagueID: string, userID: string, week: number, projections: Record<string, number>): Promise<Matchup | undefined> {
	const [rosters, users, matchups] = await Promise.all(['rosters', 'users', `matchups/${week}`].map((p) => getJSON(`${sleeper}league/${leagueID}/${p}`)));
	const mine = rosters.find(ownedBy(userID));
	const myMatchup = mine && matchups.find((m: any) => m.roster_id === mine.roster_id);
	if (!myMatchup) return;
	const side = (m: any): Side => {
		const ownerID = rosters.find((r: any) => r.roster_id === m.roster_id)?.owner_id;
		const owner = users.find((u: any) => u.user_id === ownerID);
		const manager: string | undefined = owner?.display_name;
		return {
			teamName: owner?.metadata?.team_name ?? (manager ? `Team ${manager}` : `Team ${m.roster_id}`),
			manager,
			avatar: owner?.metadata?.avatar ?? (owner?.avatar ? `https://sleepercdn.com/avatars/thumbs/${owner.avatar}` : undefined),
			points: m.points ?? 0,
			projected: (m.starters ?? []).reduce((t: number, id: string) => t + (projections[id] ?? 0), 0)
		};
	};
	const opponent = myMatchup.matchup_id && matchups.find((m: any) => m.matchup_id === myMatchup.matchup_id && m.roster_id !== mine.roster_id);
	return { me: side(myMatchup), opponent: opponent ? side(opponent) : undefined };
}

// MARK: ESPN Fantasy (public leagues: league ID only; private: espn_s2 and SWID cookies)

export class PrivateLeagueError extends Error {
	constructor() {
		super(inTauri ? 'This league is private. Add your espn_s2 and SWID cookies to read it.' : 'This league is private. Private ESPN leagues only work in the desktop app.');
	}
}

const inTauri = typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;

/** In the desktop app ESPN goes through Rust, which may send the Cookie header a browser page can't. */
async function espnFetch(leagueID: string, season: string, views: string[], week?: number, credentials?: Credentials): Promise<any> {
	const query = views.map((v) => `view=${v}`).concat(week ? [`scoringPeriodId=${week}`] : []).join('&');
	const url = `https://lm-api-reads.fantasy.espn.com/apis/v3/games/ffl/seasons/${season}/segments/0/leagues/${leagueID}?${query}`;
	const headers: Record<string, string> = credentials ? { Cookie: `espn_s2=${credentials.espnS2}; SWID=${credentials.swid}` } : {};
	const send = inTauri ? (await import('@tauri-apps/plugin-http')).fetch : fetch;
	const response = await send(url, { headers });
	if (response.status === 401) throw new PrivateLeagueError();
	if (response.status === 404) throw new Error('No ESPN league with that ID this season.');
	if (!response.ok) throw new Error(`ESPN returned ${response.status}`);
	return response.json();
}

const espnTeamName = (t: any): string => t?.name ?? [t?.location, t?.nickname].filter(Boolean).join(' ');

export async function espnLeague(leagueID: string, season: string, credentials?: Credentials): Promise<{ name: string; teams: { id: string; name: string }[] }> {
	const d = await espnFetch(leagueID, season, ['mTeam', 'mSettings'], undefined, credentials);
	return { name: d.settings?.name ?? 'ESPN League', teams: (d.teams ?? []).map((t: any) => ({ id: String(t.id), name: espnTeamName(t) })) };
}

/** ESPN lineup slot IDs in display order; bench (20) and IR (21) aren't starting slots. */
const startingSlots: [number, string][] = [[0, 'QB'], [2, 'RB'], [3, 'RB/WR'], [4, 'WR'], [5, 'WR/TE'], [6, 'TE'], [23, 'FLEX'], [7, 'OP'], [16, 'DEF'], [17, 'K']];
const positions: Record<number, string> = { 1: 'QB', 2: 'RB', 3: 'WR', 4: 'TE', 5: 'K', 16: 'DEF' };
const proTeams: Record<number, string> = {
	1: 'ATL', 2: 'BUF', 3: 'CHI', 4: 'CIN', 5: 'CLE', 6: 'DAL', 7: 'DEN', 8: 'DET', 9: 'GB', 10: 'TEN', 11: 'IND', 12: 'KC', 13: 'LV', 14: 'LAR', 15: 'MIA', 16: 'MIN',
	17: 'NE', 18: 'NO', 19: 'NYG', 20: 'NYJ', 21: 'PHI', 22: 'ARI', 23: 'PIT', 24: 'LAC', 25: 'SF', 26: 'SEA', 27: 'TB', 28: 'WSH', 29: 'CAR', 30: 'JAX', 33: 'BAL', 34: 'HOU'
};

function espnPlayer(p: any): Player {
	// Team defences have negative IDs, which aren't athletes.
	const espnID = p.id > 0 ? String(p.id) : undefined;
	const status: string | undefined = p.injuryStatus;
	return {
		id: String(p.id),
		name: p.fullName,
		position: positions[p.defaultPositionId],
		team: proTeams[p.proTeamId],
		espnID,
		photo: espnID && headshot(espnID),
		// ESPN says ACTIVE (or NORMAL) for healthy players.
		injury: !status || status === 'ACTIVE' || status === 'NORMAL' ? undefined : { status: status === 'INJURY_RESERVE' ? 'IR' : status[0] + status.slice(1).toLowerCase() }
	};
}

async function espnTeam(leagueID: string, season: string, teamID: string, c?: Credentials): Promise<Team | undefined> {
	const d = await espnFetch(leagueID, season, ['mRoster', 'mSettings'], undefined, c);
	const team = d.teams?.find((t: any) => String(t.id) === teamID);
	if (!team) return;
	const entries: any[] = team.roster?.entries ?? [];
	const counts: Record<string, number> = d.settings?.rosterSettings?.lineupSlotCounts ?? {};
	const lineup: Slot[] = startingSlots.flatMap(([id, label]) => {
		const filled = entries.filter((e) => e.lineupSlotId === id && e.playerPoolEntry).map((e) => espnPlayer(e.playerPoolEntry.player));
		return Array.from({ length: Math.max(counts[id] ?? 0, filled.length) }, (_, i) => ({ label, player: filled[i] }));
	});
	const starting = new Set(startingSlots.map(([id]) => id));
	return { lineup, bench: entries.filter((e) => !starting.has(e.lineupSlotId) && e.playerPoolEntry).map((e) => espnPlayer(e.playerPoolEntry.player)) };
}

/** Points per player for a week: actual (source 0) or ESPN's projection (source 1). */
async function espnPoints(leagueID: string, season: string, week: number, source: 0 | 1, c?: Credentials): Promise<Record<string, number>> {
	const d = await espnFetch(leagueID, season, ['mRoster'], week, c);
	const points: Record<string, number> = {};
	for (const entry of (d.teams ?? []).flatMap((t: any) => t.roster?.entries ?? [])) {
		const p = entry.playerPoolEntry?.player;
		const total = p?.stats?.find((s: any) => s.scoringPeriodId === week && s.statSourceId === source)?.appliedTotal;
		if (total !== undefined) points[String(p.id)] = total;
	}
	return points;
}

async function espnMatchup(leagueID: string, season: string, teamID: string, week: number, projections: Record<string, number>, c?: Credentials): Promise<Matchup | undefined> {
	const d = await espnFetch(leagueID, season, ['mMatchupScore', 'mRoster', 'mTeam'], week, c);
	const id = Number(teamID);
	const game = d.schedule?.find((g: any) => g.matchupPeriodId === week && (g.home?.teamId === id || g.away?.teamId === id));
	if (!game) return;
	const side = (s: any): Side => {
		const team = d.teams?.find((t: any) => t.id === s.teamId);
		const starters = (team?.roster?.entries ?? []).filter((e: any) => ![20, 21].includes(e.lineupSlotId));
		return {
			teamName: espnTeamName(team),
			manager: d.members?.find((m: any) => m.id === team?.owners?.[0])?.displayName,
			avatar: team?.logo,
			points: s.totalPoints ?? 0,
			projected: starters.reduce((t: number, e: any) => t + (e.playerPoolEntry ? projections[String(e.playerPoolEntry.player.id)] ?? 0 : 0), 0)
		};
	};
	const [mine, theirs] = game.home?.teamId === id ? [game.home, game.away] : [game.away, game.home];
	return { me: side(mine), opponent: theirs ? side(theirs) : undefined };
}

// MARK: Dispatch, as FantasyData.

export async function team(l: LeagueRef, season: string): Promise<Team> {
	const t = l.provider === 'sleeper' ? await sleeperTeam(l.leagueID, l.memberID) : await espnTeam(l.leagueID, season, l.memberID, store.credentials(l.leagueID));
	if (!t) throw new Error('You don’t have a team in this league.');
	return t;
}

export const projections = (l: LeagueRef, season: string, week: number) =>
	l.provider === 'sleeper' ? sleeperProjections(l.leagueID, season, week) : espnPoints(l.leagueID, season, week, 1, store.credentials(l.leagueID));

export const points = (l: LeagueRef, season: string, week: number) =>
	l.provider === 'sleeper' ? sleeperPoints(l.leagueID, week) : espnPoints(l.leagueID, season, week, 0, store.credentials(l.leagueID));

export const matchup = (l: LeagueRef, season: string, week: number, proj: Record<string, number>) =>
	l.provider === 'sleeper' ? sleeperMatchup(l.leagueID, l.memberID, week, proj) : espnMatchup(l.leagueID, season, l.memberID, week, proj, store.credentials(l.leagueID));

/** Injury severity, 0 healthy … 4 season-ending, for the status tag's colour. */
export function severity(i?: Injury): number {
	const s = i?.status.toLowerCase() ?? '';
	return ['ir', 'injury_reserve', 'pup', 'na', 'sus', 'suspension'].includes(s) ? 4 : s === 'out' ? 3 : s === 'doubtful' ? 2 : s === 'questionable' ? 1 : 0;
}

// MARK: Season, standings, calendar and news, as FantasyInsights.swift.

export type Starter = { playerID: string; name: string; position?: string; actual: number; projected: number };
export type WeekResult = { week: number; starters: Starter[]; actual: number; projected: number };
export type Standing = { id: string; teamName: string; wins: number; losses: number; ties: number; pointsFor: number; isMine: boolean };
export type Calendar = { playoffWeekStart: number; tradeDeadlineWeek?: number };
export type News = { id: string; headline: string; story?: string; published: Date; source: string; url?: string };

const weekResult = (week: number, starters: Starter[]): WeekResult => ({
	week,
	starters,
	actual: starters.reduce((t, s) => t + s.actual, 0),
	projected: starters.reduce((t, s) => t + s.projected, 0)
});

/** Your starters in one week with what each scored (Sleeper's starters_points) and was projected. */
async function sleeperWeek(leagueID: string, userID: string, season: string, week: number, players: Record<string, Player>): Promise<WeekResult | undefined> {
	const [rosters, matchups, proj] = await Promise.all([getJSON(`${sleeper}league/${leagueID}/rosters`), getJSON(`${sleeper}league/${leagueID}/matchups/${week}`), sleeperProjections(leagueID, season, week)]);
	const mine = rosters.find(ownedBy(userID));
	const m = mine && matchups.find((x: any) => x.roster_id === mine.roster_id);
	if (!m) return;
	const points: number[] = m.starters_points ?? [];
	const starters = (m.starters ?? []).flatMap((id: string, i: number) =>
		id === '0' ? [] : [{ playerID: id, name: players[id]?.name ?? id, position: players[id]?.position, actual: points[i] ?? 0, projected: proj[id] ?? 0 }]
	);
	return weekResult(week, starters);
}

async function espnWeek(leagueID: string, season: string, teamID: string, week: number, c?: Credentials): Promise<WeekResult | undefined> {
	const d = await espnFetch(leagueID, season, ['mRoster'], week, c);
	const team = d.teams?.find((t: any) => String(t.id) === teamID);
	if (!team) return;
	const starting = new Set(startingSlots.map(([id]) => id));
	const starters = (team.roster?.entries ?? []).filter((e: any) => starting.has(e.lineupSlotId) && e.playerPoolEntry).map((e: any) => {
		const p = e.playerPoolEntry.player;
		const total = (source: number) => p.stats?.find((s: any) => s.scoringPeriodId === week && s.statSourceId === source)?.appliedTotal ?? 0;
		return { playerID: String(p.id), name: p.fullName, position: positions[p.defaultPositionId], actual: total(0), projected: total(1) };
	});
	return weekResult(week, starters);
}

/** Your starters' actual and projected points for each completed week, oldest first. */
export async function season(l: LeagueRef, seasonYear: string, weeks: number[]): Promise<WeekResult[]> {
	// Sleeper names starters by ID only; its player list fills in names, including players since dropped.
	const players = l.provider === 'sleeper' ? await sleeperPlayers() : {};
	const results = await Promise.all(
		weeks.map((w) => (l.provider === 'sleeper' ? sleeperWeek(l.leagueID, l.memberID, seasonYear, w, players) : espnWeek(l.leagueID, seasonYear, l.memberID, w, store.credentials(l.leagueID))))
	);
	return results.filter((r): r is WeekResult => !!r);
}

export type SeasonTrend = {
	weeks: WeekResult[];
	actualPerWeek: number;
	projectedPerWeek: number;
	/** Average actual minus projected per start, best last. */
	gapByPosition: { position: string; gap: number }[];
	/** Total actual minus projected across all starts, worst first. */
	gapByStarter: { name: string; gap: number }[];
};

export function seasonTrend(weeks: WeekResult[]): SeasonTrend {
	const count = Math.max(1, weeks.length);
	const byPosition = new Map<string, { total: number; starts: number }>();
	const byStarter = new Map<string, { name: string; gap: number }>();
	for (const s of weeks.flatMap((w) => w.starters)) {
		const gap = s.actual - s.projected;
		const starter = byStarter.get(s.playerID) ?? { name: s.name, gap: 0 };
		byStarter.set(s.playerID, { ...starter, gap: starter.gap + gap });
		if (s.position) {
			const p = byPosition.get(s.position) ?? { total: 0, starts: 0 };
			byPosition.set(s.position, { total: p.total + gap, starts: p.starts + 1 });
		}
	}
	return {
		weeks,
		actualPerWeek: weeks.reduce((t, w) => t + w.actual, 0) / count,
		projectedPerWeek: weeks.reduce((t, w) => t + w.projected, 0) / count,
		gapByPosition: [...byPosition].map(([position, p]) => ({ position, gap: p.total / p.starts })).sort((a, b) => a.gap - b.gap),
		gapByStarter: [...byStarter.values()].sort((a, b) => a.gap - b.gap)
	};
}

/** By record, then points for, as fantasy apps rank. */
export async function standings(l: LeagueRef, seasonYear: string): Promise<Standing[]> {
	let rows: Standing[];
	if (l.provider === 'sleeper') {
		const [rosters, users] = await Promise.all([getJSON(`${sleeper}league/${l.leagueID}/rosters`), getJSON(`${sleeper}league/${l.leagueID}/users`)]);
		rows = rosters.map((r: any) => {
			const owner = users.find((u: any) => u.user_id === r.owner_id);
			const s = r.settings ?? {};
			return {
				id: String(r.roster_id),
				teamName: owner?.metadata?.team_name ?? owner?.display_name ?? `Team ${r.roster_id}`,
				wins: s.wins ?? 0, losses: s.losses ?? 0, ties: s.ties ?? 0,
				pointsFor: (s.fpts ?? 0) + (s.fpts_decimal ?? 0) / 100,
				isMine: ownedBy(l.memberID)(r)
			};
		});
	} else {
		const d = await espnFetch(l.leagueID, seasonYear, ['mTeam'], undefined, store.credentials(l.leagueID));
		rows = (d.teams ?? []).map((t: any) => {
			const r = t.record?.overall ?? {};
			return { id: String(t.id), teamName: espnTeamName(t), wins: r.wins ?? 0, losses: r.losses ?? 0, ties: r.ties ?? 0, pointsFor: r.pointsFor ?? 0, isMine: String(t.id) === l.memberID };
		});
	}
	return rows.sort((a, b) => b.wins + b.ties / 2 - (a.wins + a.ties / 2) || b.pointsFor - a.pointsFor);
}

export const record = (s: Standing) => (s.ties > 0 ? `${s.wins}-${s.losses}-${s.ties}` : `${s.wins}-${s.losses}`);

/** When the playoffs start and the trade deadline, as NFL weeks. */
export async function calendar(l: LeagueRef, state: NFLState): Promise<Calendar> {
	if (l.provider === 'sleeper') {
		const s = (await getJSON(`${sleeper}league/${l.leagueID}`)).settings ?? {};
		// A deadline past the regular season (Sleeper uses 99) means there isn't one.
		return { playoffWeekStart: s.playoff_week_start ?? 15, tradeDeadlineWeek: s.trade_deadline > 0 && s.trade_deadline < 19 ? s.trade_deadline : undefined };
	}
	const s = (await espnFetch(l.leagueID, state.season, ['mSettings'], undefined, store.credentials(l.leagueID))).settings;
	const deadline = s?.tradeSettings?.deadlineDate;
	return { playoffWeekStart: (s?.scheduleSettings?.matchupPeriodCount ?? 14) + 1, tradeDeadlineWeek: deadline > 0 ? weekOf(new Date(deadline), state) : undefined };
}

/** Each NFL team's bye week: the regular-season week it doesn't appear in. */
export function byes(schedule: Map<number, { home: string; away: string }[]>): Record<string, number> {
	const teams = new Set([...schedule.values()].flat().flatMap((g) => [g.home, g.away]));
	const result: Record<string, number> = {};
	for (const [week, games] of schedule) {
		const playing = new Set(games.flatMap((g) => [g.home, g.away]));
		for (const team of teams) if (!playing.has(team)) result[team] = week;
	}
	return result;
}

/** Some stories arrive as HTML: reduced to text (never rendered), spacing tidied. */
const plainText = (html: string) => (new DOMParser().parseFromString(html, 'text/html').body.textContent ?? '').replace(/\s+/g, ' ').trim();

/** ESPN's fantasy news feed for one player (Rotowire blurbs and analysis). */
export async function news(espnID: string, limit = 4): Promise<News[]> {
	const d = await getJSON(`https://site.api.espn.com/apis/fantasy/v2/games/ffl/news/players?limit=${limit}&playerId=${espnID}`);
	return (d.feed ?? []).flatMap((item: any) => {
		const published = item.published && new Date(item.published);
		if (!item.headline || !published || isNaN(published.getTime())) return [];
		const url: string | undefined = item.links?.web?.href ?? item.links?.mobile?.href;
		return [{ id: String(item.id ?? item.headline), headline: plainText(item.headline), story: item.story ? plainText(item.story) || undefined : undefined, published, source: item.type ?? 'ESPN', url: url?.replace('http://', 'https://') }];
	});
}

// MARK: Bye-week planning, as ByeWeekPlanner and LineupCover.

/** Which positions can fill a lineup slot, across Sleeper's and ESPN's slot names. */
export function slotPositions(slot: string): string[] {
	switch (slot) {
		case 'FLEX': return ['RB', 'WR', 'TE'];
		case 'REC_FLEX': case 'WR/TE': return ['WR', 'TE'];
		case 'WRRB_FLEX': case 'RB/WR': return ['RB', 'WR'];
		case 'SUPER_FLEX': case 'OP': return ['QB', 'RB', 'WR', 'TE'];
		default: return [slot];
	}
}

export type CoverSlot = { label: string; starter?: Player; filledBy?: Player };
/** The usual starter can't play here (or there isn't one). */
export const needsCover = (s: CoverSlot) => !s.starter || s.filledBy?.id !== s.starter.id;

/** Who fills each starting slot in a week: starters keep their own slot where they can play, and the bench fills
 *  the gaps, moving starters between flex slots if that frees a spot (a maximum matching). */
export function lineupCover(lineup: Slot[], bench: Player[], isAvailable: (p: Player) => boolean): CoverSlot[] {
	const starters = lineup.map((s) => s.player).filter((p): p is Player => !!p && isAvailable(p));
	const players = [...starters, ...bench.filter((p) => isAvailable(p) && !starters.includes(p))];
	const playerOfSlot: (number | undefined)[] = lineup.map(() => undefined);
	const slotOfPlayer: (number | undefined)[] = players.map(() => undefined);
	// Starters begin in their own slots.
	lineup.forEach((entry, slot) => {
		const i = entry.player ? players.indexOf(entry.player) : -1;
		if (i >= 0) [playerOfSlot[slot], slotOfPlayer[i]] = [i, slot];
	});
	function assign(slot: number, seen: Set<number>): boolean {
		const allowed = slotPositions(lineup[slot].label);
		// Free players first, so nobody already placed moves unless that's the only way to fill the slot.
		const order = [...players.keys()].sort((a, b) => Number(slotOfPlayer[a] !== undefined) - Number(slotOfPlayer[b] !== undefined));
		for (const p of order) {
			if (!allowed.includes(players[p].position ?? '') || seen.has(p)) continue;
			seen.add(p);
			if (slotOfPlayer[p] === undefined || assign(slotOfPlayer[p]!, seen)) {
				[slotOfPlayer[p], playerOfSlot[slot]] = [slot, p];
				return true;
			}
		}
		return false;
	}
	lineup.forEach((_, slot) => playerOfSlot[slot] === undefined && assign(slot, new Set()));
	return lineup.map((entry, i) => ({ label: entry.label, starter: entry.player, filledBy: playerOfSlot[i] === undefined ? undefined : players[playerOfSlot[i]!] }));
}

/** Whether two spellings name the same player: case, punctuation and suffixes ignored, so Sleeper's "Kenneth Walker"
 *  matches ESPN's "Kenneth Walker III" and "D.J. Moore" matches "DJ Moore". */
export function sameName(a: string, b: string): boolean {
	const key = (name: string) => name.toLowerCase().replace(/[^\p{L}\s]/gu, '').split(/\s+/).filter((w) => w && !['jr', 'sr', 'ii', 'iii', 'iv', 'v'].includes(w)).join(' ');
	return key(a) === key(b);
}

// MARK: Spotting your players in games, as FantasyRoster.

/** ESPN's play-by-play short form: "Jayden Daniels" → "J.Daniels", "Amon-Ra St. Brown" → "A.St. Brown". */
export function shortName(name: string): string | undefined {
	const words = name.split(' ').filter((w) => !['jr.', 'jr', 'sr.', 'sr', 'ii', 'iii', 'iv', 'v'].includes(w.toLowerCase()));
	return words.length >= 2 ? `${words[0][0]}.${words.slice(1).join(' ')}` : undefined;
}

/** `name` appears in `text` not glued to other letters ("J.Brown" isn't in "AJ.Brown" or "J.Browning"). */
function mentions(text: string, name: string): boolean {
	for (let i = text.indexOf(name); i >= 0; i = text.indexOf(name, i + 1)) {
		const before = text[i - 1], after = text[i + name.length];
		if (!(before && (/\p{L}/u.test(before) || before === '.')) && !(after && /\p{L}/u.test(after))) return true;
	}
	return false;
}

/** The players a play's text names, by full or short name, as whole words. */
export const playersIn = (text: string, players: Player[]) =>
	players.filter((p) => [p.name, shortName(p.name)].some((n) => n && mentions(text, n)));

/** Whether a box score row is one of yours: by ESPN ID, else by name. */
export const isRostered = (athleteID: string, name: string, players: Player[]) => players.some((p) => p.espnID === athleteID || p.name === name);
