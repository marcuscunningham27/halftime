// @ts-nocheck: run by Node directly, outside the Svelte app's type setup.
// The same cases as SportsKit's FantasyInsightsTests, so both apps plan byes and trends alike.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { lineupCover, needsCover, seasonTrend, parseEspnTeam, parseEspnPoints, type Player } from './fantasy.ts';

const player = (id: string, position: string): Player => ({ id, name: id, position, team: 'X' });

test('cover keeps starters and fills gaps from the bench', () => {
	const [allen, harvey, kraft, goedert, mahomes, lemon] = [['Allen', 'QB'], ['Harvey', 'RB'], ['Kraft', 'TE'], ['Goedert', 'TE'], ['Mahomes', 'QB'], ['Lemon', 'WR']].map(([id, p]) => player(id, p));
	const lineup = [{ label: 'QB', player: allen }, { label: 'RB', player: harvey }, { label: 'TE', player: kraft }, { label: 'FLEX', player: goedert }, { label: 'DEF' }];
	// Allen and Kraft are out: Mahomes takes QB; Goedert slides FLEX→TE so Lemon can take FLEX.
	const cover = lineupCover(lineup, [mahomes, lemon], (p) => p !== allen && p !== kraft);
	assert.deepEqual(cover.map((s) => s.filledBy?.id), ['Mahomes', 'Harvey', 'Goedert', 'Lemon', undefined]);
	assert.deepEqual(cover.filter(needsCover).map((s) => s.label), ['QB', 'TE', 'FLEX', 'DEF']);
	assert.equal(lineupCover(lineup.slice(0, 4), [], () => true).filter(needsCover).length, 0);
});

test('cover does not move starters needlessly', () => {
	const harvey = player('Harvey', 'RB'), najee = player('Najee', 'RB');
	const cover = lineupCover([{ label: 'RB', player: harvey }, { label: 'RB' }], [najee], () => true);
	assert.deepEqual(cover.map((s) => s.filledBy?.id), ['Harvey', 'Najee']);
});

test('season trend averages per week and ranks the gaps', () => {
	const qb = (actual: number, projected: number) => ({ playerID: 'qb', name: 'Passer', position: 'QB', actual, projected });
	const rb = (actual: number, projected: number) => ({ playerID: 'rb', name: 'Runner', position: 'RB', actual, projected });
	const week = (n: number, starters) => ({ week: n, starters, actual: starters.reduce((t, s) => t + s.actual, 0), projected: starters.reduce((t, s) => t + s.projected, 0) });
	const trend = seasonTrend([week(1, [qb(25, 18), rb(5, 10)]), week(2, [qb(20, 19), rb(8, 9)])]);
	assert.equal(trend.actualPerWeek, 29);
	assert.equal(trend.projectedPerWeek, 28);
	assert.deepEqual(trend.gapByPosition.map((g) => g.position), ['RB', 'QB']);
	assert.equal(trend.gapByPosition[0].gap, -3);
	assert.deepEqual(trend.gapByStarter.map((g) => [g.name, g.gap]), [['Runner', -6], ['Passer', 8]]);
});

test('roster finds your players in plays by full or short name, as whole words', async () => {
	const { playersIn, shortName } = await import('./fantasy.ts');
	const players = ['Jayden Daniels', 'Christian McCaffrey', 'Amon-Ra St. Brown', 'Marvin Harrison Jr.'].map((name) => ({ id: name, name }));
	assert.equal(shortName('Marvin Harrison Jr.'), 'M.Harrison');
	assert.deepEqual(playersIn('(Shotgun) J.Daniels pass deep middle to A.Williams to SF 28 for 17 yards', players).map((p) => p.name), ['Jayden Daniels']);
	assert.deepEqual(playersIn('A.St. Brown right end to DET 40 for 5 yards', players).map((p) => p.name), ['Amon-Ra St. Brown']);
	assert.deepEqual(playersIn('AJ.Daniels pass incomplete', players), []);
});

// Shaped like ESPN's league response with view=mTeam, mRoster and mSettings: the same sample as SportsKit's ESPNFantasyTests.
const league = {
	id: 123,
	settings: { name: 'Office League', rosterSettings: { lineupSlotCounts: { 0: 1, 2: 2, 23: 1, 16: 1, 20: 6 } } },
	teams: [
		{ id: 1, location: 'Team', nickname: 'Taco', roster: { entries: [] } },
		{ id: 4, name: "Marcus's Team", roster: { entries: [
			{ lineupSlotId: 0, playerPoolEntry: { player: { id: 3139477, fullName: 'Patrick Mahomes', defaultPositionId: 1, proTeamId: 12, stats: [{ scoringPeriodId: 6, statSourceId: 0, appliedTotal: 21.5 }, { scoringPeriodId: 6, statSourceId: 1, appliedTotal: 19 }] } } },
			{ lineupSlotId: 2, playerPoolEntry: { player: { id: 4241457, fullName: 'Najee Harris', defaultPositionId: 2, proTeamId: 0 } } },
			{ lineupSlotId: 16, playerPoolEntry: { player: { id: -16028, fullName: 'Commanders D/ST', defaultPositionId: 16, proTeamId: 28 } } },
			{ lineupSlotId: 20, playerPoolEntry: { player: { id: 4430807, fullName: 'Malik Nabers', defaultPositionId: 3, proTeamId: 19 } } }
		] } }
	]
};

test('ESPN Fantasy lineups keep slot order and empty slots, and defences have no athlete ID', () => {
	const team = parseEspnTeam(league, '4');
	assert.deepEqual(team.lineup.map((s) => s.label), ['QB', 'RB', 'RB', 'FLEX', 'DEF']);
	assert.deepEqual(team.lineup.map((s) => s.player?.name), ['Patrick Mahomes', 'Najee Harris', undefined, undefined, 'Commanders D/ST']);
	assert.deepEqual(team.bench.map((p) => p.name), ['Malik Nabers']);
	const mahomes = team.lineup[0].player;
	assert.ok(mahomes.team === 'KC' && mahomes.position === 'QB' && mahomes.espnID === '3139477');
	const defence = team.lineup[4].player;
	assert.ok(defence.espnID === undefined && defence.team === 'WSH' && defence.position === 'DEF');
	assert.equal(parseEspnTeam(league, '99'), undefined);
	assert.deepEqual(parseEspnPoints(league, 6, 0), { 3139477: 21.5 });
	assert.deepEqual(parseEspnPoints(league, 6, 1), { 3139477: 19 });
	assert.deepEqual(parseEspnPoints(league, 5, 0), {});
});
