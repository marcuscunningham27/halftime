<script lang="ts">
	// SoccerPitchView: the info row, a tilted 105 × 68 m pitch with each team's colour and code behind the goal it
	// defends (away on the left), the home logo in the centre circle, every shot marked by how it ended and each goal's
	// flight, filtered by half and by player.
	import GlassPicker from './GlassPicker.svelte';
	import { type Game, type Shot, type ShotOutcome, type TeamStat, hex, backdropHex } from './espn';
	let { game, shots, teamStats }: { game: Game; shots: Shot[]; teamStats: TeamStat[] } = $props();

	const halves = ['All', '1st Half', '2nd Half'] as const;
	let half = $state<(typeof halves)[number]>('All');
	let shooter = $state('');
	const shooters = $derived([...new Set(shots.map((s) => s.shooter).filter((s): s is string => !!s))].sort());
	const shown = $derived(shots.filter((s) => (half === 'All' || s.period === halves.indexOf(half)) && (!shooter || s.shooter === shooter)));
	// Goals last, so they sit on top of nearby misses.
	const ordered = $derived([...shown].sort((a, b) => Number(a.outcome === 'goal') - Number(b.outcome === 'goal')));

	const outcomes: [ShotOutcome, string][] = [['goal', 'Goal'], ['save', 'Save'], ['offTarget', 'Off Target'], ['block', 'Block']];
	/** "away–home" for a count over each team's shown shots. */
	const pair = (count: (s: Shot[]) => number) =>
		`${count(shown.filter((s) => s.teamID === game.away.team.id))}–${count(shown.filter((s) => s.teamID === game.home.team.id))}`;
	const possession = $derived.by(() => {
		const stat = teamStats.find((t) => t.label.toLowerCase() === 'possession');
		return stat && `${stat.away}–${stat.home}%`;
	});

	// Each end's team band is 8% of the pitch length either side; the pitch itself spans 105 units between them.
	const band = 0.08 * 105;
	const width = 105 + 2 * band;
	/** Shots come in the shooter's attacking frame. Away defends the left goal, so it shoots right; home is turned to face left. */
	function point(l: { x: number; y: number }, teamID: string) {
		const away = teamID === game.away.team.id;
		return { x: band + (away ? l.x : 1 - l.x) * 105, y: (away ? l.y : 1 - l.y) * 68 };
	}
	function flight(s: Shot): string | undefined {
		if (s.outcome !== 'goal' || !s.end) return;
		const from = point(s.location, s.teamID), to = point(s.end, s.teamID);
		const lift = Math.max(8, Math.abs(to.x - from.x) * 0.35);
		return `M${from.x},${from.y} Q${(from.x + to.x) / 2},${Math.min(from.y, to.y) - lift} ${to.x},${to.y}`;
	}
	const awayBand = $derived(hex(backdropHex(game.away.team)));
	const homeBand = $derived(hex(backdropHex(game.home.team)));
	const label = $derived('Shot map: ' + outcomes.map(([o, title]) => `${shown.filter((s) => s.outcome === o).length} ${title.toLowerCase()}`).join(', '));
</script>

