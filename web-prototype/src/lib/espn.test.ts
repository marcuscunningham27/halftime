// @ts-nocheck: run by Node directly, outside the Svelte app's type setup.
// Run with `npm test` (Node's own test runner, which reads TypeScript directly).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { possession, readable, brightness, type Play } from './espn.ts';

const play = (type: string, teamID: string, extra: Partial<Play> = {}): Play => ({ id: type, text: type, type, teamID, isScoring: false, isShot: false, period: 1, clock: '', ...extra });

test('possession follows rebounds, makes, turnovers and the last free throw', () => {
	assert.equal(possession([play('Defensive Rebound', 'A')], 'A', 'H'), 'A');
	assert.equal(possession([play('Jump Shot', 'A', { isShot: true, isScoring: true })], 'A', 'H'), 'H');
	assert.equal(possession([play('Jump Shot', 'A', { isShot: true })], 'A', 'H'), 'A');
	assert.equal(possession([play('Bad Pass Turnover', 'H')], 'A', 'H'), 'A');
	assert.equal(possession([play('Free Throw 1 of 2', 'A', { isScoring: true })], 'A', 'H'), 'A');
	assert.equal(possession([play('Free Throw 2 of 2', 'A', { isScoring: true })], 'A', 'H'), 'H');
	assert.equal(possession([play('Shooting Foul', 'H')], 'A', 'H'), 'A');
	assert.equal(possession([play('Defensive Rebound', 'A'), play('Technical Foul', 'H')], 'A', 'H'), 'A');
	assert.equal(possession([play('Defensive Rebound', 'A'), play('End Period', 'A')], 'A', 'H'), undefined);
});

test('readable darkens pale team colours and leaves dark ones alone', () => {
	const luminance = (h: string) => {
		const [r, g, b] = [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16) / 255).map((v) => (v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4));
		return 0.2126 * r + 0.7152 * g + 0.0722 * b;
	};
	const whiteRatio = (h: string) => 1.05 / (luminance(h) + 0.05);
	assert.equal(readable('#2d6526'), '#2d6526');
	const gold = readable('#ffb81c', 1.225); // Bruins gold, at the game page's lightest fold
	assert.ok(whiteRatio(brightness(gold, 1.225)) >= 4.49, `white on ${gold} is too faint`);
	assert.notEqual(gold, '#ffb81c');
});
