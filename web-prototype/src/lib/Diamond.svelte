<script lang="ts">
	// BaseballDiamondView: an info row (count, outs and batter while live; runs, hits and errors once it's over), the
	// outfield wall in the home colour, mown grass with the home logo, runners glowing in the batting team's colour,
	// earlier balls in play as dots (filled hits, hollow outs) and the latest arcing out with a pulse where it landed.
	// Drawn in ESPN's 250-unit hit-chart space, home plate at (125, 204).
	import { type Game, type Play, type TeamStat, hex, backdropHex, isBaseHit } from './espn';
	let { game, plays, teamStats }: { game: Game; plays: Play[]; teamStats: TeamStat[] } = $props();

	const home = { x: 125, y: 204 }, first = { x: 152.7, y: 176.3 }, second = { x: 125, y: 148.6 }, third = { x: 97.3, y: 176.3 };
	const dirt = '#c29461', track = 'color-mix(in srgb, #c29461, black 15%)';
	const state = $derived(game.status === 'live' ? game.situation?.baseball : undefined);

	/** One entry per at-bat, newest last: its result row and where the ball went. ESPN puts the spot on the result row
	 *  in some games and on the "Ball In Play" pitch in others; a result still to come (live) is the pitch itself. */
	const atBats = $derived.by(() => {
		const list: { play: Play; spot?: { x: number; y: number } }[] = [];
		let inPlay: Play | undefined;
		for (const p of plays) {
			if (p.text.endsWith('In Play')) inPlay = p;
			else if (p.type === 'Play Result') {
				list.push({ play: p, spot: p.location ?? inPlay?.location });
				inPlay = undefined;
			}
		}
		if (inPlay) list.push({ play: inPlay, spot: inPlay.location });
		return list;
	});
	const teamOf = (p: Play) => [game.away.team, game.home.team].find((t) => t.id === p.teamID);
	/** The team at the plate: whoever the latest at-bat belongs to. */
	const batting = $derived(atBats.at(-1) && teamOf(atBats.at(-1)!.play));
	const at = (l: { x: number; y: number }) => ({ x: l.x * 250, y: l.y * 250 });
	const earlier = $derived(atBats.slice(0, -1).filter((a) => a.spot).slice(-7));
	const last = $derived(atBats.at(-1));
	const lastSpot = $derived(last?.spot && at(last.spot));
	/** Fly balls and homers arc; grounders and liners run flat, as on ESPN. */
	const flight = $derived.by(() => {
		if (!last || !lastSpot) return;
		const words = `${last.play.headline ?? last.play.type ?? ''} ${last.play.text}`.toLowerCase();
		const arcs = ['flied', 'fly', 'popped', 'pop', 'homer', 'home run', 'sacrifice fly', 'foul out', 'fouled out'].some((w) => words.includes(w));
		return arcs ? `M${home.x},${home.y} Q${(home.x + lastSpot.x) / 2},${Math.min(home.y, lastSpot.y) - 70} ${lastSpot.x},${lastSpot.y}` : `M${home.x},${home.y} L${lastSpot.x},${lastSpot.y}`;
	});
	const fan = (reach: number, depth: number) => `M${home.x},${home.y} L${home.x - reach},${home.y - reach} Q${home.x},${home.y - depth} ${home.x + reach},${home.y - reach} Z`;
	const diamond = (b: { x: number; y: number }) => `M${b.x},${b.y - 5.5} L${b.x + 5.5},${b.y} L${b.x},${b.y + 5.5} L${b.x - 5.5},${b.y} Z`;
	const runnerColor = $derived(batting ? hex(batting.color) : '#3373ff');
	const stat = (label: string) => teamStats.find((t) => t.label === label);
	const pair = (label: string) => (stat(label) ? `${stat(label)!.away}–${stat(label)!.home}` : undefined);
	const info = $derived(
		state
			? [['Count', `${state.balls}–${state.strikes}`], ['Outs', '●'.repeat(state.outs) + '○'.repeat(Math.max(0, 3 - state.outs))], ['At Bat', state.batter]]
			: [['Runs', game.away.score !== undefined && game.home.score !== undefined ? `${game.away.score}–${game.home.score}` : undefined], ['Hits', pair('Hits')], ['Errors', pair('Errors')]]
	);
	const label = $derived.by(() => {
		const parts: string[] = [];
		if (state) {
			parts.push(`${state.balls} balls, ${state.strikes} strikes, ${state.outs} outs`);
			const bases = [state.onFirst && 'first', state.onSecond && 'second', state.onThird && 'third'].filter(Boolean);
			parts.push(bases.length ? `runners on ${bases.join(', ')}` : 'bases empty');
		}
		if (last) parts.push(last.play.text);
		return parts.join('. ');
	});
