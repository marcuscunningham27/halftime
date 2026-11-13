<script lang="ts">
	// FantasySettings.swift: add a Sleeper league by username, or an ESPN league by ID (plus cookies when private).
	import GlassPicker from './GlassPicker.svelte';
	import { store, refID, nflState, sleeperUserID, sleeperLeagues, espnLeague, type LeagueRef } from './fantasy';

	let { leagues = $bindable(), onclose }: { leagues: LeagueRef[]; onclose: () => void } = $props();

	let provider = $state<'Sleeper' | 'ESPN Fantasy'>('Sleeper');
	let username = $state('');
	let leagueID = $state('');
	let espnS2 = $state('');
	let swid = $state('');
	let busy = $state(false);
	let error = $state<string | undefined>();
	/** What the search found: leagues to add (Sleeper) or teams to pick from (ESPN). */
	let found = $state<{ label: string; ref: LeagueRef }[]>([]);
	/** Cookies that opened the league just searched; saved only when one of its teams is added. */
	let pendingCookies: { leagueID: string; credentials?: { espnS2: string; swid: string } } | undefined;

	async function find() {
		busy = true;
		error = undefined;
		found = [];
		try {
			const { season } = await nflState();
			if (provider === 'Sleeper') {
				const userID = await sleeperUserID(username);
				if (!userID) throw new Error(`No Sleeper user called “${username.trim()}”.`);
				const list = await sleeperLeagues(userID, season);
				if (!list.length) throw new Error(`No NFL leagues for ${season}.`);
				found = list.map((l) => ({ label: l.name, ref: { provider: 'sleeper', leagueID: l.id, name: l.name, memberID: userID } }));
			} else {
				const id = leagueID.trim();
				const credentials = espnS2.trim() && swid.trim() ? { espnS2: espnS2.trim(), swid: swid.trim() } : undefined;
				const league = await espnLeague(id, season, credentials);
				pendingCookies = { leagueID: id, credentials };
				found = league.teams.map((t) => ({ label: t.name, ref: { provider: 'espn', leagueID: id, name: league.name, memberID: t.id } }));
			}
		} catch (e) {
			error = e instanceof Error ? e.message : String(e);
		}
		busy = false;
	}

	async function add(ref: LeagueRef) {
		if (ref.provider === 'espn' && pendingCookies?.leagueID === ref.leagueID) {
			try {
				await store.setCredentials(ref.leagueID, pendingCookies.credentials);
			} catch {
				error = 'Couldn’t save the ESPN cookies to the Keychain.';
				return;
			}
		}
		leagues = [...leagues.filter((l) => refID(l) !== refID(ref)), ref];
		store.saveLeagues(leagues);
		store.setActive(refID(ref));
		onclose();
	}

	function remove(ref: LeagueRef) {
		leagues = leagues.filter((l) => refID(l) !== refID(ref));
		store.saveLeagues(leagues);
		if (ref.provider === 'espn') store.setCredentials(ref.leagueID);
	}
</script>

<section class="card">
	<div class="top">
		<h2>Manage Leagues</h2>
		{#if leagues.length}<button class="text" onclick={onclose}>Done</button>{/if}
	</div>

	{#if leagues.length}
		<ul class="saved">
			{#each leagues as league (refID(league))}
				<li>
					<span><strong>{league.name}</strong><small>{league.provider === 'sleeper' ? 'Sleeper' : 'ESPN Fantasy'}</small></span>
					<button class="text danger" onclick={() => remove(league)}>Remove</button>
				</li>
			{/each}
		</ul>
	{/if}

	<div class="picker"><GlassPicker options={['Sleeper', 'ESPN Fantasy']} bind:selected={provider} /></div>

	<form onsubmit={(e) => (e.preventDefault(), find())}>
		{#if provider === 'Sleeper'}
			<label>Sleeper username <input bind:value={username} autocomplete="off" spellcheck="false" required /></label>
		{:else}
			<label>League ID <input bind:value={leagueID} inputmode="numeric" autocomplete="off" required /></label>
			<p class="hint">Private league? Copy the <code>espn_s2</code> and <code>SWID</code> cookies from espn.com while signed in.</p>
			<label>espn_s2 <input bind:value={espnS2} autocomplete="off" spellcheck="false" /></label>
			<label>SWID <input bind:value={swid} autocomplete="off" spellcheck="false" placeholder="{'{'}…{'}'}" /></label>
		{/if}
		<button class="glass action" disabled={busy}>{busy ? 'Looking…' : provider === 'Sleeper' ? 'Find Leagues' : 'Find League'}</button>
	</form>

	{#if error}<p class="error" role="alert">{error}</p>{/if}
	{#if found.length}
		<p class="hint">{provider === 'Sleeper' ? 'Choose a league:' : 'Which team is yours?'}</p>
		<ul class="found">
			{#each found as item}
				<li><button onclick={() => add(item.ref)}>{item.label}<span>Add</span></button></li>
			{/each}
		</ul>
	{/if}
</section>

<style>
	.card {
		padding: 12px 16px 16px;
		border-radius: 22px;
		background: rgba(0, 0, 0, 0.38);
		box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.1);
		display: flex;
		flex-direction: column;
		gap: 12px;
	}
	.top {
		display: flex;
		justify-content: space-between;
		align-items: center;
	}
	h2 {
		margin: 0;
		font-size: var(--headline);
	}
	.picker {
		display: flex;
		justify-content: center;
	}
	form {
		display: flex;
		flex-direction: column;
		gap: 10px;
	}
	label {
		display: flex;
		flex-direction: column;
		gap: 4px;
		font-size: var(--subheadline);
		color: var(--secondary);
	}
	input {
		font: inherit;
		font-size: var(--body);
		color: var(--label);
		background: rgba(255, 255, 255, 0.08);
		border: 0.5px solid rgba(255, 255, 255, 0.18);
		border-radius: 7px;
		padding: 6px 8px;
		user-select: text;
		-webkit-user-select: text;
	}
	input:focus {
		outline: 3px solid rgba(10, 132, 255, 0.55);
		outline-offset: 0;
	}
	.action {
		align-self: flex-start;
		padding: 6px 16px;
		border-radius: 999px;
		font-weight: 600;
	}
	.action:disabled {
		opacity: 0.6;
	}
	.hint {
		margin: 0;
		font-size: var(--subheadline);
		color: var(--secondary);
	}
	code {
		font-size: 0.95em;
	}
	.error {
		margin: 0;
		color: #ff6961;
		font-size: var(--subheadline);
	}
	ul {
		list-style: none;
		margin: 0;
		padding: 0;
	}
	.saved li, .found li {
		border-top: 1px solid var(--separator);
	}
	.saved li {
		display: flex;
		justify-content: space-between;
		align-items: center;
		padding: 8px 0;
	}
	.saved span {
		display: flex;
		flex-direction: column;
	}
	small {
		color: var(--secondary);
		font-size: var(--caption);
	}
	.found button {
		width: 100%;
		display: flex;
		justify-content: space-between;
		padding: 9px 4px;
		text-align: left;
		border-radius: 6px;
	}
	.found button:hover {
		background: rgba(255, 255, 255, 0.06);
	}
	.found button span, .text {
		color: #64a8ff;
		font-weight: 600;
	}
	.text.danger {
		color: #ff6961;
	}
</style>
