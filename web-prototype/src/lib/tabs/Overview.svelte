<script lang="ts">
	// GameOverviewView: venue, game info, odds, standings and the pre-game win probability.
	// shortcut: no weather card or venue local time (the Swift app geocodes with MapKit); Open-Meteo's geocoder could replace it.
	import { type Game, type Overview, ordinal, hex } from '../espn';
	let { game, overview }: { game: Game; overview: Overview } = $props();

	const signed = (n: number) => (n > 0 ? `+${n}` : `−${Math.abs(n)}`);
	const oneDecimal = (n: number) => String(Math.round(n * 10) / 10);
	const standings = $derived(
		[game.away.team, game.home.team].flatMap((team) => {
			const s = overview.standings.find((x) => x.teamID === team.id);
			return s ? [{ team, s }] : [];
		})
	);
	const away = $derived(overview.winProbability[game.away.team.id] ?? 0);
	const home = $derived(overview.winProbability[game.home.team.id] ?? 0);
</script>

{#snippet info(title: string, value: string)}
	<div class="info"><span class="dim">{title}</span><span class="value">{value}</span></div>
{/snippet}

<div class="stack">
	{#if overview.venue}
		<div class="venue">
			{#if overview.venue.image}<img src={overview.venue.image} alt="" />{/if}
			<div class="caption">
				<strong>{overview.venue.name}</strong>
				{#if overview.venue.place}<span class="dim">{overview.venue.place}</span>{/if}
			</div>
		</div>
	{/if}

	<section class="sports-card">
		<h2>Game Info</h2>
		{@render info('Your time', game.startDate.toLocaleString([], { weekday: 'short', day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' }))}
		{#if overview.venue}{@render info('Venue', [overview.venue.name, overview.venue.place].filter(Boolean).join(', '))}{/if}
		{#if overview.broadcasts.length}{@render info('Watch', overview.broadcasts.join(', '))}{/if}
		{#if game.note}{@render info('Event', game.note)}{/if}
		{#if overview.attendance}{@render info('Attendance', overview.attendance.toLocaleString())}{/if}
	</section>

	{#if overview.odds}
		{@const o = overview.odds}
		<section class="sports-card">
			<h2>Odds</h2>
			{#if o.homeSpread !== undefined}
				<!-- A positive home line means the away team is favoured by that much. -->
				{@render info('Spread', o.homeSpread === 0 ? "Pick'em" : `${(o.homeSpread > 0 ? game.away : game.home).team.abbreviation} −${oneDecimal(Math.abs(o.homeSpread))}`)}
			{/if}
			{#if o.overUnder !== undefined}{@render info('Over/Under', oneDecimal(o.overUnder))}{/if}
			{#if o.awayMoneyLine !== undefined && o.homeMoneyLine !== undefined}
				{@render info('Moneyline', `${game.away.team.abbreviation} ${signed(o.awayMoneyLine)} · ${game.home.team.abbreviation} ${signed(o.homeMoneyLine)}`)}
			{/if}
			<p class="footnote">Average of {o.books.length} sportsbook{o.books.length === 1 ? '' : 's'}: {o.books.join(', ')}.</p>
		</section>
	{/if}

	{#if standings.length}
		<section class="sports-card">
			<h2>Standings</h2>
			{#each standings as { team, s }}
				<div class="standing">
					<img src={team.logo} alt="" width="24" height="24" />
					<strong>{team.shortName}</strong>
					<span class="grow">{ordinal(s.position)} in {s.group}</span>
					{#if s.record}<span class="dim">{s.record}</span>{/if}
				</div>
			{/each}
		</section>
	{/if}

	{#if game.status !== 'final' && away + home > 0}
		<section class="sports-card">
			<h2>Win Probability</h2>
			<div class="split"><strong>{game.away.team.abbreviation} {away.toFixed(1)}%</strong><strong>{home.toFixed(1)}% {game.home.team.abbreviation}</strong></div>
			<div class="bar">
				<span style:width="calc((100% - 4px) * {away / (away + home)})" style:background={hex(game.away.team.color)}></span>
				<span style:flex="1" style:background={hex(game.home.team.color)}></span>
			</div>
			<p class="footnote">ESPN Matchup Predictor, before the game.</p>
		</section>
	{/if}
</div>

<style>
	.stack {
		display: flex;
		flex-direction: column;
		gap: 12px;
	}
	.venue {
		position: relative;
		height: 180px;
		border-radius: 22px;
		overflow: hidden;
		background: rgba(255, 255, 255, 0.08);
	}
	.venue img {
		width: 100%;
		height: 100%;
		object-fit: cover;
	}
	.venue::after {
		content: '';
		position: absolute;
		inset: 0;
		background: linear-gradient(transparent 50%, rgba(0, 0, 0, 0.75));
	}
	.venue .caption {
		position: absolute;
		z-index: 1;
		left: 14px;
		bottom: 14px;
		display: flex;
		flex-direction: column;
		gap: 2px;
	}
	.venue strong {
		font-size: var(--title3);
	}
	.info {
		display: flex;
		justify-content: space-between;
		gap: 12px;
		padding: 5px 0;
	}
	.value {
		text-align: right;
	}
	.dim {
		color: var(--secondary);
	}
	.footnote {
		margin: 4px 0 0;
		font-size: var(--caption);
		color: var(--tertiary);
	}
	.standing {
		display: flex;
		align-items: center;
		gap: 10px;
		padding: 5px 0;
	}
	.grow {
		flex: 1;
		text-align: right;
	}
	.split {
		display: flex;
		justify-content: space-between;
	}
	.bar {
		display: flex;
		gap: 4px;
		height: 8px;
		margin: 6px 0;
	}
	.bar span {
		border-radius: 4px;
	}
</style>