</script>

<div class="diamond-wrap" role="img" aria-label={label}>
	<div class="info">
		{#each info as [title, value], i}
			{#if i > 0}<span class="divider"></span>{/if}
			<div class="stat"><span class="title">{title}:</span><span class="value">{value ?? '–'}</span></div>
		{/each}
	</div>
	<svg class="field" viewBox="0 18 250 200" aria-hidden="true">
		<defs>
			<clipPath id="grass"><path d={fan(112, 220)} /></clipPath>
			<linearGradient id="park-light" gradientUnits="userSpaceOnUse" x1="0" y1="30" x2="250" y2="220">
				<stop offset="0" stop-color="white" stop-opacity="0.1" />
				<stop offset="0.5" stop-color="white" stop-opacity="0" />
				<stop offset="1" stop-color="black" stop-opacity="0.12" />
			</linearGradient>
		</defs>
		<!-- The outfield wall in the home team's colour, then the warning track inside it. -->
		<path d="M{home.x - 121},{home.y - 121} Q{home.x},{home.y - 236} {home.x + 121},{home.y - 121}" fill="none" stroke={hex(backdropHex(game.home.team))} stroke-width="8" />
		<path d={fan(118, 230)} fill={track} />
		<!-- Grass mown in stripes, in the football field's turf greens, lit like the court. -->
		<g clip-path="url(#grass)">
			{#each Array.from({ length: 17 }, (_, i) => 20 + i * 12) as band}
				<rect y={band} width="250" height="12.2" fill={Math.floor(band / 12) % 2 === 0 ? '#4ca846' : '#40983c'} />
			{/each}
			<rect width="250" height="250" fill="url(#park-light)" />
		</g>
		<!-- Infield dirt and the grass square inside the bases. -->
		<path d={fan(50, 98)} fill={dirt} />
		<path d="M{home.x},{home.y - 6} L{first.x - 6},{first.y} L{second.x},{second.y + 6} L{third.x + 6},{third.y} Z" fill="#4ca846" />
		<!-- Chalk: foul lines out to the wall and the batter's boxes; the mound with its rubber; the plate's dirt circle. -->
		<path d="M{home.x - 118},{home.y - 118} L{home.x},{home.y} L{home.x + 118},{home.y - 118}" fill="none" stroke="rgba(255,255,255,0.9)" stroke-width="1" />
		<ellipse cx={home.x} cy={home.y} rx="10" ry="7" fill={dirt} />
		<rect x={home.x - 8} y={home.y - 4} width="4" height="8" fill="none" stroke="rgba(255,255,255,0.9)" stroke-width="0.6" />
		<rect x={home.x + 4} y={home.y - 4} width="4" height="8" fill="none" stroke="rgba(255,255,255,0.9)" stroke-width="0.6" />
		<circle cx="125" cy="177" r="6" fill="color-mix(in srgb, {dirt}, white 10%)" />
		<rect x="123" y="176.5" width="4" height="1" fill="rgba(255,255,255,0.9)" />
		<!-- The home team's code on the centre-field wall and its logo on the grass. -->
		<text class="wall" x="125" y="26">{game.home.team.abbreviation}</text>
		<image href={game.home.team.logo} x={125 - 20} y={88 - 20} width="40" height="40" opacity="0.8" />
		{#each [first, second, third] as base, i}
			{@const occupied = [state?.onFirst, state?.onSecond, state?.onThird][i]}
			{#if occupied}
				<!-- A runner: the base glows in the batting team's colour. -->
				<circle cx={base.x} cy={base.y} r="10" fill={runnerColor} fill-opacity="0.35" />
				<path d={diamond(base)} fill={runnerColor} stroke="white" stroke-width="1" />
			{:else}
				<path d={diamond(base)} fill="white" />
			{/if}
		{/each}
		<path d="M{home.x - 3},{home.y - 2} L{home.x + 3},{home.y - 2} L{home.x + 3},{home.y} L{home.x},{home.y + 2.5} L{home.x - 3},{home.y} Z" fill="white" />
		<!-- Earlier balls in play: filled in the team's colour for hits, hollow for outs. -->
		{#each earlier as a}
			{@const s = at(a.spot!)}
			{@const color = hex(teamOf(a.play)?.color)}
			{#if isBaseHit(a.play)}
				<circle cx={s.x} cy={s.y} r="3.5" fill={color} stroke="rgba(255,255,255,0.85)" stroke-width="0.8" />
			{:else}
				<!-- A dark casing under the ring keeps it readable on dirt and grass, whatever the team colour. -->
				<circle cx={s.x} cy={s.y} r="3.5" fill="none" stroke="rgba(0,0,0,0.55)" stroke-width="3" />
				<circle cx={s.x} cy={s.y} r="3.5" fill="none" stroke="color-mix(in srgb, {color}, white 45%)" stroke-width="1.5" />
			{/if}
		{/each}
		{#if flight && lastSpot}
			<path d={flight} fill="none" stroke="rgba(255,255,255,0.9)" stroke-width="3" stroke-linecap="round" />
			<path d={flight} fill="none" stroke="color-mix(in srgb, {runnerColor}, white 20%)" stroke-width="1.6" stroke-linecap="round" />
			<circle cx={lastSpot.x} cy={lastSpot.y} r="4.5" fill="none" stroke="white" stroke-width="1.2" />
			{#key last?.play.id}
				<circle class="pulse" cx={lastSpot.x} cy={lastSpot.y} r="3.2" fill="none" stroke-width="1.3" stroke={last && isBaseHit(last.play) ? `color-mix(in srgb, ${runnerColor}, white 30%)` : 'white'} />
			{/key}
		{/if}
	</svg>
	{#if state?.pitcher}<p class="pitcher">Pitching: {state.pitcher}</p>{/if}
</div>

<style>
	.diamond-wrap {
		display: flex;
		flex-direction: column;
		gap: 10px;
		align-items: center;
	}
	.info {
		display: flex;
		align-items: center;
		width: 100%;
		padding-bottom: 4px;
	}
	.divider {
		width: 1px;
		height: 34px;
		background: var(--separator);
	}
	.stat {
		flex: 1;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 2px;
		min-width: 0;
	}
	.title {
		font-size: var(--caption);
		font-weight: 500;
		color: var(--secondary);
		text-transform: uppercase;
	}
	.value {
		font-size: var(--title3);
		font-weight: 500;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
		max-width: 100%;
	}
	/* SwiftUI's rotation3DEffect(22°, x axis, perspective 0.5), at most 420pt wide. */
	.field {
		display: block;
		width: 100%;
		max-width: 420px;
		transform: perspective(700px) rotateX(22deg);
	}
	.wall {
		font: 900 7px system-ui;
		font-stretch: expanded;
		fill: rgba(255, 255, 255, 0.9);
		text-anchor: middle;
		dominant-baseline: central;
	}
	.pulse {
		transform-box: fill-box;
		transform-origin: center;
		animation: pulse 1.4s ease-out infinite;
	}
	@keyframes pulse {
		from { transform: scale(1); opacity: 1; }
		to { transform: scale(3.9); opacity: 0; }
	}
	.pitcher {
		margin: 0;
		font-size: var(--caption);
		color: var(--secondary);
	}
	@media (prefers-reduced-motion: reduce) {
		.pulse { animation: none; }
	}
</style>
