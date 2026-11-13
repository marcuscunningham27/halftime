// Ported from SportsKit's GameFacts and QuickQuestion: game summaries and quick answers built straight from ESPN's
// numbers, with no model involved, so they can't get a score, a player or a stat wrong.
import { periodTitle, type Game, type GameDetail, type Leader, type Play, type BoxScore } from './espn.ts';

const name = (id: string | undefined, g: Game) => (id === g.home.team.id ? g.home.team.shortName : id === g.away.team.id ? g.away.team.shortName : '—');
/** "Quarter 3, 4:12", or just the period where there's no clock (baseball). */
const when = (p: Play, g: Game) => (p.clock ? `${periodTitle(g.league, p.period)}, ${p.clock}` : periodTitle(g.league, p.period));
/** "32 points" for a bare number, else the full line with its category: "21/29, 264 YDS, 1 TD (passing yards)". */
const stat = (l: Leader) => (/^\d+$/.test(l.line) ? `${l.line} ${l.category.toLowerCase()}` : `${l.line} (${l.category.toLowerCase()})`);
export const leadingNumber = (line: string) => {
	const m = line.match(/^[\d.]+/);
	return m ? Number(m[0]) : -1;
};
/** "points" → "point", "rebounder" → "rebound", "scorer" → "score": enough to match leader categories. */
const stem = (w: string) => {
	for (const suffix of ['ers', 'er', 's']) if (w.length > suffix.length + 3 && w.endsWith(suffix)) return w.slice(0, -suffix.length);
	return w;
};
const words = (s: string) => s.toLowerCase().split(/[^\p{L}]+/u).filter(Boolean);

// MARK: Sentences

function state(g: Game): string {
	const a = g.away.score ?? 0, h = g.home.score ?? 0;
	const [lead, trail] = a >= h ? [g.away, g.home] : [g.home, g.away];
	const high = Math.max(a, h), low = Math.min(a, h);
	if (g.status === 'final') {
		const overtime = g.statusDetail.includes('OT') || g.statusDetail.includes('SO') ? ' in overtime' : '';
		return a === h ? `${g.away.team.shortName} and ${g.home.team.shortName} drew ${a}–${h}.` : `${lead.team.shortName} beat ${trail.team.shortName} ${high}–${low}${overtime}.`;
	}
	return a === h
		? `${g.away.team.shortName} and ${g.home.team.shortName} are tied at ${a} (${g.statusDetail}).`
		: `${lead.team.shortName} lead ${trail.team.shortName} ${high}–${low} (${g.statusDetail}).`;
}

/** Each team's first listed leader, e.g. "Gilgeous-Alexander (Thunder) 32 points". */
function topPerformers(g: Game, d: GameDetail): string | undefined {
	const parts = [g.away.team, g.home.team].flatMap((t) => {
		const l = d.overview.leaders.find((x) => x.teamID === t.id);
		return l ? [`${l.athlete} (${t.shortName}) ${stat(l)}`] : [];
	});
	return parts.length ? `Top performers: ${parts.join('; ')}.` : undefined;
}

/** Football: who has the ball and where; baseball: count, outs and runners. */
function situation(g: Game): string | undefined {
	const s = g.situation;
	if (!s) return;
	if (s.baseball) {
		const b = s.baseball;
		const runners = [b.onFirst && 'first', b.onSecond && 'second', b.onThird && 'third'].filter(Boolean);
		return `${b.outs === 1 ? '1 out' : `${b.outs} outs`}, ${b.balls}-${b.strikes} count, ${runners.length ? `runners on ${runners.join(' and ')}` : 'bases empty'}.`;
	}
	if (!s.possessionTeamID || !s.downAndDistance) return;
	return `${name(s.possessionTeamID, g)} have the ball, ${s.downAndDistance}${s.isRedZone ? ' in the red zone' : ''}.`;
}

/** The period the winner (or current leader) won by the most. */
function decidingPeriod(g: Game): string | undefined {
	const away = g.away.periodScores, home = g.home.periodScores;
	const a = g.away.score, h = g.home.score;
	if (away.length < 2 || away.length !== home.length || a === undefined || h === undefined || a === h) return;
	const margins = away.map((x, i) => (a > h ? x - home[i] : home[i] - x));
	const best = margins.reduce((bi, m, i) => (m > margins[bi] ? i : bi), 0);
	if (margins[best] <= 0) return;
	const team = a > h ? g.away.team.shortName : g.home.team.shortName;
	return `${team} did the most damage in ${periodTitle(g.league, best + 1)}, winning it ${Math.max(away[best], home[best])}–${Math.min(away[best], home[best])}.`;
}

