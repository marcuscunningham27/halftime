<script lang="ts">
	// PlayByPlayView: drives for football (All Drives / Scoring Drives), plays by period for other sports; newest first.
	import GlassPicker from '../GlassPicker.svelte';
	import Probability from './Probability.svelte';
	import FantasyBadge from '../FantasyBadge.svelte';
	import { playersIn } from '../roster.svelte';
	import { type Game, type Drive, type Play, type Overview, hex, periodTitle } from '../espn';
	let { game, drives, plays, overview }: { game: Game; drives: Drive[]; plays: Play[]; overview: Overview } = $props();

	const byDrive = $derived(drives.length > 0);
	const options = $derived(byDrive ? ['All Drives', 'Scoring Drives'] : ['All Plays', 'Scoring Plays']);
	let filter = $state<string>('All');
	const scoringOnly = $derived(filter.startsWith('Scoring'));
	const shown = $derived(drives.filter((d) => !scoringOnly || d.isScore).reverse());
	const periodPlays = $derived(plays.filter((p) => !scoringOnly || p.isScoring));
	const periods = $derived([...new Set(periodPlays.map((p) => p.period))].sort((a, b) => b - a));
	$effect(() => {
		if (!options.includes(filter)) filter = options[0];
	});
	const latestID = $derived(drives.at(-1)?.id);
	const team = (id?: string) => [game.away.team, game.home.team].find((t) => t.id === id);
	const titleCase = (s: string) => s.replace(/\b\w/g, (c) => c.toUpperCase());

	/** "12:04 · 1st & 10 at" then the spot, which is drawn in the team's colour. */
	function footer(p: Play): [string, string?] {
		const at = p.spot?.indexOf(' at ') ?? -1;
		if (p.spot && at >= 0) return [`${p.clock ? p.clock + ' · ' : ''}${p.spot.slice(0, at)} at `, p.spot.slice(at + 4)];
		return [[p.clock, p.spot].filter(Boolean).join(' · ')];
	}
</script>

{#if plays.length === 0}
	<div class="empty-state">No Plays Yet</div>
{:else}
	<div class="stack">
		<Probability {game} {plays} {overview} />
		<div class="picker"><GlassPicker {options} bind:selected={filter} /></div>
		{#if !byDrive}
			{#each periods as period (period)}
				<section class="sports-card">
					<h2>{periodTitle(game.league, period)}</h2>
					{#each periodPlays.filter((p) => p.period === period).reverse() as play (play.id)}
						{@const t = team(play.teamID)}
						{@const [lead, spot] = footer(play)}
						<hr />
						<div class="play row" style:--team={hex(t?.color)}>
							<span class="logo">{#if t}<img src={t.logo} alt={t.shortName} width="20" height="20" />{/if}</span>
							<div class="body">
								{#if play.type}<strong>{play.type}</strong>{/if}
								<p class:scoring={play.isScoring} class:plain={!play.type}>{play.text}</p>
								<span class="footer">{lead}{#if spot}<span class="spot">{spot}</span>{/if}</span>
							</div>
							{#if play.isScoring && play.awayScore !== undefined && play.homeScore !== undefined}
								<strong class="score">{game.away.team.abbreviation} {play.awayScore} – {play.homeScore} {game.home.team.abbreviation}</strong>
							{/if}
						</div>
					{/each}
				</section>
			{/each}
		{/if}
		{#each shown as drive (drive.id)}
			{@const t = team(drive.teamID)}
			<section class="sports-card" class:current={game.status === 'live' && drive.id === latestID} style:--team={hex(t?.color)}>
				<div class="head">
					{#if t}<img src={t.logo} alt={t.shortName} width="20" height="20" />{/if}
					<span class="summary">{titleCase(drive.summary)}</span>
					{#if drive.result}<span class="result" class:score={drive.isScore}>{drive.result}</span>{/if}
				</div>
				{#each [...drive.plays].reverse() as play (play.id)}
					{@const [lead, spot] = footer(play)}
					<hr />
					{@const yours = game.league.id === 'nfl' ? playersIn(play.text) : []}
					<div class="play" class:yours={yours.length > 0}>
						{#if play.type || yours.length}
							<span class="headline">
								{#if play.type}<strong>{play.type}</strong>{/if}
								{#each yours as p (p.id)}<FantasyBadge /><span class="mine">{p.name}</span>{/each}
							</span>
						{/if}
						<p class:scoring={play.isScoring} class:plain={!play.type}>{play.text}</p>
						<span class="footer">{lead}{#if spot}<span class="spot">{spot}</span>{/if}</span>
					</div>
				{/each}
			</section>
		{/each}
	</div>
{/if}

<style>
	.stack {
		display: flex;
		flex-direction: column;
		gap: 12px;
	}
	.picker {
		display: flex;
		justify-content: center;
	}
	.sports-card {
		position: relative;
	}
	/* The drive in progress gets the offence's colour down its edge, as on iOS. */
	.current::before {
		content: '';
		position: absolute;
		left: 0;
		top: 14px;
		bottom: 14px;
		width: 3px;
		border-radius: 2px;
		background: var(--team);
	}
	.head {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 6px 0;
		font-size: var(--subheadline);
	}
	.summary {
		flex: 1;
		color: var(--secondary);
	}
	.result {
		font-weight: 600;
		color: var(--secondary);
	}
	.result.score {
		color: var(--label);
	}
	.play {
		display: flex;
		flex-direction: column;
		gap: 3px;
		padding: 8px 0;
	}
	.play p {
		margin: 0;
		color: var(--secondary);
		user-select: text;
		-webkit-user-select: text;
	}
	.play p.plain {
		color: var(--label);
	}
	.play p.scoring {
		font-weight: 600;
	}
	.row {
		flex-direction: row;
		align-items: flex-start;
		gap: 10px;
	}
	.logo {
		width: 20px;
		flex: none;
		padding-top: 2px;
	}
	.body {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 3px;
	}
	.score {
		font-size: var(--subheadline);
		white-space: nowrap;
	}
	.play.yours {
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
	.footer {
		font-size: var(--subheadline);
		color: var(--secondary);
	}
	.spot {
		color: color-mix(in srgb, var(--team), white 30%);
	}
</style>
