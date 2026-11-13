// Ported from SportsKit's ESPN provider: the same unofficial endpoints, trimmed to what Home and the NFL page need.

export type League = { id: string; name: string; abbreviation: string; path: string; regulationPeriods: number; periodStyle: 'quarters' | 'periods' | 'halves' };

export const leagues: League[] = [
	{ id: 'nfl', name: 'National Football League', abbreviation: 'NFL', path: 'football/nfl', regulationPeriods: 4, periodStyle: 'quarters' },
	{ id: 'nba', name: 'National Basketball Association', abbreviation: 'NBA', path: 'basketball/nba', regulationPeriods: 4, periodStyle: 'quarters' },
	{ id: 'nhl', name: 'National Hockey League', abbreviation: 'NHL', path: 'hockey/nhl', regulationPeriods: 3, periodStyle: 'periods' },
	{ id: 'epl', name: 'Premier League', abbreviation: 'EPL', path: 'soccer/eng.1', regulationPeriods: 2, periodStyle: 'halves' }
];

/** Soccer league logos live under ESPN's numeric league IDs (League.logoURL). */
export const leagueLogo = (l: League) =>
	l.id === 'epl' ? 'https://a.espncdn.com/i/leaguelogos/soccer/500/23.png' : `https://a.espncdn.com/i/teamlogos/leagues/500/${l.id}.png`;

export type Team = { id: string; abbreviation: string; displayName: string; shortName: string; color?: string; alternateColor?: string; logo?: string };
export type Competitor = { team: Team; score?: number; record?: string; periodScores: number[] };
export type Situation = { possessionTeamID?: string; yardLine?: number; distance?: number; shortDownAndDistance?: string };
export type Status = 'scheduled' | 'live' | 'final';
export type Game = {
	id: string;
	league: League;
	startDate: Date;
	status: Status;
	period: number;
	clock: string;
	statusDetail: string;
	statusName: string;
	home: Competitor;
	away: Competitor;
	situation?: Situation;
	note?: string;
	broadcasts: string[];
};

const base = 'https://site.api.espn.com/apis/site/v2/sports/';

async function get(url: string): Promise<any> {
	const response = await fetch(url);
	if (!response.ok) throw new Error(`ESPN returned ${response.status}`);
	return response.json();
}

/** ESPN files games by US Eastern day; a local day can straddle two of them. */
function espnDays(day: Date): string[] {
	const fmt = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York', year: 'numeric', month: '2-digit', day: '2-digit' });
	const end = new Date(day.getTime() + 86_400_000 - 1);
	return [...new Set([day, end].map((d) => fmt.format(d).replaceAll('-', '')))];
}

export function startOfDay(offset: number): Date {
	const d = new Date();
	d.setHours(0, 0, 0, 0);
	d.setDate(d.getDate() + offset);
	return d;
}

export async function scoreboard(league: League, day: Date): Promise<Game[]> {
	const pages = await Promise.all(espnDays(day).map((d) => get(`${base}${league.path}/scoreboard?dates=${d}`)));
	const end = day.getTime() + 86_400_000;
	const games = pages.flatMap((p) => (p.events ?? []).map((e: any) => parseEvent(e, league)));
	const seen = new Set<string>();
	return games.filter((g) => g.startDate.getTime() >= day.getTime() && g.startDate.getTime() < end && !seen.has(g.id) && seen.add(g.id));
}

/** One NFL regular-season week (seasontype 2), every game in a single request. */
export async function nflWeek(season: string, week: number): Promise<Game[]> {
	const page = await get(`${base}football/nfl/scoreboard?dates=${season}&seasontype=2&week=${week}&limit=100`);
	return (page.events ?? []).map((e: any) => parseEvent(e, leagues[0]));
}

function parseTeam(t: any): Team {
	return {
		id: t.id,
		abbreviation: t.abbreviation,
		displayName: t.displayName,
		shortName: t.shortDisplayName,
		color: t.color,
		alternateColor: t.alternateColor,
		logo: t.logo ?? t.logos?.[0]?.href
	};
}

