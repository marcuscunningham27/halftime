<script lang="ts">
	// GameLeadersView: headshot and big number each side, category in the middle, name, position and line below.
	import type { Game, Leader } from '../espn';
	let { game, leaders }: { game: Game; leaders: Leader[] } = $props();
	const categories = $derived([...new Set(leaders.map((l) => l.category))]);
	const pick = (category: string, teamID: string) => leaders.find((l) => l.category === category && l.teamID === teamID);
</script>

{#snippet face(l: Leader | undefined)}
	<span class="face" class:hidden={!l}>{#if l?.headshot}<img src={l.headshot} alt="" />{/if}</span>
{/snippet}

{#snippet caption(l: Leader | undefined, trailing: boolean)}
	<div class="caption" class:trailing>
		{#if l}
			<span><strong>{l.shortName ?? l.athlete}</strong> {#if l.position}<span class="dim">{l.position}</span>{/if}</span>
			{#if l.summary}<small>{l.summary}</small>{/if}
		{/if}
	</div>
{/snippet}

{#if categories.length}
	<section class="sports-card">
		<h2>{game.status === 'scheduled' ? 'Season Leaders' : 'Game Leaders'}</h2>
		<div class="teams">
			<span><img src={game.away.team.logo} alt="" width="26" height="26" /><strong>{game.away.team.abbreviation}</strong></span>
			<span><strong>{game.home.team.abbreviation}</strong><img src={game.home.team.logo} alt="" width="26" height="26" /></span>
		</div>
		{#each categories as category}
			{@const away = pick(category, game.away.team.id)}
			{@const home = pick(category, game.home.team.id)}
			<hr />
			<div class="row" role="group" aria-label="{category}: {[away, home].filter(Boolean).map((l) => `${l!.athlete} ${l!.summary ?? ''}`).join('; ')}">
				<div class="line">
					{@render face(away)}
					<span class="big">{away?.mainValue ?? ''}</span>
					<span class="category">{category}</span>
					<span class="big">{home?.mainValue ?? ''}</span>
					{@render face(home)}
				</div>
				<div class="captions">{@render caption(away, false)}{@render caption(home, true)}</div>
			</div>
		{/each}
	</section>
{/if}

<style>
	.teams {
		display: flex;
		justify-content: space-between;
		padding: 8px 0;
	}
	.teams span {
		display: flex;
		align-items: center;
		gap: 6px;
	}
	.row {
		padding: 10px 0;
		display: flex;
		flex-direction: column;
		gap: 6px;
	}
	.line {
		display: flex;
		align-items: center;
		gap: 12px;
	}
	.face {
		width: 52px;
		height: 52px;
		border-radius: 50%;
		overflow: hidden;
		flex: none;
		background: rgba(255, 255, 255, 0.12);
		box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.25);
	}
	.face.hidden {
		visibility: hidden;
	}
	.face img {
		width: 100%;
		height: 100%;
		object-fit: cover;
	}
	.big {
		font: 700 30px/1 'Chakra Petch', sans-serif;
	}
	/* ESPN-style bold condensed label. */
	.category {
		flex: 1;
		text-align: center;
		font-size: var(--subheadline);
		font-weight: 700;
		font-stretch: condensed;
		text-transform: uppercase;
	}
	.captions {
		display: flex;
		justify-content: space-between;
		gap: 12px;
	}
	.caption {
		display: flex;
		flex-direction: column;
		gap: 1px;
		font-size: var(--subheadline);
	}
	.caption.trailing {
		align-items: flex-end;
		text-align: right;
	}
	.dim, small {
		color: var(--secondary);
	}
	small {
		font-size: var(--caption);
	}
</style>