/** Unanswered scoring streaks, oldest first, from the running score on each scoring play. */
function scoringRuns(g: Game, d: GameDetail): { team: string; points: number; period: number }[] {
	const runs: { team: string; points: number; period: number }[] = [];
	let prev = [0, 0];
	for (const p of d.plays) {
		if (!p.isScoring || p.awayScore === undefined || p.homeScore === undefined) continue;
		const da = p.awayScore - prev[0], dh = p.homeScore - prev[1];
		prev = [p.awayScore, p.homeScore];
		const [team, points] = da > 0 && dh === 0 ? [g.away.team.id, da] : dh > 0 && da === 0 ? [g.home.team.id, dh] : [undefined, 0];
		if (!team) continue;
		const last = runs.at(-1);
		if (last?.team === team) last.points += points;
		else runs.push({ team, points, period: p.period });
	}
	return runs;
}

/** A few plain sentences: where a live game stands, or how a finished one was won. */
export function summary(g: Game, d: GameDetail): string {
	const sentences = [state(g)];
	const top = topPerformers(g, d);
	if (top) sentences.push(top);
	if (g.status === 'live') {
		const run = scoringRuns(g, d).at(-1);
		const last = d.plays.findLast((p) => p.isScoring);
		if (g.league.sport === 'basketball' && run && run.points >= 6) sentences.push(`${name(run.team, g)} are on a ${run.points}–0 run.`);
		else if (last) sentences.push(`Latest score: ${last.text} (${when(last, g)}).`);
		const s = situation(g);
		if (s) sentences.push(s);
	} else {
		const p = decidingPeriod(g);
		if (p) sentences.push(p);
	}
	return sentences.join(' ');
}

// MARK: Quick answers

export type QuickKind =
	| { kind: 'leaders'; categories: string[] }
	| { kind: 'teamStats'; labels: string[] }
	| { kind: 'scoring' }
	| { kind: 'biggestRun' }
	| { kind: 'decidingPeriod' }
	| { kind: 'scoringDrives' }
	| { kind: 'boxRows'; anchor: string; columns: string[]; firstOnly: boolean }
	| { kind: 'plays'; types: string[] }
	/** Needs judgement: always goes to the model. */
	| { kind: 'model' };
export type QuickQuestion = { text: string; ask: QuickKind };

const q = (text: string, ask: QuickKind): QuickQuestion => ({ text, ask });
/** Four questions that suit the sport's stats. */
export function quickQuestions(leagueID: string): QuickQuestion[] {
	switch (leagueID) {
		case 'nfl': case 'cfb': return [
			q('Who had the most yards?', { kind: 'leaders', categories: ['passing yards', 'rushing yards', 'receiving yards'] }),
			q('Who were the top passers?', { kind: 'boxRows', anchor: 'C/ATT', columns: ['C/ATT', 'YDS', 'TD', 'INT'], firstOnly: false }),
			q('How did turnovers change the game?', { kind: 'teamStats', labels: ['Turnovers', 'Fumbles lost', 'Interceptions thrown'] }),
			q('What were the key scoring drives?', { kind: 'scoringDrives' })
		];
		case 'nba': case 'wnba': return [
			q("Who's the top scorer?", { kind: 'leaders', categories: ['points'] }),
			q('How are the teams shooting from three?', { kind: 'teamStats', labels: ['3PT', 'Three Point %'] }),
			q('Who leads in rebounds and assists?', { kind: 'leaders', categories: ['rebounds', 'assists'] }),
			q('What was the biggest run?', { kind: 'biggestRun' })
		];
		case 'mlb': return [
			q('Who drove in the runs?', { kind: 'scoring' }),
			q('How did the starting pitchers do?', { kind: 'boxRows', anchor: 'IP', columns: ['IP', 'H', 'ER', 'BB', 'K'], firstOnly: true }),
			q('Who had the big hits?', { kind: 'plays', types: ['Home Run', 'Triple', 'Double'] }),
			q('Which inning decided it?', { kind: 'decidingPeriod' })
		];
		case 'nhl': return [
			q('Who scored the goals?', { kind: 'scoring' }),
			q('How did the goalies play?', { kind: 'boxRows', anchor: 'SV', columns: ['SA', 'SV', 'GA', 'SV%'], firstOnly: false }),
			q('How did the power plays go?', { kind: 'teamStats', labels: ['Power Play Goals', 'Power Play Opportunities'] }),
			q('Which team controlled the shots?', { kind: 'teamStats', labels: ['Shots', 'Blocked Shots'] })
		];
		case 'epl': case 'ucl': case 'mls': return [
			q('Who scored and when?', { kind: 'scoring' }),
			q('Which team had more of the ball?', { kind: 'teamStats', labels: ['Possession', 'Passes'] }),
			q('Who were the standout players?', { kind: 'model' }),
			q('What were the big chances?', { kind: 'teamStats', labels: ['SHOTS', 'ON GOAL', 'Corner Kicks'] })
		];
		default: return [q('Who were the best players?', { kind: 'leaders', categories: [] }), q('What were the turning points?', { kind: 'model' })];
	}
}

