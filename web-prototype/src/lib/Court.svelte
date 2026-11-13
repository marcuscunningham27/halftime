<script lang="ts">
	// BasketballCourtView: a tilted 94 × 50 ft court with every located shot, the last basket's flight, a pulse on the
	// latest shot and the team with the ball's half shaded. Away shoots at the left basket, home at the right.
	import { type Game, type Play, type Team, hex, backdropHex } from './espn';
	let { game, shots, possession }: { game: Game; shots: Play[]; possession?: string } = $props();

	const teams = $derived([game.away.team, game.home.team]);
	const teamOf = (p: Play) => teams.find((t) => t.id === p.teamID);
	/** Distance out from the team's basket line becomes left-to-right position. */
	function spot(p: Play): { x: number; y: number; team: Team } | undefined {
		const team = teamOf(p);
		if (!p.location || !team) return;
		const away = team.id === game.away.team.id;
		return { x: away ? p.location.y * 47 : 94 - p.location.y * 47, y: p.location.x * 50, team };
	}
	const made = (t: Team) => shots.filter((s) => s.teamID === t.id && s.isScoring).length;
	const attempts = (t: Team) => shots.filter((s) => s.teamID === t.id).length;

	const lastShot = $derived(shots.at(-1) && spot(shots.at(-1)!));
	const lastBasket = $derived.by(() => {
		const s = shots.findLast((p) => p.isScoring);
		const at = s && spot(s);
		if (!at) return;
		const hoop = { x: at.team.id === game.away.team.id ? 5.25 : 88.75, y: 25 };
		// Bow the line up the screen in proportion to its length, so it reads as the ball's flight.
		const lift = Math.max(2, Math.hypot(hoop.x - at.x, hoop.y - at.y) * 0.35);
		return { ...at, d: `M${at.x},${at.y} Q${(at.x + hoop.x) / 2},${Math.min(at.y, hoop.y) - lift} ${hoop.x},${hoop.y}` };
	});
	const offense = $derived(teams.find((t) => t.id === possession));
	const dir = $derived(offense?.id === game.away.team.id ? -1 : 1);
	const pad = $derived(hex(backdropHex(game.home.team)));
	const mix = (c: string | undefined, pct: number) => `color-mix(in srgb, ${hex(c)}, white ${pct}%)`;
	const label = $derived('Shot chart. ' + teams.map((t) => `${t.shortName} ${made(t)} of ${attempts(t)}`).join(', '));
</script>