function parseEvent(e: any, league: League): Game {
	const c = e.competitions[0];
	const state = c.status.type.state;
	const status: Status = state === 'pre' ? 'scheduled' : state === 'in' ? 'live' : 'final';
	const competitor = (homeAway: string): Competitor => {
		const x = c.competitors.find((k: any) => k.homeAway === homeAway);
		return {
			team: parseTeam(x.team),
			score: status === 'scheduled' ? undefined : Number(x.score),
			record: x.records?.[0]?.summary,
			periodScores: (x.linescores ?? []).map((l: any) => Number(l.value ?? l.displayValue))
		};
	};
	const s = c.situation;
	return {
		id: e.id,
		league,
		startDate: new Date(e.date),
		status,
		period: c.status.period,
		clock: c.status.displayClock,
		statusDetail: c.status.type.shortDetail,
		statusName: c.status.type.name,
		home: competitor('home'),
		away: competitor('away'),
		situation: s && {
			possessionTeamID: s.possession,
			yardLine: s.yardLine,
			distance: s.distance,
			shortDownAndDistance: s.shortDownDistanceText && (s.possessionText ? `${s.shortDownDistanceText} · ${s.possessionText}` : s.shortDownDistanceText)
		},
		note: c.notes?.[0]?.headline,
		broadcasts: watchOn(c)
	};
}

/** Channels and streaming apps, national before local, without repeats. */
function watchOn(c: any): string[] {
	const national = (m: string | undefined) => (m?.toLowerCase() === 'national' ? 0 : 1);
	const geo = [...(c.geoBroadcasts ?? [])].sort((a, b) => national(a.market?.type) - national(b.market?.type)).map((g) => g.media?.shortName);
	const names = geo.length ? geo : [...(c.broadcasts ?? [])].sort((a, b) => national(a.market) - national(b.market)).flatMap((b) => b.names ?? []);
	return [...new Set(names.filter(Boolean) as string[])];
}

// Display helpers, as Game+ScoreStyle in the Swift app.

export function ordinal(n: number): string {
	const suffix = n % 100 >= 11 && n % 100 <= 13 ? 'th' : ({ 1: 'st', 2: 'nd', 3: 'rd' } as Record<number, string>)[n % 10] ?? 'th';
	return `${n}${suffix}`;
}

/** Centre status in iOS style: "4th 1:54", "Half", "Final", or a start time. */
export function headlineStatus(g: Game): string {
	if (g.status === 'scheduled') return g.startDate.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
	if (g.status === 'final') return g.statusDetail;
	if (g.statusName === 'STATUS_HALFTIME') return 'Half';
	if (g.statusName === 'STATUS_END_PERIOD' || g.league.periodStyle === 'halves') return g.statusDetail;
	const period = g.period <= g.league.regulationPeriods ? ordinal(g.period) : periodLabel(g.league, g.period);
	return `${period} ${g.clock}`;
}

export function periodLabel(l: League, n: number): string {
	if (n <= l.regulationPeriods) return String(n);
	const ot = n - l.regulationPeriods;
	return ot === 1 ? 'OT' : `${ot}OT`;
}

export const substatus = (g: Game) => (g.status === 'live' ? g.situation?.shortDownAndDistance : undefined);
export const hasBall = (g: Game, c: Competitor) => g.status === 'live' && g.situation?.possessionTeamID === c.team.id;

export function isLosing(g: Game, c: Competitor): boolean {
	if (g.status !== 'final' || c.score === undefined) return false;
	const other = c.team.id === g.home.team.id ? g.away : g.home;
	return c.score < (other.score ?? 0);
}

/** Live first, then upcoming, then finished. */
export const ordered = (games: Game[]) => [...games].sort((a, b) => ['live', 'scheduled', 'final'].indexOf(a.status) - ['live', 'scheduled', 'final'].indexOf(b.status));

function hsb(hex: string) {
	const v = [0, 2, 4].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255);
	const top = Math.max(...v), bottom = Math.min(...v);
	return { saturation: top === 0 ? 0 : (top - bottom) / top, brightness: top };
}

