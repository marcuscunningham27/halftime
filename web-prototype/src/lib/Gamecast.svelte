<script lang="ts">
	// GamecastView: the last play in a banner over the surface, then the three latest plays.
	// Under the surface while live: hockey's power play and empty net, then each side's timeouts and fouls.
	import type { Snippet } from 'svelte';
	import FantasyBadge from './FantasyBadge.svelte';
	import { playersIn } from './roster.svelte';
	import { type Game, type Play, type Court, type Team, type CourtSide, isMarker, isSkipped, playTeam, bannerTitle, periodTitle, powerPlayTeam, hex } from './espn';
	let { game, plays, court, children }: { game: Game; plays: Play[]; court?: Court; children: Snippet } = $props();

	/** NFL teams get three timeouts a half, NBA teams seven a game, WNBA teams five. */
	const timeoutsPerGame = $derived(game.league.sport === 'football' ? 3 : game.league.id === 'wnba' ? 5 : 7);
	const ppTeam = $derived(court?.powerPlay ? [game.away.team, game.home.team].find((t) => t.id === powerPlayTeam(plays, game.away.team.id, game.home.team.id)) : undefined);
	const showsSides = $derived(!!court && [court.away, court.home].some((s) => s.timeoutsLeft !== undefined || s.fouls !== undefined));

	const latest = $derived(plays.findLast((p) => p.text && !isSkipped(p)));
	// Baseball lists at-bat results rather than every pitch.
	const recent = $derived(
		plays.filter((p) => (game.league.sport === 'baseball' ? p.type === 'Play Result' : p.teamID && p.text && !isSkipped(p) && !isMarker(p))).slice(-3).reverse()
	);
	// Period ends belong to neither team (football files them under the last drive's).
	const bannerTeam = $derived(latest && !isMarker(latest) && game.status !== 'final' ? playTeam(latest, game) : undefined);
</script>

{#snippet sideStatus(team: Team, side: CourtSide, trailing: boolean)}
	<!-- Timeouts left as pips, team fouls this period and a bonus tag. -->
	<div class="side" class:trailing role="group" aria-label="{team.shortName}: {side.timeoutsLeft !== undefined ? `${side.timeoutsLeft} timeouts left` : ''}{side.fouls !== undefined ? `, ${side.fouls} team fouls` : ''}{side.inBonus ? ', in the bonus' : ''}">
		{#if side.timeoutsLeft !== undefined}
			<span class="tol">TOL {#each { length: timeoutsPerGame } as _, i}<i style:background={i < side.timeoutsLeft ? `color-mix(in srgb, ${hex(team.color)}, white 25%)` : 'rgba(255,255,255,0.15)'}></i>{/each}</span>
		{/if}
		<span class="fouls">
			{#if side.fouls !== undefined}Fouls {side.fouls}{/if}
			{#if side.inBonus}<b class="bonus">BONUS</b>{/if}
		</span>
	</div>
{/snippet}

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
	{#if court && (court.powerPlay || court.emptyNet)}
		<div class="pills">
			{#if court.powerPlay}<span class="pill" style:--c={ppTeam ? hex(ppTeam.color) : '#ff9f0a'}>{['Power Play', ppTeam?.abbreviation].filter(Boolean).join(' · ')}</span>{/if}
			{#if court.emptyNet}<span class="pill" style:--c="#ff453a">Empty Net</span>{/if}
		</div>
	{/if}
	{#if court && showsSides}
		<div class="sides">
			{@render sideStatus(game.away.team, court.away, false)}
			{@render sideStatus(game.home.team, court.home, true)}
		</div>
	{/if}
	{#if recent.length}
		<ul class="recent">
			{#each recent as play (play.id)}
				{@const team = playTeam(play, game)}
				{@const scorer = play.isScoring ? play.teamID : undefined}
				<!-- Fantasy is NFL only, so other sports never match. -->
				{@const yours = game.league.id === 'nfl' ? playersIn(play.text) : []}
				<li class:yours={yours.length > 0}>
					<span class="logo">{#if team}<img src={team.logo} alt="" width="20" height="20" />{/if}</span>
					<div class="text">
						<span class="headline">
							<strong>{play.headline ?? play.type ?? ''}</strong>
							{#each yours as p (p.id)}<FantasyBadge /><span class="mine">{p.name}</span>{/each}
						</span>
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
	.pills {
		display: flex;
		justify-content: center;
		gap: 8px;
	}
	.pill {
		padding: 4px 10px;
		border-radius: 999px;
		background: var(--c);
		font-size: var(--caption);
		font-weight: 800;
		text-transform: uppercase;
	}
	.sides {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
	}
	.side {
		display: flex;
		flex-direction: column;
		gap: 4px;
	}
	.side.trailing {
		align-items: flex-end;
	}
	.tol {
		display: flex;
		align-items: center;
		gap: 4px;
		font-size: var(--caption);
		font-weight: 600;
		color: var(--secondary);
	}
	.tol i {
		width: 10px;
		height: 4px;
		border-radius: 2px;
	}
	.fouls {
		display: flex;
		align-items: center;
		gap: 6px;
		font-size: var(--caption);
		color: var(--secondary);
	}
	.bonus {
		padding: 1px 5px;
		border-radius: 999px;
		background: rgba(255, 159, 10, 0.8);
		color: var(--label);
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
	.recent li.yours {
		margin: 0 -6px;
		padding-inline: 6px;
		border-radius: 8px;
		background: rgba(255, 214, 10, 0.14);
	}
	.headline {
		display: flex;
		align-items: center;
		gap: 5px;
	}
	.mine {
		font-size: var(--caption);
		font-weight: 600;
		color: #ffd60a;
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
