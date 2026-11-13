// @ts-nocheck: run by Node directly, outside the Svelte app's type setup.
// The same cases as SportsKit's GameFactsTests, so both apps answer from the stats alike.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { summary, answer, answerTyped, leadingNumber, quickQuestions } from './facts.ts';

const nba = { id: 'nba', name: 'NBA', abbreviation: 'NBA', path: '', sport: 'basketball', regulationPeriods: 4, periodStyle: 'quarters' };
const okc = { id: '25', abbreviation: 'OKC', displayName: 'Oklahoma City Thunder', shortName: 'Thunder' };
const sas = { id: '24', abbreviation: 'SA', displayName: 'San Antonio Spurs', shortName: 'Spurs' };
const sum = (a) => a.reduce((x, y) => x + y, 0);
const game = (status, away, home, statusDetail = 'Final') => ({
	id: '1', league: nba, startDate: new Date(), status, period: away.length, clock: '4:12', statusDetail, statusName: '', broadcasts: [],
	home: { team: sas, score: sum(home), periodScores: home }, away: { team: okc, score: sum(away), periodScores: away }
});
const basket = (id, team, away, home, period = 2) => ({ id, text: `${team.shortName} basket`, period, clock: '5:00', teamID: team.id, isScoring: true, awayScore: away, homeScore: home, type: 'Jump Shot', isShot: true });
const detail = {
	plays: [basket('1', okc, 2, 0), basket('2', sas, 2, 3), basket('3', sas, 2, 5), basket('4', sas, 2, 8), basket('5', okc, 4, 8)],
	drives: [],
	boxScores: [{ teamID: '24', category: 'pitching', title: '', labels: ['IP', 'H', 'ER', 'K'], rows: [{ id: 'p', name: 'Ace', stats: ['6.0', '4', '2', '7'] }, { id: 'r', name: 'Relief', stats: ['1.0', '0', '0', '1'] }] }],
	teamStats: [{ label: '3PT', away: '12-30', home: '9-35' }],
	overview: { leaders: [
		{ teamID: '25', category: 'Points', athlete: 'Shai Gilgeous-Alexander', line: '32' },
		{ teamID: '24', category: 'Points', athlete: 'Stephon Castle', line: '24' },
		{ teamID: '25', category: 'Rebounds', athlete: 'Chet Holmgren', line: '11' }
	] }
};
const ask = (a) => answer({ text: '', ask: a }, game('final', [25, 31, 30, 30], [26, 16, 32, 30]), detail);

test('final summary states the result, leaders and deciding period', () => {
	const text = summary(game('final', [25, 31, 30, 30], [26, 16, 32, 30]), detail);
	assert.ok(text.startsWith('Thunder beat Spurs 116–104.'));
	assert.ok(text.includes('Shai Gilgeous-Alexander (Thunder) 32 points; Stephon Castle (Spurs) 24 points.'));
	assert.ok(text.includes('Thunder did the most damage in Quarter 2, winning it 31–16.'));
});

test('live summary shows the lead and latest score', () => {
	const text = summary(game('live', [20, 10], [20, 6], '4:12 - 2nd'), detail);
	assert.ok(text.startsWith('Thunder lead Spurs 30–26 (4:12 - 2nd).'));
	assert.ok(text.includes('Latest score: Thunder basket (Quarter 2, 5:00).'));
});

test('quick answers come from the stats', () => {
	assert.equal(ask({ kind: 'leaders', categories: ['points'] }), 'Points: Shai Gilgeous-Alexander (Thunder) 32, Stephon Castle (Spurs) 24.');
	assert.ok(leadingNumber('264 YDS') === 264 && leadingNumber('21/29, 264 YDS') === 21);
	assert.equal(ask({ kind: 'teamStats', labels: ['3PT', 'Missing'] }), '3PT: Thunder 12-30, Spurs 9-35.');
	assert.equal(ask({ kind: 'biggestRun' }), 'Spurs went on a 8–0 run in Quarter 2.');
	assert.equal(ask({ kind: 'boxRows', anchor: 'IP', columns: ['IP', 'ER', 'K'], firstOnly: true }), 'Ace (Spurs): IP 6.0, ER 2, K 7');
	assert.equal(ask({ kind: 'model' }), undefined);
	assert.equal(ask({ kind: 'leaders', categories: ['assists'] }), undefined);
	assert.equal(quickQuestions('nba').length, 4);
});

test('typed questions naming a leader category or a player use the stats', () => {
	const g = game('final', [60, 56], [50, 54]);
	assert.equal(answerTyped('Who had the most points?', g, detail), 'Points: Shai Gilgeous-Alexander (Thunder) 32, Stephon Castle (Spurs) 24.');
	assert.equal(answerTyped('top rebounders', g, detail), 'Rebounds: Chet Holmgren (Thunder) 11.');
	assert.equal(answerTyped('Why did the Spurs lose?', g, detail), undefined);
	const box = { ...detail, plays: [], teamStats: [], boxScores: [{ teamID: '24', category: 'players-0', title: 'Spurs', labels: ['MIN', 'PTS', 'REB', 'AST'], rows: [{ id: '1', name: 'Devin Booker', stats: ['34', '23', '4', '6'] }, { id: '2', name: 'Jaren Jackson Jr.', stats: ['30', '18', '9', '1'] }] }] };
	assert.equal(answerTyped('how many rebounds does booker have?', g, box), 'Devin Booker (Spurs): 4 REB.');
	assert.equal(answerTyped('Booker points and assists', g, box), 'Devin Booker (Spurs): 23 PTS, 6 AST.');
	assert.equal(answerTyped('How did Jackson play?', g, box), 'Jaren Jackson Jr. (Spurs): 30 MIN, 18 PTS, 9 REB, 1 AST.');
	assert.ok(answerTyped('most points?', g, box)?.startsWith('Points:'));
});