/** Behind the game page: the alternate colour when the main one is grey (Team.backdropHex). */
export function backdropHex(t: Team): string | undefined {
	if (!t.color || !t.alternateColor || t.color.length !== 6 || t.alternateColor.length !== 6) return t.color;
	const main = hsb(t.color), alt = hsb(t.alternateColor);
	return main.saturation < 0.15 && (alt.saturation >= 0.15 || alt.brightness < 0.4) ? t.alternateColor : t.color;
}

// Game page: summary drives and the field, as FieldView.swift's FieldState.

export type Play = {
	id: string;
	text: string;
	type?: string;
	headline?: string;
	teamID?: string;
	isScoring: boolean;
	awayScore?: number;
	homeScore?: number;
	spot?: string;
	startYardLine?: number;
	endYardLine?: number;
	period: number;
	clock: string;
	/** Where it happened, 0–1 across and along the surface (NBA: across the court and out from the basket). */
	location?: { x: number; y: number };
	isShot: boolean;
};
export type Drive = { id: string; teamID?: string; summary: string; result?: string; isScore: boolean; plays: Play[] };
export type BoxScore = { teamID: string; title: string; labels: string[]; rows: { id: string; name: string; stats: string[] }[] };
export type TeamStat = { label: string; away: string; home: string };
export type Leader = { teamID: string; category: string; athlete: string; shortName?: string; position?: string; headshot?: string; mainValue?: string; summary?: string };
export type Overview = {
	venue?: { name: string; place?: string; image?: string };
	attendance?: number;
	broadcasts: string[];
	odds?: { books: string[]; homeSpread?: number; overUnder?: number; homeMoneyLine?: number; awayMoneyLine?: number };
	standings: { teamID: string; group: string; position: number; record?: string }[];
	winProbability: Record<string, number>;
	leaders: Leader[];
	recap?: { headline: string; paragraphs: string[] };
};
export type GameDetail = { plays: Play[]; shots: Shot[]; drives: Drive[]; periodScores: Record<string, number[]>; boxScores: BoxScore[]; teamStats: TeamStat[]; overview: Overview };

export async function summary(game: Game): Promise<GameDetail> {
	const s = await get(`${base}${game.league.path}/summary?event=${game.id}`);
	let drives: any[] = s.drives?.previous ?? [];
	// The live drive also appears at the end of `previous`, possibly stale.
	if (s.drives?.current) drives = [...drives.filter((d) => d.id !== s.drives.current.id), s.drives.current];
	const modelDrives: Drive[] = drives.map((d) => ({
		id: d.id,
		teamID: d.team?.id,
		summary: d.description ?? '',
		result: d.displayResult,
		isScore: d.isScore ?? false,
		plays: (d.plays ?? []).map((p: any) => parsePlay(p, game.league, d.team?.id))
	}));
	// NFL groups plays into drives; most sports send a flat list; soccer only has key events.
	let plays: Play[];
	if (modelDrives.length) plays = modelDrives.flatMap((d) => d.plays);
	else {
		// Some feeds leave scoringPlay empty, so fall back to the running score changing.
		let previous = [0, 0];
		plays = (s.plays ?? s.keyEvents ?? []).map((p: any) => {
			const play = parsePlay(p, game.league);
			if (p.scoringPlay === undefined && p.awayScore !== undefined && p.homeScore !== undefined) {
				play.isScoring = p.awayScore !== previous[0] || p.homeScore !== previous[1];
				previous = [p.awayScore, p.homeScore];
			}
			return play;
		});
	}
	return {
		plays,
		shots: shots(s),
		drives: modelDrives,
		periodScores: Object.fromEntries(
			(s.header?.competitions?.[0]?.competitors ?? []).map((c: any) => [c.team.id, (c.linescores ?? []).map((l: any) => Number(l.displayValue)).filter((n: number) => !isNaN(n))])
		),
		boxScores: (s.boxscore?.players ?? []).flatMap((team: any) =>
			(team.statistics ?? [])
				.filter((c: any) => c.labels?.length)
				.map((c: any) => ({
					teamID: team.team.id,
					title: c.text ?? `${team.team.displayName} ${c.name}`,
					labels: c.labels,
					rows: (c.athletes ?? []).filter((a: any) => a.stats).map((a: any) => ({ id: a.athlete.id, name: a.athlete.displayName, stats: a.stats }))
				}))
		),
		teamStats: teamStats(s.boxscore?.teams ?? []),
		overview: overview(s)
	};
}

