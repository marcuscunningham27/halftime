<script lang="ts">
	// GamecastView: the last play in a banner over the surface, then the three latest plays.
	// shortcut: no timeouts / fouls / bonus row (ESPN's core API situation); add it with the NBA live check.
	import type { Snippet } from 'svelte';
	import { type Game, type Play, isMarker, isSkipped, playTeam, bannerTitle, periodTitle, hex } from './espn';
	let { game, plays, children }: { game: Game; plays: Play[]; children: Snippet } = $props();

	const latest = $derived(plays.findLast((p) => p.text && !isSkipped(p)));
	const recent = $derived(plays.filter((p) => p.teamID && p.text && !isSkipped(p) && !isMarker(p)).slice(-3).reverse());
	// Period ends belong to neither team (football files them under the last drive's).
	const bannerTeam = $derived(latest && !isMarker(latest) && game.status !== 'final' ? playTeam(latest, game) : undefined);
</script>

<div class="gamecast">
	{#if latest}
		{#key latest.id}
			<div class="banner" style:--team={bannerTeam ? hex(bannerTeam.color) : 'gray'} role="status" aria-label="Last play: {latest.text}">
				<div class="banner-title">
					{#if bannerTeam}<img src={bannerTeam.logo} alt="" width="30" height="30" />{/if}
					<span>{bannerTitle(latest, game).toUpperCase()}</span>
				</div>
				{#if !isMarker(latest)}<p>{latest.text}</p>{/if}
			</div>
		{/key}
	{/if}
	{@render children()}
	{#if recent.length}
		<ul class="recent">
			{#each recent as play (play.id)}
				{@const team = playTeam(play, game)}
				{@const scorer = play.isScoring ? play.teamID : undefined}
				<li>
					<span class="logo">{#if team}<img src={team.logo} alt="" width="20" height="20" />{/if}</span>
					<div class="text">
						<strong>{play.headline ?? play.type ?? ''}</strong>
						<span class="caption">{[play.clock, periodTitle(game.league, play.period), play.spot ?? ''].filter(Boolean).join(' - ')}</span>
						<span class="caption">{play.text}</span>
					</div>
					{#if play.awayScore !== undefined && play.homeScore !== undefined}
						<span class="play-score">
							<span class:scored={scorer === game.away.team.id}>{play.awayScore}</span>
							<span class:scored={scorer === game.home.team.id}>{play.homeScore}</span>
						</span>
					{/if}
				</li>
			{/each}
		</ul>
	{/if}
</div>

<style>
	.gamecast {
		display: flex;
		flex-direction: column;
		gap: 12px;
		max-width: 600px;
		width: 100%;
		margin: 0 auto;
	}
	.banner {
		text-align: center;
		padding: 10px;
		border-radius: 14px;
		background: color-mix(in srgb, var(--team) 25%, transparent);
		animation: drop 0.35s cubic-bezier(0.3, 1.2, 0.5, 1);
	}
	@keyframes drop {
		from { transform: translateY(-12px); opacity: 0; }
	}
	.banner-title {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 10px;
		font: 700 34px/1.1 'Chakra Petch', sans-serif;
	}
	.banner p {
		margin: 4px 0 0;
		font-size: var(--subheadline);
		color: var(--secondary);
	}
	.recent {
		list-style: none;
		margin: 0;
		padding: 0 14px;
		border-radius: 14px;
		background: rgba(255, 255, 255, 0.06);
	}
	.recent li {
		display: flex;
		align-items: flex-start;
		gap: 10px;
		padding: 9px 0;
	}
	.recent li + li {
		border-top: 1px solid var(--separator);
	}
	.logo {
		width: 20px;
		flex: none;
	}
	.text {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 2px;
	}
	.text strong {
		font-size: var(--subheadline);
	}
	.caption {
		font-size: var(--caption);
		color: var(--secondary);
	}
	.play-score {
		display: flex;
		gap: 8px;
		font-size: var(--subheadline);
		color: var(--secondary);
	}
	.play-score .scored {
		color: var(--label);
		font-weight: 700;
	}
	@media (prefers-reduced-motion: reduce) {
		.banner { animation: none; }
	}
</style>
