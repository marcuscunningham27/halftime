// Ported from SportsKit's ClaudeService, GamePrompt and FantasyPrompt: the one place the app talks to Claude.
// Prompts are always built from ESPN's and the league's data, and Claude is told not to go beyond it.
// The Swift app can also use Apple's on-device model; that has no Windows equivalent, so here it's Claude only.
import Anthropic from '@anthropic-ai/sdk';
import { getSecret, setSecret } from './secrets';
import type { Game, GameDetail } from './espn';
import { slotPositions, winProbability, severity, type Team, type Player, type Matchup, type News } from './fantasy';

/** Small and fast, as recaps are short and frequent; the same model the Swift app uses. */
export const model = 'claude-haiku-5-5';
const keyName = 'anthropic-api-key';

export const getKey = () => getSecret(keyName);
export const setKey = (key: string) => setSecret(keyName, key.trim() || undefined);

/** A reason Claude can't answer, written for the person reading it. */
export class ClaudeError extends Error {}

/** Haiku 5.5 thinks by default and its thinking counts against max_tokens, so the cap leaves room for thinking plus
 *  a short answer, and effort is low: these are short, plain-text tasks (as ClaudeService.complete). */
async function complete(system: string, user: string): Promise<string> {
	const apiKey = await getKey();
	if (!apiKey) throw new ClaudeError('Add your Anthropic API key in Settings › Summaries to use Claude.');
	// The key is the person's own, typed into their own copy of the app, so calling from the page exposes it to no one else.
	const client = new Anthropic({ apiKey, dangerouslyAllowBrowser: true });
	let response: Anthropic.Message;
	try {
		response = await client.messages.create({
			model,
			max_tokens: 4000,
			output_config: { effort: 'low' },
			system,
			messages: [{ role: 'user', content: user }]
		});
	} catch (e) {
		if (e instanceof Anthropic.AuthenticationError) throw new ClaudeError('Your Anthropic API key was rejected. Check it in Settings › Summaries.');
		if (e instanceof Anthropic.RateLimitError) throw new ClaudeError('Claude is busy right now. Try again in a moment.');
		if (e instanceof Anthropic.APIError) throw new ClaudeError(`Claude couldn’t answer (${e.status ?? 'error'}). ${e.message}`);
		throw new ClaudeError('Couldn’t reach Claude. Check your connection.');
	}
	if (response.stop_reason === 'refusal') throw new ClaudeError('Claude declined to answer this one.');
	const text = response.content.flatMap((b) => (b.type === 'text' ? [b.text] : [])).join('').trim();
	if (!text) throw new ClaudeError(response.stop_reason === 'max_tokens' ? 'Claude ran out of room before answering. Try again.' : 'Claude returned an empty answer.');
	return text;
}

// MARK: Game prompts (GamePrompt)

const recapSystem = `You write short sports recaps for a scores app. Use only the game data you are given: never invent stats, players, quotes or plays that are not in it. Write two short paragraphs, 80 to 120 words in all, in plain prose with no headings, lists or markdown. Lead with the result (or the state of play if the game is still going), then the moments and players that decided it. Use team names as given.`;

const catchUpSystem = `You catch up a fan who has just tuned in to a live game, for a scores app. Use only the game data you are given: never invent stats, players, quotes or plays that are not in it. Write two or three sentences on what has happened so far and the current state of play, then one sentence starting "Watch for" on what matters next, based only on the score, time left and situation given. Plain prose, no markdown, under 90 words.`;

const askSystem = `You answer a fan's question about one game for a scores app. Use only the game data you are given. If the data doesn't answer the question, say you don't have that information; never guess or invent stats, players or plays. Answer in one to three short sentences of plain prose, no markdown.`;