function parsePlay(p: any, league: League, teamID?: string): Play {
	const c = p.coordinate;
	return {
		id: p.id,
		text: p.text ?? '',
		type: p.type?.text,
		headline: p.shortDescription,
		teamID: teamID ?? p.team?.id,
		isScoring: p.scoringPlay ?? false,
		awayScore: p.awayScore,
		homeScore: p.homeScore,
		spot: p.start?.downDistanceText,
		startYardLine: p.start?.yardLine,
		endYardLine: p.end?.yardLine,
		period: p.period?.number ?? 0,
		clock: p.clock?.displayValue ?? '',
		location: location(league, c),
		isShot: p.shootingPlay ?? false
	};
}

/** A play's spot as 0–1 of the surface; off-surface values are ESPN's "unknown". */
function location(league: League, c: any): Play['location'] {
	if (!c || typeof c.x !== 'number' || typeof c.y !== 'number') return;
	// NBA: feet on a half court (50 wide, 47 deep).
	if (league.id === 'nba' && c.x >= 0 && c.x <= 50 && c.y >= 0 && c.y <= 47) return { x: c.x / 50, y: c.y / 47 };
	// NHL: feet from centre ice on the 200 × 85 rink.
	if (league.id === 'nhl' && Math.abs(c.x) <= 100 && Math.abs(c.y) <= 42.5) return { x: (c.x + 100) / 200, y: (42.5 - c.y) / 85 };
}

export type ShotOutcome = 'goal' | 'save' | 'offTarget' | 'block';
/** A soccer attempt, in the shooting team's frame: x toward the goal it attacks, y across. */
export type Shot = { id: string; teamID: string; outcome: ShotOutcome; location: { x: number; y: number }; end?: { x: number; y: number }; text: string; period: number; shooter?: string };

/** Soccer shots come from the commentary, which names teams but gives no IDs, so match them through the line-ups. */
function shots(s: any): Shot[] {
	const teamIDs = new Map<string, string>((s.rosters ?? []).map((r: any) => [r.team?.displayName, r.team?.id]));
	return (s.commentary ?? []).flatMap((entry: any) => {
		const p = entry.play;
		const kind: string = p?.type?.type ?? '';
		const outcome: ShotOutcome | undefined =
			kind.startsWith('goal') || kind === 'penalty---scored' ? 'goal'
			: kind === 'shot-on-target' || kind === 'penalty---saved' ? 'save'
			: kind === 'shot-off-target' || kind === 'penalty---missed' ? 'offTarget'
			: kind === 'shot-blocked' ? 'block'
			: undefined;
		const teamID = teamIDs.get(p?.team?.displayName);
		if (!outcome || !teamID || p.fieldPositionX === undefined || p.fieldPositionY === undefined) return [];
		return [{
			id: p.id,
			teamID,
			outcome,
			location: { x: p.fieldPositionX / 100, y: p.fieldPositionY / 100 },
			end: p.fieldPosition2X !== undefined && p.fieldPosition2Y !== undefined ? { x: p.fieldPosition2X / 100, y: p.fieldPosition2Y / 100 } : undefined,
			text: [p.shortText, p.clock?.displayValue].filter(Boolean).join(' · '),
			period: p.period?.number ?? 1,
			shooter: p.participants?.[0]?.athlete?.displayName
		}];
	});
}