<div class="court-wrap" role="img" aria-label={label}>
	<div class="legend">
		{#each teams as t}
			<span><i style:background={hex(t.color)}></i><img src={t.logo} alt="" width="18" height="18" />{t.abbreviation} {made(t)}/{attempts(t)} FG</span>
		{/each}
	</div>
	<div class="stage">
		<svg class="court" viewBox="0 0 94 50" aria-hidden="true">
			<defs>
				<linearGradient id="floor" x1="0" y1="0" x2="1" y2="1">
					<stop offset="0" stop-color="#cc9961" />
					<stop offset="1" stop-color="#b88552" />
				</linearGradient>
				{#if offense}
					<linearGradient id="attack" x1={dir < 0 ? 0 : 1} x2={dir < 0 ? 1 : 0} y1="0" y2="0">
						<stop offset="0" stop-color={hex(offense.color)} stop-opacity="0.55" />
						<stop offset="1" stop-color={hex(offense.color)} stop-opacity="0.05" />
					</linearGradient>
				{/if}
			</defs>
			<rect width="94" height="50" rx="1" fill="url(#floor)" stroke="rgba(255,255,255,0.9)" stroke-width="0.35" />
			<g fill="none" stroke="rgba(255,255,255,0.9)" stroke-width="0.3">
				<path d="M47,0V50" />
				<circle cx="47" cy="25" r="6" />
				{#each [true, false] as left}
					{@const base = left ? 0 : 94}
					{@const d = left ? 1 : -1}
					<!-- Painted key, free-throw circle, three-point line, rim. -->
					<rect x={left ? 0 : 75} y="17" width="19" height="16" fill={hex((left ? game.away : game.home).team.color)} fill-opacity="0.45" />
					<circle cx={base + d * 19} cy="25" r="6" />
					<path d="M{base},3 H{base + d * 14} A23.75,23.75 0 0 {left ? 1 : 0} {base + d * 14},47 H{base}" />
					<circle cx={base + d * 5.25} cy="25" r="0.75" stroke="orange" stroke-width="0.35" />
				{/each}
			</g>
			{#if offense}
				<rect x={dir < 0 ? 0 : 47} width="47" height="50" fill="url(#attack)" />
				{#each [0, 1, 2] as i}
					<path class="chevron" style:animation-delay="{(-i * 1.6) / 3}s" style:--dx="{dir * 22}px" d="M{47 + dir * 6 - dir * 3},18 l{dir * 6},7 l{-dir * 6},7" />
				{/each}
			{/if}
			<image href={game.home.team.logo} x={47 - 8.5} y={25 - 8.5} width="17" height="17" opacity="0.85" />
			{#each shots as shot (shot.id)}
				{@const at = spot(shot)}
				{#if at}
					{#if shot.isScoring}
						<circle cx={at.x} cy={at.y} r="0.8" fill={hex(at.team.color)} stroke="rgba(255,255,255,0.8)" stroke-width="0.15" />
					{:else}
						<circle cx={at.x} cy={at.y} r="0.8" fill="none" stroke={mix(at.team.color, 30)} stroke-width="0.3" />
					{/if}
				{/if}
			{/each}
			{#if lastBasket}
				<path d={lastBasket.d} fill="none" stroke="rgba(255,255,255,0.9)" stroke-width="0.9" stroke-linecap="round" />
				<path d={lastBasket.d} fill="none" stroke={mix(lastBasket.team.color, 20)} stroke-width="0.5" stroke-linecap="round" />
				<circle cx={lastBasket.x} cy={lastBasket.y} r="1.4" fill="none" stroke="white" stroke-width="0.3" />
			{/if}
			{#if lastShot}
				{#key shots.at(-1)?.id}
					<circle class="pulse" cx={lastShot.x} cy={lastShot.y} r="1.2" fill="none" stroke-width="0.5" stroke={shots.at(-1)?.isScoring ? mix(lastShot.team.color, 30) : 'white'} />
				{/key}
			{/if}
		</svg>
		<!-- Hoops stand up out of the floor, so they sit outside the tilt, over each basket. -->
		{#each ['left', 'right'] as side}
			<svg class="hoop {side}" viewBox="0 0 50 100" width="34" height="68" aria-hidden="true">
				<ellipse cx="12" cy="97.5" rx="12" ry="2.5" fill="rgba(0,0,0,0.25)" />
				<polygon points="2,50 14,46 14,98 2,98" fill={pad} />
				<polygon points="14,46 19,48 19,96 14,98" fill="color-mix(in srgb, {pad}, black 35%)" />
				<polygon points="2,50 14,46 19,48 7,52" fill="color-mix(in srgb, {pad}, white 30%)" />
				<path d="M2,72 L14,70" stroke="rgba(0,0,0,0.18)" stroke-width="0.8" />
				<polygon points="9,47 31,39 31,42 9,50" fill="#e0e0e0" />
				<polygon points="9,50 31,42 31,43.5 9,51.5" fill="#9e9e9e" />
				<path d="M17,60 L30,44" stroke="#b3b3b3" stroke-width="1.5" />
				<polygon points="29,8 31,7 31,47 29,48" fill="#b8b8b8" />
				<polygon points="31,7 35,5 35,45 31,47" fill="white" />
				<polygon points="35,40 38,40 38,43 35,44" fill="#999" />
				<path d="M37.5,42 L40,55.5 M40.25,42 L41.5,55.5 M43,42 L43,55.5 M45.75,42 L44.5,55.5 M48.5,42 L46,55.5 M37.5,42 L41.5,55.5 M40.25,42 L40,55.5 M40.25,42 L43,55.5 M43,42 L41.5,55.5 M43,42 L44.5,55.5 M45.75,42 L43,55.5 M45.75,42 L46,55.5 M48.5,42 L44.5,55.5 M40,55.5 L46,55.5" stroke="#d9d9d9" stroke-width="0.6" fill="none" />
				<ellipse cx="43" cy="42" rx="7" ry="2.5" fill="none" stroke="#f25426" stroke-width="1.6" />
			</svg>
		{/each}
	</div>
</div>

<style>
	.court-wrap {
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
	.stage {
		position: relative;
	}
	/* SwiftUI's rotation3DEffect(20°, x axis, perspective 0.5). */
	.court {
		display: block;
		width: 100%;
		transform: perspective(700px) rotateX(20deg);
	}
	.chevron {
		fill: none;
		stroke: white;
		stroke-width: 2.2;
		stroke-linecap: round;
		stroke-linejoin: round;
		animation: drift 1.6s linear infinite;
	}
	@keyframes drift {
		0% { transform: translateX(0); opacity: 0; }
		50% { opacity: 0.55; }
		100% { transform: translateX(var(--dx)); opacity: 0; }
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
	.hoop {
		position: absolute;
		top: calc(50% - 34px - 34px);
	}
	.hoop.left {
		left: -10px;
	}
	.hoop.right {
		right: -10px;
		transform: scaleX(-1);
	}
	@media (prefers-reduced-motion: reduce) {
		.chevron, .pulse { animation: none; }
	}
</style>