function leaders(categories: string[], g: Game, d: GameDetail): string | undefined {
	const wanted = d.overview.leaders.filter((l) => !categories.length || categories.some((c) => l.category.toLowerCase().includes(c.toLowerCase())));
	if (!wanted.length) return;
	// One line per category, keeping ESPN's order, highest first where the line starts with a number.
	const order = [...new Set(wanted.map((l) => l.category))];
	return order
		.map((cat) => `${cat}: ${wanted.filter((l) => l.category === cat).sort((a, b) => leadingNumber(b.line) - leadingNumber(a.line)).map((l) => `${l.athlete} (${name(l.teamID, g)}) ${l.line}`).join(', ')}.`)
		.join('\n');
}

function teamStats(labels: string[], g: Game, d: GameDetail): string | undefined {
	const seen = new Set<string>();
	const rows = labels.flatMap((label) => {
		const row = d.teamStats.find((t) => t.label.toLowerCase() === label.toLowerCase() && !seen.has(t.label));
		if (!row) return [];
		seen.add(row.label);
		return [row];
	});
	return rows.length ? rows.map((r) => `${r.label}: ${g.away.team.shortName} ${r.away}, ${g.home.team.shortName} ${r.home}.`).join('\n') : undefined;
}

function scoring(g: Game, d: GameDetail): string | undefined {
	const scores = d.plays.filter((p) => p.isScoring);
	if (!scores.length) return d.plays.length ? 'No one has scored yet.' : undefined;
	return scores.map((p) => `${when(p, g)} · ${name(p.teamID, g)}: ${p.text}`).join('\n');
}

function biggestRun(g: Game, d: GameDetail): string | undefined {
	const run = scoringRuns(g, d).reduce<ReturnType<typeof scoringRuns>[number] | undefined>((best, r) => (!best || r.points > best.points ? r : best), undefined);
	return run && `${name(run.team, g)} went on a ${run.points}–0 run in ${periodTitle(g.league, run.period)}.`;
}

function scoringDrives(g: Game, d: GameDetail): string | undefined {
	const drives = d.drives.filter((x) => x.isScore);
	if (!drives.length) return;
	return drives.map((x) => `${x.plays[0] ? periodTitle(g.league, x.plays[0].period) : ''} · ${name(x.teamID, g)}: ${x.result ?? 'Score'} (${x.summary})`).join('\n');
}

/** Rows of the table whose labels include `anchor` (e.g. "IP" for pitchers, "SV" for goalies). */
function boxRows(anchor: string, columns: string[], firstOnly: boolean, g: Game, d: GameDetail): string | undefined {
	const lines = [g.away.team, g.home.team].flatMap((t) => {
		const box = d.boxScores.find((b) => b.teamID === t.id && b.labels.includes(anchor));
		if (!box) return [];
		return (firstOnly ? box.rows.slice(0, 1) : box.rows).map((row) => {
			const stats = columns.flatMap((c) => {
				const i = box.labels.indexOf(c);
				return i >= 0 && i < row.stats.length ? [`${c} ${row.stats[i]}`] : [];
			});
			return `${row.name} (${t.shortName}): ${stats.join(', ')}`;
		});
	});
	return lines.length ? lines.join('\n') : undefined;
}

function plays(types: string[], g: Game, d: GameDetail): string | undefined {
	// Baseball repeats a hit on the pitch row ("Pitch 4 : Ball In Play"); keep the described result row.
	const found = d.plays.filter((p) => (types.includes(p.headline ?? '') || types.includes(p.type ?? '')) && !p.text.startsWith('Pitch'));
	if (!found.length) return d.plays.length ? 'None yet.' : undefined;
	return found.map((p) => `${when(p, g)} · ${name(p.teamID, g)}: ${p.text}`).join('\n');
}

