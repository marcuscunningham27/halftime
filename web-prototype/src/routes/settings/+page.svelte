<script lang="ts">
	// SettingsView.swift's Following and Fantasy tabs. General (launch at login, Close to Menu), Notifications and
	// Summaries arrive with the menu bar, alerts and AI features they configure.
	import { goto } from '$app/navigation';
	import Backdrop from '$lib/Backdrop.svelte';
	import GlassPicker from '$lib/GlassPicker.svelte';
	import FollowButton from '$lib/FollowButton.svelte';
	import LeagueSetup from '$lib/LeagueSetup.svelte';
	import { leagues, leagueLogo } from '$lib/espn';
	import { follows } from '$lib/follows.svelte';
	import { store } from '$lib/fantasy';

	const tabs = ['Following', 'Fantasy'] as const;
	let tab = $state<(typeof tabs)[number]>('Following');
	let fantasyLeagues = $state(store.leagues());
	const leagueOf = (id: string) => leagues.find((l) => l.id === id);
</script>

<svelte:head><title>Settings · Halftime</title></svelte:head>
<Backdrop color="#1c1c1e" />

<header data-tauri-drag-region><h1 data-tauri-drag-region>Settings</h1></header>

<main>
	<div class="picker"><GlassPicker options={[...tabs]} bind:selected={tab} /></div>

	{#if tab === 'Following'}
		{#if follows.leagues.length === 0 && follows.teams.length === 0}
			<div class="empty-state">
				<div>
					<strong>Nothing Followed</strong>
					<p>Star a team or league on its page, on a game, or from the sidebar search.</p>
				</div>
			</div>
		{/if}
		{#if follows.leagues.length}
			<section class="sports-card">
				<h2>Leagues</h2>
				{#each follows.leagues as id, i (id)}
					{@const l = leagueOf(id)}
					{#if l}
						{#if i > 0}<hr />{/if}
						<div class="row">
							<img src={leagueLogo(l)} alt="" width="22" height="22" />
							<a class="grow" href="/league?league={id}">{l.name}</a>
							<FollowButton leagueID={id} name={l.abbreviation} />
						</div>
					{/if}
				{/each}
			</section>
		{/if}
		{#if follows.teams.length}
			<section class="sports-card">
				<h2>Teams</h2>
				{#each follows.teams as { leagueID, team }, i (leagueID + team.id)}
					{#if i > 0}<hr />{/if}
					<div class="row">
						<img src={team.logo} alt="" width="22" height="22" />
						<a class="grow two" href="/league?league={leagueID}&team={team.id}"><span>{team.displayName}</span><small>{leagueOf(leagueID)?.abbreviation}</small></a>
						<FollowButton {leagueID} {team} name={team.shortName} />
					</div>
				{/each}
			</section>
		{/if}
		<p class="footnote">Followed teams come first on Home under My Teams. Alert settings for each will arrive with notifications.</p>
	{:else}
		<LeagueSetup bind:leagues={fantasyLeagues} onclose={() => goto('/fantasy')} />
	{/if}
</main>

<style>
	header {
		position: sticky;
		top: 0;
		z-index: 2;
		height: 52px;
		display: flex;
		align-items: center;
		padding: 0 16px 0 var(--titlebar-inset);
	}
	h1 {
		margin: 0;
		font-size: 17px;
	}
	main {
		max-width: 640px;
		margin: 0 auto;
		padding: 20px;
		box-sizing: border-box;
		display: flex;
		flex-direction: column;
		gap: 14px;
	}
	.picker {
		display: flex;
		justify-content: center;
	}
	.empty-state {
		text-align: center;
	}
	.empty-state strong {
		color: var(--label);
		font-size: 17px;
	}
	.row {
		display: flex;
		align-items: center;
		gap: 10px;
		padding: 7px 0;
	}
	.grow {
		flex: 1;
		min-width: 0;
	}
	.grow:hover span,
	a.grow:not(.two):hover {
		text-decoration: underline;
	}
	.two {
		display: flex;
		flex-direction: column;
	}
	small {
		font-size: var(--caption);
		color: var(--secondary);
	}
	.footnote {
		margin: 0;
		font-size: var(--caption);
		color: var(--secondary);
	}
</style>