/** The game as plain text for a prompt: only facts from ESPN, nothing derived by the model. */
export function gameData(g: Game, d: GameDetail): string {
	const away = g.away, home = g.home;
	const name = (id?: string) => (id === home.team.id ? home.team.shortName : id === away.team.id ? away.team.shortName : '');
	const lines = [
		`${g.league.name}: ${away.team.displayName} at ${home.team.displayName}`,
		`Status: ${g.status === 'final' ? 'Final' : g.status === 'live' ? 'In progress' : 'Not started'} (${g.statusDetail})`,
		`Score: ${away.team.shortName} ${away.score ?? 0}, ${home.team.shortName} ${home.score ?? 0}`
	];
	if (away.periodScores.length) {
		lines.push(`By period: ${away.team.shortName} ${away.periodScores.join(' ')}; ${home.team.shortName} ${home.periodScores.join(' ')}`);
		// Running totals spelled out, so a small model never has to add up who led when.
		let a = 0, h = 0;
		away.periodScores.forEach((ap, i) => {
			a += ap;
			h += home.periodScores[i] ?? 0;
			lines.push(`After period ${i + 1}: ${away.team.shortName} ${a}, ${home.team.shortName} ${h} (${a === h ? 'tied' : `${a > h ? away.team.shortName : home.team.shortName} leading`})`);
		});
	}
	if (g.status === 'live') {
		let now = `Now: period ${g.period}, ${g.clock} left`;
		const s = g.situation;
		if (s?.possessionTeamID) now += `; ${name(s.possessionTeamID)} have the ball`;
		if (s?.downAndDistance) now += `, ${s.downAndDistance}`;
		if (s?.isRedZone) now += ' (red zone)';
		lines.push(now);
	}
	const records = [away, home].flatMap((c) => (c.record ? [`${c.team.shortName} ${c.record}`] : []));
	if (records.length) lines.push(`Records: ${records.join(', ')}`);
	const scoring = d.plays.filter((p) => p.isScoring);
	if (scoring.length) {
		lines.push('\nScoring plays:');
		for (const p of scoring) lines.push(`- P${p.period} ${p.clock} ${name(p.teamID)}: ${p.text}${p.awayScore !== undefined && p.homeScore !== undefined ? ` [${p.awayScore}–${p.homeScore}]` : ''}`);
	}
	if (g.status === 'live' && d.plays.length) {
		lines.push('\nLatest plays:');
		for (const p of d.plays.slice(-8)) lines.push(`- P${p.period} ${p.clock}: ${p.text}`);
	}
	if (d.overview.leaders.length) {
		lines.push('\nLeaders:');
		for (const l of d.overview.leaders) lines.push(`- ${l.category}, ${name(l.teamID)}: ${l.athlete} ${l.line}`);
	}
	if (d.teamStats.length) {
		lines.push(`\nTeam stats (${away.team.shortName} / ${home.team.shortName}):`);
		for (const t of d.teamStats) lines.push(`- ${t.label}: ${t.away} / ${t.home}`);
	}
	return lines.join('\n');
}

/** A short recap of a finished game, or a catch-up on a live one. */
export const recap = (g: Game, d: GameDetail) => complete(g.status === 'live' ? catchUpSystem : recapSystem, gameData(g, d));

/** An answer to a fan's question, from the game data plus the top rows of each box score. */
export function ask(question: string, g: Game, d: GameDetail): Promise<string> {
	const lines = [gameData(g, d)];
	if (d.boxScores.length) {
		lines.push('\nBox score (top 3 per category):');
		for (const b of d.boxScores) {
			lines.push(`${b.title} [${b.labels.join(', ')}]`);
			for (const r of b.rows.slice(0, 3)) lines.push(`- ${r.name}: ${r.stats.join(', ')}`);
		}
	}
	lines.push(`\nQuestion: ${question}`);
	return complete(askSystem, lines.join('\n'));
}

// MARK: Fantasy prompt (FantasyPrompt)

