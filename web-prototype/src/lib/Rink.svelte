<script lang="ts">
	// HockeyRinkView: a tilted 200 × 85 ft rink with every shot and goal where it was taken (teams change ends each
	// period, as ESPN places them): goals filled with a ring, shots on goal filled, missed and blocked hollow.
	import { type Game, type Play, type Team, hex } from './espn';
	let { game, shots }: { game: Game; shots: Play[] } = $props();

	const teams = $derived([game.away.team, game.home.team]);
	const teamOf = (p: Play) => teams.find((t) => t.id === p.teamID);
	const type = (p: Play) => (p.type ?? '').toLowerCase();
	const isGoal = (p: Play) => type(p).includes('goal') && p.isScoring;
	const missed = (p: Play) => type(p).includes('miss') || type(p).includes('block');
	const goals = (t: Team) => shots.filter((p) => p.teamID === t.id && isGoal(p)).length;
	const onGoal = (t: Team) => shots.filter((p) => p.teamID === t.id && (isGoal(p) || (type(p).includes('shot') && !missed(p)))).length;
	// Goals last, so they sit on top of nearby shots.
	const ordered = $derived([...shots].sort((a, b) => Number(isGoal(a)) - Number(isGoal(b))));
	const last = $derived(shots.at(-1));
	const lastTeam = $derived(last && teamOf(last));
	const label = $derived('Shot map. ' + teams.map((t) => `${t.shortName} ${goals(t)} goals on ${onGoal(t)} shots`).join(', '));
	const red = '#d92626', blue = '#264dcc';
</script>

<div class="rink-wrap" role="img" aria-label={label}>
	<div class="legend">
		{#each teams as t}
			<span><i style:background={hex(t.color)}></i><img src={t.logo} alt="" width="18" height="18" />{t.abbreviation} {goals(t)} G · {onGoal(t)} SOG</span>
		{/each}
	</div>
	<svg class="rink" viewBox="0 0 200 85" aria-hidden="true">
		<rect width="200" height="85" rx="28" fill="#edf5fc" stroke="gray" stroke-width="0.8" />
		{#each [[100, red, 1], [75, blue, 1.2], [125, blue, 1.2], [11, red, 0.4], [189, red, 0.4]] as [x, color, width]}
			<path d="M{x},1V84" stroke={String(color)} stroke-width={Number(width)} />
		{/each}
		<circle cx="100" cy="42.5" r="15" fill="none" stroke={blue} stroke-width="0.4" />
		{#each [31, 169] as x}
			{#each [20.5, 64.5] as y}
				<circle cx={x} cy={y} r="15" fill="none" stroke={red} stroke-width="0.4" />
				<circle cx={x} cy={y} r="1" fill={red} />
			{/each}
		{/each}
		<!-- Goal creases. -->
		<path d="M11,36.5 A6,6 0 0 1 11,48.5 Z" fill={blue} fill-opacity="0.35" />
		<path d="M189,36.5 A6,6 0 0 0 189,48.5 Z" fill={blue} fill-opacity="0.35" />
		<image href={game.home.team.logo} x={100 - 12.75} y={42.5 - 12.75} width="25.5" height="25.5" opacity="0.8" />
		{#each ordered as shot (shot.id)}
			{@const t = teamOf(shot)}
			{#if t && shot.location}
				{@const x = shot.location.x * 200}
				{@const y = shot.location.y * 85}
				{#if isGoal(shot)}
					<circle cx={x} cy={y} r="3" fill={hex(t.color)} />
					<circle cx={x} cy={y} r="4.5" fill="none" stroke={hex(t.color)} stroke-width="0.8" />
				{:else if missed(shot)}
					<circle cx={x} cy={y} r="1.8" fill="none" stroke={hex(t.color)} stroke-opacity="0.7" stroke-width="0.6" />
				{:else}
					<circle cx={x} cy={y} r="1.8" fill={hex(t.color)} fill-opacity="0.9" />
				{/if}
			{/if}
		{/each}
		{#if last?.location && lastTeam}
			{#key last.id}
				<!-- On the light ice the pulse is the team colour for goals and misses alike, so it shows. -->
				<circle class="pulse" cx={last.location.x * 200} cy={last.location.y * 85} r="2.6" fill="none" stroke={hex(lastTeam.color)} stroke-width="1.7" />
			{/key}
		{/if}
	</svg>
</div>

<style>
	.rink-wrap {
		display: flex;
		flex-direction: column;
		gap: 8px;
	}
	.legend {
		display: flex;
		justify-content: space-between;
		font-size: var(--caption);
		color: var(--secondary);
	}
	.legend span {
		display: flex;
		align-items: center;
		gap: 6px;
	}
	.legend i {
		width: 9px;
		height: 9px;
		border-radius: 50%;
	}
	/* SwiftUI's rotation3DEffect(20°, x axis, perspective 0.5). */
	.rink {
		display: block;
		width: 100%;
		transform: perspective(700px) rotateX(20deg);
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
	@media (prefers-reduced-motion: reduce) {
		.pulse { animation: none; }
	}
</style>
