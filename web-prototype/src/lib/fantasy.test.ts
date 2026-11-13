// @ts-nocheck: run by Node directly, outside the Svelte app's type setup.
// The same cases as SportsKit's FantasyInsightsTests, so both apps plan byes and trends alike.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { lineupCover, needsCover, seasonTrend, type Player } from './fantasy.ts';

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