const weekSystem = `You brief a fantasy football manager on their week, for a sports app. Use only the data given: never invent players, injuries, stats or news. In under 120 words of plain prose (no markdown, no lists), say where the matchup stands, then each lineup issue listed and the bench options given for it (suggest only those; if none are given, say a pickup is needed), then anything else in the news that affects this week. If there are no lineup issues, say so. Write flowing sentences, never copy the data's labels or layout. For example: "You're projected 99.1 to 97.4, a 52% chance. Your second RB slot is empty and nobody on your bench can fill it, so you'll need a pickup."`;

/** Can play this week: has an NFL team, isn't on bye, and isn't ruled out. */
const available = (p: Player, week: number, byes: Record<string, number>) => !!p.team && byes[p.team] !== week && severity(p.injury) < 3;

/** The week as plain text; lineup issues and the bench players who can fill each are worked out here, so the model needn't. */
export function weekData(team: Team, week: number, matchup: Matchup | undefined, projections: Record<string, number>, byes: Record<string, number>, news: Record<string, News[]>): string {
	const describe = (p: Player) => {
		const parts = [`${p.name} (${[p.team, p.position].filter(Boolean).join(' ')})`];
		if (p.team && byes[p.team] === week) parts.push('ON BYE this week');
		if (!p.team) parts.push('no NFL team');
		if (p.injury) parts.push(`status ${p.injury.status}${p.injury.detail ? ` (${p.injury.detail})` : ''}`);
		if (projections[p.id] !== undefined) parts.push(`projected ${projections[p.id].toFixed(1)}`);
		return parts.join(', ');
	};
	const lines = [`Week ${week}`];
	if (matchup) {
		const chance = winProbability(matchup);
		lines.push(matchup.opponent
			? `Matchup: ${matchup.me.teamName} projected ${matchup.me.projected.toFixed(1)} vs ${matchup.opponent.teamName} projected ${matchup.opponent.projected.toFixed(1)}${chance !== undefined ? `, win chance ${Math.round(chance * 100)}%` : ''}`
			: 'Matchup: bye week');
	}
	lines.push('\nStarters:', ...team.lineup.map((s) => `- ${s.label}: ${s.player ? describe(s.player) : 'EMPTY'}`));
	lines.push('\nBench:', ...team.bench.map((p) => `- ${describe(p)}${available(p, week, byes) ? '' : ', UNAVAILABLE'}`));
	const issues = team.lineup.flatMap((slot) => {
		let problem: string;
		const p = slot.player;
		if (p) {
			if (available(p, week, byes)) {
				if (severity(p.injury) !== 2) return [];
				problem = `${p.name} is doubtful`;
			} else problem = p.team && byes[p.team] === week ? `${p.name} is on bye` : `${p.name} is out`;
		} else problem = 'empty';
		const eligible = slotPositions(slot.label);
		const options = team.bench
			.filter((b) => available(b, week, byes) && eligible.includes(b.position ?? ''))
			.sort((a, b) => (projections[b.id] ?? 0) - (projections[a.id] ?? 0))
			.map((b) => `${b.name}${projections[b.id] !== undefined ? ` (${projections[b.id].toFixed(1)})` : ''}`);
		return [`- ${slot.label}: ${problem}; bench options: ${options.length ? options.join(', ') : 'none'}`];
	});
	lines.push('\nLineup issues:', ...(issues.length ? issues : ['- none']));
	const players = [...team.lineup.flatMap((s) => (s.player ? [s.player] : [])), ...team.bench];
	const recent = players.flatMap((p) => {
		const n = news[p.id]?.[0];
		return n && Date.now() - n.published.getTime() < 5 * 86_400_000 ? [`- ${p.name}: ${n.headline}`] : [];
	});
	if (recent.length) lines.push('\nRecent news:', ...recent);
	return lines.join('\n');
}

/** A briefing on your fantasy week: matchup, lineup gaps and injuries, and news that matters. */
export const weekBriefing = (...args: Parameters<typeof weekData>) => complete(weekSystem, weekData(...args));