/** Both teams list the same stats in the same order. */
function teamStats(teams: any[]): TeamStat[] {
	const away = teams.find((t) => t.homeAway === 'away')?.statistics ?? [];
	const home = teams.find((t) => t.homeAway === 'home')?.statistics ?? [];
	return away
		.map((a: any, i: number) => ({ label: a.label ?? a.displayName, away: a.displayValue, home: home[i]?.displayValue }))
		.filter((t: TeamStat) => t.label && t.away !== undefined && t.home !== undefined);
}

function overview(s: any): Overview {
	const v = s.gameInfo?.venue;
	// Average every listed sportsbook; ESPN's free feed often has just one.
	const books: any[] = [...(s.pickcenter ?? []), ...(s.odds ?? [])];
	const average = (values: (number | undefined)[]) => {
		const n = values.filter((x): x is number => typeof x === 'number');
		return n.length ? n.reduce((a, b) => a + b, 0) / n.length : undefined;
	};
	const round = (n?: number) => (n === undefined ? undefined : Math.round(n));
	const winProbability: Record<string, number> = {};
	for (const side of [s.predictor?.homeTeam, s.predictor?.awayTeam]) if (side?.id && side.gameProjection) winProbability[side.id] = Number(side.gameProjection);
	return {
		venue: v?.fullName && { name: v.fullName, place: [v.address?.city, v.address?.state].filter(Boolean).join(', ') || undefined, image: v.images?.[0]?.href },
		attendance: s.gameInfo?.attendance || undefined,
		broadcasts: [...new Set<string>((s.header?.competitions?.[0]?.broadcasts ?? []).map((b: any) => b.media?.shortName).filter(Boolean))],
		odds: books.length
			? {
					books: [...new Set<string>(books.map((b) => b.provider?.name).filter(Boolean))].sort(),
					homeSpread: average(books.map((b) => b.spread)),
					overUnder: average(books.map((b) => b.overUnder)),
					homeMoneyLine: round(average(books.map((b) => b.homeTeamOdds?.moneyLine))),
					awayMoneyLine: round(average(books.map((b) => b.awayTeamOdds?.moneyLine)))
				}
			: undefined,
		standings: (s.standings?.groups ?? []).flatMap((g: any) => {
			// "2026 NFC West Standings" → "NFC West"
			const group = (g.header ?? '').replace('Standings', '').split(' ').filter((w: string) => w && isNaN(Number(w))).join(' ');
			return (g.standings?.entries ?? []).map((e: any, i: number) => ({ teamID: e.id, group, position: i + 1, record: e.stats?.find((x: any) => x.name === 'overall')?.displayValue }));
		}),
		winProbability,
		leaders: (s.leaders ?? []).flatMap((team: any) =>
			(team.leaders ?? []).flatMap((c: any) => {
				const top = c.leaders?.[0];
				if (!team.team?.id || !top?.athlete?.displayName) return [];
				return [{
					teamID: team.team.id,
					category: c.displayName ?? '',
					athlete: top.athlete.displayName,
					shortName: top.athlete.shortName,
					position: top.athlete.position?.abbreviation,
					headshot: top.athlete.headshot?.href,
					mainValue: top.mainStat?.value,
					summary: top.summary
				}];
			})
		),
		recap: recap(s.article)
	};
}

/** ESPN's written story as plain paragraphs; its HTML is reduced to text, never rendered. */
function recap(a: any): Overview['recap'] {
	if (!a?.headline || !a.story) return;
	const doc = new DOMParser().parseFromString(a.story.replace(/<\/p>|<br\s*\/?>/gi, '\n'), 'text/html');
	const paragraphs = (doc.body.textContent ?? '').split('\n').map((p) => p.trim()).filter(Boolean);
	return paragraphs.length ? { headline: a.headline, paragraphs } : undefined;
}

export type MarkKind = 'run' | 'pass' | 'incomplete' | 'loss' | 'penalty';
export type PlayMark = { start: number; end: number; kind: MarkKind; play: Play };