{#snippet marker(outcome: ShotOutcome, size: number, x = 0, y = 0)}
	<!-- ESPN's shot icons: a white disc showing how the shot ended. x and y place it when drawn inside the pitch. -->
	<svg class="marker" viewBox="-10 -10 20 20" {x} {y} width={size} height={size} overflow="visible" aria-hidden="true">
		<circle r="9.2" fill="white" stroke="rgba(0,0,0,0.75)" stroke-width="1.3" />
		{#if outcome === 'goal'}
			<circle r="5.6" fill="none" stroke="rgba(0,0,0,0.8)" stroke-width="1.2" />
			<path d="M0,-2.4 L2.3,-0.7 L1.4,2 L-1.4,2 L-2.3,-0.7 Z M0,-2.4V-5.6 M2.3,-0.7 L5.3,-1.7 M1.4,2 L3.3,4.5 M-1.4,2 L-3.3,4.5 M-2.3,-0.7 L-5.3,-1.7" fill="rgba(0,0,0,0.8)" stroke="rgba(0,0,0,0.8)" stroke-width="0.9" />
		{:else if outcome === 'save'}
			<circle r="4.6" fill="none" stroke="rgba(0,0,0,0.8)" stroke-width="1.8" />
			<path d="M-3.2,3.2 L3.2,-3.2" stroke="rgba(0,0,0,0.8)" stroke-width="1.8" />
		{:else if outcome === 'block'}
			<circle r="2.5" fill="rgba(0,0,0,0.8)" />
		{/if}
	</svg>
{/snippet}

<div class="pitch-wrap">
	<div class="info">
		{#each [['Shots', pair((s) => s.length)], ['On Target', pair((s) => s.filter((x) => x.outcome === 'goal' || x.outcome === 'save').length)], ['Possession', possession]] as [title, value], i}
			{#if i > 0}<span class="divider"></span>{/if}
			<div class="stat"><span class="title">{title}:</span><span class="value">{value ?? '–'}</span></div>
		{/each}
	</div>

	<div class="tilt" role="img" aria-label={label}>
		<svg viewBox="0 0 {width} 68" aria-hidden="true">
			<rect width={band} height="68" fill={awayBand} />
			<rect x={band + 105} width={band} height="68" fill={homeBand} />
			{#each { length: 6 } as _, i}
				<rect x={band + i * 17.5} width="17.6" height="68" fill={i % 2 ? '#4ca846' : '#40983c'} />
			{/each}
			<g fill="none" stroke="rgba(255,255,255,0.85)" stroke-width="0.4">
				<rect x={band} width="105" height="68" />
				<path d="M{band + 52.5},0V68" />
				<circle cx={band + 52.5} cy="34" r="9.15" />
				{#each [true, false] as left}
					<rect x={left ? band : band + 105 - 16.5} y={34 - 20.15} width="16.5" height="40.3" />
					<rect x={left ? band : band + 105 - 5.5} y={34 - 9.15} width="5.5" height="18.3" />
					<circle cx={band + (left ? 11 : 94)} cy="34" r="0.4" fill="rgba(255,255,255,0.85)" />
				{/each}
			</g>
			<text class="endzone" transform="translate({band / 2},34) rotate(-90)">{game.away.team.abbreviation}</text>
			<text class="endzone" transform="translate({width - band / 2},34) rotate(90)">{game.home.team.abbreviation}</text>
			<image href={game.home.team.logo} x={width / 2 - 8.2} y={34 - 8.2} width="16.4" height="16.4" opacity="0.8" />
			{#each shown as shot (shot.id)}
				{@const d = flight(shot)}
				{#if d}<path {d} fill="none" stroke="rgba(255,255,255,0.9)" stroke-width="0.55" stroke-linecap="round" stroke-dasharray="0.4 1.5" />{/if}
			{/each}
			{#each ordered as shot (shot.id)}
				{@const at = point(shot.location, shot.teamID)}
				{@const size = shot.outcome === 'goal' ? 4.1 : 3.3}
				<g><title>{shot.text}</title>{@render marker(shot.outcome, size, at.x - size / 2, at.y - size / 2)}</g>
			{/each}
		</svg>
		<!-- The pitch's front edge in each team's colour at its end, for the football field's raised look. -->
		<div class="edge">
			<span style:flex={band} style:background={awayBand}></span>
			<span style:flex="105" style:background="#40983c"></span>
			<span style:flex={band} style:background={homeBand}></span>
		</div>
	</div>

	<div class="filters">
		<GlassPicker options={[...halves]} bind:selected={half} />
		<select class="glass" bind:value={shooter} aria-label="Player">
			<option value="">All Players</option>
			{#each shooters as name}<option value={name}>{name}</option>{/each}
		</select>
	</div>
	<div class="key">
		{#each outcomes as [outcome, title]}
			<span>{@render marker(outcome, 16)}{title}</span>
		{/each}
	</div>
</div>

<style>
	.pitch-wrap {
		display: flex;
		flex-direction: column;
		gap: 10px;
	}
	.info {
		display: flex;
		align-items: center;
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
	}
	/* SwiftUI's rotation3DEffect(22°, x axis, perspective 0.5), at most 260pt tall. */
	.tilt {
		width: 100%;
		max-width: calc(260px * 121.8 / 68);
		margin: 0 auto;
		border-radius: 8px;
		overflow: hidden;
		transform: perspective(700px) rotateX(22deg);
	}
	.tilt > svg {
		display: block;
		width: 100%;
	}
	.endzone {
		font: 900 4.2px system-ui;
		font-stretch: expanded;
		letter-spacing: 0.08em;
		fill: rgba(255, 255, 255, 0.9);
		text-anchor: middle;
		dominant-baseline: central;
	}
	.edge {
		display: flex;
		height: 7px;
		filter: brightness(0.75);
	}
	.filters {
		display: flex;
		justify-content: space-between;
		align-items: center;
		gap: 12px;
	}
	select {
		font: inherit;
		font-size: var(--subheadline);
		color: var(--label);
		padding: 6px 12px;
		border-radius: 999px;
		appearance: none;
		-webkit-appearance: none;
	}
	select option {
		color: initial;
	}
	.key {
		display: flex;
		justify-content: center;
		flex-wrap: wrap;
		gap: 6px;
	}
	.key span {
		display: flex;
		align-items: center;
		gap: 5px;
		padding: 5px 10px;
		border-radius: 999px;
		background: rgba(255, 255, 255, 0.1);
		font-size: var(--caption);
		font-weight: 500;
	}
	.marker {
		filter: drop-shadow(0 0.5px 1px rgba(0, 0, 0, 0.25));
	}
</style>
