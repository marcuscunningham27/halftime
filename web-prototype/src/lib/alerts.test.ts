// @ts-nocheck: run by Node directly, outside the Svelte app's type setup.
// Cases from SportsKit's NotificationTests, so both apps alert alike.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { EventDetector, isQuiet, compactScore } from './alerts.ts';

const league = { id: 'nfl', name: 'NFL', abbreviation: 'NFL', path: '', regulationPeriods: 4, periodStyle: 'quarters' };
const team = (id) => ({ id, abbreviation: id, displayName: id, shortName: id });
const game = (over = {}) => ({
	id: '1', league, startDate: new Date(), status: 'live', period: 2, clock: '7:00', statusDetail: '7:00 - 2nd', statusName: 'STATUS_IN_PROGRESS',
	home: { team: team('SF'), score: 7, periodScores: [] }, away: { team: team('WSH'), score: 3, periodScores: [] }, broadcasts: [], ...over
});

test('first sighting only records; kickoff, scores, lead changes and finals fire once', () => {
	const d = new EventDetector();
	assert.deepEqual(d.events(undefined, game()), []);
	assert.deepEqual(d.events(game({ status: 'scheduled', home: { team: team('SF'), periodScores: [] }, away: { team: team('WSH'), periodScores: [] } }), game({ home: { team: team('SF'), score: 0, periodScores: [] }, away: { team: team('WSH'), score: 0, periodScores: [] } })).map((e) => e.type), ['gameStart']);
	const lead = d.events(game(), game({ away: { team: team('WSH'), score: 10, periodScores: [] } }));
	assert.deepEqual(lead.map((e) => e.type), ['scoreUpdate', 'leadChange']);
	assert.equal(lead[1].body, 'WSH lead WSH 10 – 7 SF · 7:00 - 2nd');
	assert.deepEqual(d.events(game(), game({ status: 'final' })).map((e) => e.type), ['final']);
});

test('red zone fires once per drive', () => {
	const d = new EventDetector();
	const rz = (team) => game({ situation: { possessionTeamID: team, isRedZone: true, downAndDistance: '1st & 10 at SF 15' } });
	assert.deepEqual(d.events(undefined, rz('WSH')), []); // first sighting records the drive
	assert.deepEqual(d.events(rz('WSH'), rz('WSH')), []);
	assert.deepEqual(d.events(rz('WSH'), rz('SF')).map((e) => e.body), ['SF in the red zone: 1st and 10 at SF 15']);
});

test('quiet hours can cross midnight', () => {
	const at = (h, m = 0) => new Date(2026, 10, 13, h, m);
	assert.equal(isQuiet(at(23), true, 22 * 60, 7 * 60), true);
	assert.equal(isQuiet(at(6, 59), true, 22 * 60, 7 * 60), true);
	assert.equal(isQuiet(at(7), true, 22 * 60, 7 * 60), false);
	assert.equal(isQuiet(at(23), false, 22 * 60, 7 * 60), false);
	assert.equal(isQuiet(at(13), true, 12 * 60, 14 * 60), true);
});

test('menu bar score is compact', () => {
	assert.equal(compactScore(game()), 'WSH 3 – 7 SF · Q2');
	assert.equal(compactScore(game({ statusName: 'STATUS_HALFTIME' })), 'WSH 3 – 7 SF · Half');
	assert.equal(compactScore(game({ period: 5 })), 'WSH 3 – 7 SF · OT');
});