/** Reads ESPN's play type; kicks, timeouts and period markers aren't drawn. */
export function playMark(play: Play): PlayMark | undefined {
	const type = play.type?.toLowerCase();
	if (play.startYardLine === undefined || !type) return;
	const has = (s: string) => type.includes(s);
	const kind: MarkKind | undefined =
		has('pass') && has('incomplet') ? 'incomplete'
		: has('pass') || has('interception') ? 'pass'
		: has('sack') ? 'loss'
		: has('rush') || has('run') || has('scramble') ? 'run'
		: has('penalty') ? 'penalty'
		: undefined;
	return kind && { start: play.startYardLine, end: play.endYardLine ?? play.startYardLine, kind, play };
}

export type FieldState = {
	/** Yards from the home goal line. */
	ball: number;
	offenseTeamID?: string;
	lineToGain?: number;
	marks: PlayMark[];
	down?: string;
	ballOn?: string;
	drive?: string;
	lastPlay?: Play;
};

const isSnap = (p: Play) => p.spot !== undefined && (p.endYardLine ?? p.startYardLine) !== undefined;

/** "13 plays, 61 yards, 5:46" → "13 plays, 61 yds", as ESPN shortens it. */
const shortDrive = (s?: string) => (s ? s.split(', ').slice(0, 2).join(', ').replace('yards', 'yds').replace('yard', 'yd') : undefined);

export function fieldState(game: Game, drives: Drive[] | undefined): FieldState | undefined {
	const s = game.situation;
	if (game.status === 'live' && s?.yardLine !== undefined) {
		const ball = s.yardLine;
		const last = drives?.at(-1);
		const drive = last?.teamID === s.possessionTeamID ? last : undefined;
		const [down, ballOn] = s.shortDownAndDistance?.split(' · ') ?? [];
		return {
			ball,
			offenseTeamID: s.possessionTeamID,
			// The home offence moves toward the away goal (yard line rising), the away offence the other way.
			lineToGain: s.distance === undefined ? undefined : Math.min(100, Math.max(0, s.possessionTeamID === game.home.team.id ? ball + s.distance : ball - s.distance)),
			marks: (drive?.plays ?? []).map(playMark).filter((m) => m !== undefined),
			down,
			ballOn,
			drive: shortDrive(drive?.summary),
			lastPlay: drive?.plays.findLast(isSnap)
		};
	}
	// After the whistle, show where the last snap ended, as iOS does.
	const drive = drives?.findLast((d) => d.plays.some(isSnap));
	const last = drive?.plays.findLast(isSnap);
	const ball = last && (last.endYardLine ?? last.startYardLine);
	if (!drive || !last || ball === undefined) return;
	const [down, ballOn] = last.spot?.split(' at ') ?? [];
	return { ball, offenseTeamID: drive.teamID, marks: drive.plays.map(playMark).filter((m) => m !== undefined), down, ballOn, drive: shortDrive(drive.summary), lastPlay: last };
}

export const yardsGained = (p: Play, homeOffense: boolean) =>
	p.startYardLine === undefined || p.endYardLine === undefined ? undefined : homeOffense ? p.endYardLine - p.startYardLine : p.startYardLine - p.endYardLine;

// Gamecast helpers, as Gamecast.swift.

/** Period and game ends ("End Period", "End of Game"). */
export const isMarker = (p: Play) => /^(end|period)/i.test(p.type ?? '');

/** The play's team. Football files timeouts under the drive's team, so read "Timeout #1 by SF" instead. */
export function playTeam(p: Play, g: Game): Team | undefined {
	const teams = [g.away.team, g.home.team];
	const caller = /timeout/i.test(p.type ?? '') ? p.text.match(/ by ([A-Za-z]+)/)?.[1] : undefined;
	return teams.find((t) => t.abbreviation === caller) ?? teams.find((t) => t.id === p.teamID);
}

/** ESPN's headline over the field, with a finished game always reading "End of Game". */
export function bannerTitle(p: Play, g: Game): string {
	if (g.status === 'final') return 'End of Game';
	if (/timeout/i.test(p.type ?? '')) return 'Timeout';
	if (isMarker(p)) return p.headline ?? (p.text || p.type) ?? 'End of Period';
	return p.headline ?? p.type ?? 'Last Play';
}