/** The answer to a quick question from the stats, or undefined when only the model can answer it. */
export function answer(question: QuickQuestion, g: Game, d: GameDetail): string | undefined {
	const a = question.ask;
	switch (a.kind) {
		case 'leaders': return leaders(a.categories, g, d);
		case 'teamStats': return teamStats(a.labels, g, d);
		case 'scoring': return scoring(g, d);
		case 'biggestRun': return biggestRun(g, d);
		case 'decidingPeriod': return decidingPeriod(g);
		case 'scoringDrives': return scoringDrives(g, d);
		case 'boxRows': return boxRows(a.anchor, a.columns, a.firstOnly, g, d);
		case 'plays': return plays(a.types, g, d);
		case 'model': return undefined;
	}
}

/** Box score columns a question word asks for, across sports. */
const columns: Record<string, string[]> = {
	point: ['PTS'], rebound: ['REB'], board: ['REB'], assist: ['AST', 'A'], steal: ['STL'], block: ['BLK', 'BS'],
	three: ['3PT'], minute: ['MIN', 'TOI'], turnover: ['TO'], foul: ['PF'], yard: ['YDS'], touchdown: ['TD'],
	catche: ['REC'], reception: ['REC'], carrie: ['CAR'], interception: ['INT'], sack: ['SACKS'], tackle: ['TOT'],
	goal: ['G'], save: ['SV'], shot: ['SOG'], hit: ['H', 'HT'], hits: ['H', 'HT'], strikeout: ['K'],
	rbi: ['RBI'], rbis: ['RBI'], homer: ['HR']
};

/** "passing", "goalies"… from ESPN's category, or batting / pitching for baseball's unnamed tables. */
const tableName = (b: BoxScore) => (!b.category.startsWith('players') ? b.category : b.labels.includes('IP') ? 'pitching' : b.labels.includes('AB') ? 'batting' : b.title);

/** A question naming a player in the box score ("how many rebounds does Booker have?"): the stats it asks for, or
 *  the player's whole line when it names none. Matched on surname, so "Booker" finds Devin Booker. */
function player(question: string, g: Game, d: GameDetail): string | undefined {
	const raw = words(question);
	const all = new Set([...raw, ...raw.map(stem)]);
	const surname = (n: string) => n.toLowerCase().split(/[^\p{L}-]+/u).filter(Boolean).findLast((w) => !['jr', 'sr', 'ii', 'iii', 'iv'].includes(w));
	const tables = d.boxScores.filter((b) => b.rows.some((r) => all.has(surname(r.name) ?? '')));
	if (!tables.length) return;
	const wanted = raw.includes('home') && all.has('run') ? ['HR'] : [...all].flatMap((w) => columns[w] ?? []);
	const lines = new Map<string, string[]>();
	for (const box of tables) {
		for (const row of box.rows.filter((r) => all.has(surname(r.name) ?? ''))) {
			const key = `${row.name} (${name(box.teamID, g)})`;
			if (!lines.has(key)) lines.set(key, []);
			const picked = box.labels.map((_, i) => i).filter((i) => (!wanted.length || wanted.includes(box.labels[i])) && i < row.stats.length);
			if (!picked.length) continue;
			const stats = picked.map((i) => `${row.stats[i]} ${box.labels[i]}`).join(', ');
			lines.get(key)!.push(tables.length > 1 ? `${stats} (${tableName(box)})` : stats);
		}
	}
	const found = [...lines].filter(([, v]) => v.length).map(([k, v]) => `${k}: ${v.join('; ')}.`);
	return found.length ? found.join('\n') : undefined;
}

/** A typed question naming a player, or one of ESPN's leader categories ("most points", "top rebounder"), is
 *  answered from the stats; anything else returns undefined for the model. */
export function answerTyped(question: string, g: Game, d: GameDetail): string | undefined {
	const p = player(question, g, d);
	if (p) return p;
	const asked = new Set(words(question).map(stem));
	// Match on every word of the category, so "Passing Yards" needs both and "Points" just "point".
	const matched = [...new Set(d.overview.leaders.map((l) => l.category))].filter((cat) => {
		const needed = words(cat).map(stem);
		return needed.length > 0 && needed.every((w) => asked.has(w));
	});
	return matched.length ? leaders(matched, g, d) : undefined;
}