export function periodTitle(l: League, n: number): string {
	if (l.periodStyle === 'halves') return n === 1 ? 'First Half' : n === 2 ? 'Second Half' : 'Extra Time';
	if (n <= l.regulationPeriods) return `${l.periodStyle === 'quarters' ? 'Quarter' : 'Period'} ${n}`;
	return n - l.regulationPeriods === 1 ? 'Overtime' : `Overtime ${n - l.regulationPeriods}`;
}

/** Line-up changes and soccer's injury delays: never banner- or list-worthy. */
export const isSkipped = (p: Play) => ['Substitution', 'Start Delay', 'End Delay', 'Stoppage'].includes(p.type ?? '');

/** The team with the ball, inferred from the latest plays (CourtSituation.possession); nil at a break. */
export function possession(plays: Play[], awayID: string, homeID: string): string | undefined {
	const other = (id?: string) => (id === awayID ? homeID : id === homeID ? awayID : undefined);
	for (const play of [...plays].reverse()) {
		const type = (play.type ?? '').toLowerCase();
		if (type.includes('end period') || type.includes('end game')) return;
		const team = play.teamID;
		if (!team) continue;
		if (type.includes('rebound')) return team;
		if (type.includes('turnover') || type.includes('traveling')) return other(team);
		if (type.includes('technical')) continue; // technical free throws don't change possession
		if (type.startsWith('free throw')) {
			// Only the last free throw of a trip ("free throw 2 of 2") hands the ball over, and only when it goes in.
			const words = type.split(' ');
			const last = words.length >= 3 && words.at(-3) === words.at(-1);
			return play.isScoring && last ? other(team) : team;
		}
		if (play.isShot) return play.isScoring ? other(team) : team;
		// Fouls are listed under the fouling team, so the other team has it.
		if (type.includes('foul') && !type.includes('loose ball')) return other(team);
	}
}

export const leagueByID = (id: string | null) => leagues.find((l) => l.id === id) ?? leagues[0];

export const hex = (h?: string) => (h && h.length === 6 ? `#${h}` : '#666');

// Contrast maths, as Contrast.swift: keeps white text readable on team colours.

const channels = (h: string) => [1, 3, 5].map((i) => parseInt(h.replace('#', '').padEnd(6, '0').slice(i - 1, i + 1), 16) / 255);
const toHex = (c: number[]) => '#' + c.map((v) => Math.round(Math.min(1, Math.max(0, v)) * 255).toString(16).padStart(2, '0')).join('');

/** Same hue and saturation, brightness scaled (capped where the brightest channel reaches full). */
export function brightness(h: string, k: number): string {
	const c = channels(h);
	return toHex(c.map((v) => v * Math.min(k, 1 / Math.max(...c, 0.0001))));
}

function whiteRatio(c: number[]): number {
	const linear = (v: number) => (v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4);
	return 1.05 / (0.2126 * linear(c[0]) + 0.7152 * linear(c[1]) + 0.0722 * linear(c[2]) + 0.05);
}

/** Darkened until white text on it, even brightened by `boost` (a backdrop's lightest fold), meets WCAG AA (4.5:1). */
export function readable(h: string, boost = 1): string {
	const ratio = (scale: number) => whiteRatio(channels(brightness(h, scale * boost)));
	if (ratio(1) >= 4.5) return h;
	let low = 0, high = 1;
	for (let i = 0; i < 30; i++) {
		const mid = (low + high) / 2;
		if (ratio(mid) >= 4.5) low = mid;
		else high = mid;
	}
	return brightness(h, low);
}

// League pages: standings, recent results and the days ahead, as ESPNProvider.

export type Standings = { columns: string[]; groups: { name: string; entries: { team: Team; values: string[] }[] }[] };

/** Which ESPN stats each league's table shows, how it's ranked (higher is better, in order), and whether to split by division. */
const standingsSpecs: Record<string, { level?: number; columns: [string, string][]; rankBy: string[] }> = {
	nfl: { level: 3, columns: [['wins', 'W'], ['losses', 'L'], ['ties', 'T'], ['winPercent', 'PCT']], rankBy: ['winPercent', 'wins'] },
	nba: { columns: [['wins', 'W'], ['losses', 'L'], ['winPercent', 'PCT'], ['gamesBehind', 'GB']], rankBy: ['winPercent', 'wins'] },
	nhl: { level: 3, columns: [['gamesPlayed', 'GP'], ['wins', 'W'], ['losses', 'L'], ['otLosses', 'OTL'], ['points', 'PTS']], rankBy: ['points', 'wins'] },
	epl: { columns: [['gamesPlayed', 'GP'], ['wins', 'W'], ['ties', 'D'], ['losses', 'L'], ['pointDifferential', 'GD'], ['points', 'PTS']], rankBy: ['points', 'pointDifferential', 'pointsFor'] }
};

export async function standings(league: League): Promise<Standings> {
	const spec = standingsSpecs[league.id];
	// Standings live under /apis/v2, not the site API. Level 3 splits conferences into divisions.
	const root = await get(`https://site.api.espn.com/apis/v2/sports/${league.path}/standings${spec.level ? `?level=${spec.level}` : ''}`);
	const stat = (e: any, name: string) => e.stats?.find((s: any) => s.name === name);
	// Groups are whichever nodes carry entries: conferences, divisions, or the whole league.
	const groups = (node: any): Standings['groups'] => {
		const entries: any[] | undefined = node.standings?.entries;
		if (!entries) return (node.children ?? []).flatMap(groups);
		const ranked = [...entries].sort((a, b) => {
			for (const name of spec.rankBy) {
				const x = stat(a, name)?.value ?? -Infinity, y = stat(b, name)?.value ?? -Infinity;
				if (x !== y) return y - x;
			}
			return 0;
		});
		return [{ name: node.name ?? '', entries: ranked.map((e) => ({ team: parseTeam(e.team), values: spec.columns.map(([name]) => stat(e, name)?.displayValue ?? '–') })) }];
	};
	return { columns: spec.columns.map(([, label]) => label), groups: groups(root) };
}

/** The league's most recent finals, newest first: the current slate, else stepping back a day at a time, up to a week. */
export async function recentResults(league: League, before: Date): Promise<Game[]> {
	let finals = (await get(`${base}${league.path}/scoreboard`)).events?.map((e: any) => parseEvent(e, league)).filter((g: Game) => g.status === 'final') ?? [];
	for (let back = 1; back <= 7 && finals.length === 0; back++) {
		const day = new Date(before);
		day.setHours(0, 0, 0, 0);
		day.setDate(day.getDate() - back);
		finals = (await scoreboard(league, day)).filter((g) => g.status === 'final');
	}
	return finals.sort((a: Game, b: Game) => b.startDate.getTime() - a.startDate.getTime());
}

/** Every game on the next `days` days, without repeats. */
export async function upcoming(league: League, days: number): Promise<Game[]> {
	const pages = await Promise.all(Array.from({ length: days }, (_, i) => scoreboard(league, startOfDay(i + 1)).catch(() => [])));
	const seen = new Set<string>();
	return pages.flat().filter((g) => g.status === 'scheduled' && !seen.has(g.id) && seen.add(g.id)).sort((a, b) => a.startDate.getTime() - b.startDate.getTime());
}

/** Every team, from each league's standings, for search; loaded once, the first time someone searches. */
let teamsPromise: Promise<{ league: League; team: Team }[]> | undefined;
export function allTeams() {
	teamsPromise ??= Promise.all(leagues.map((l) => standings(l).then((s) => s.groups.flatMap((g) => g.entries.map((e) => ({ league: l, team: e.team })))).catch(() => [])))
		.then((all) => all.flat().sort((a, b) => a.team.displayName.localeCompare(b.team.displayName)));
	return teamsPromise;
}
