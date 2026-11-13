<script lang="ts">
	// SettingsView.swift: General, Notifications, Following, Fantasy and Summaries.
	import { goto } from '$app/navigation';
	import { inTauri as isTauri } from '$lib/platform';
	import Backdrop from '$lib/Backdrop.svelte';
	import GlassPicker from '$lib/GlassPicker.svelte';
	import FollowButton from '$lib/FollowButton.svelte';
	import LeagueSetup from '$lib/LeagueSetup.svelte';
	import { leagues, leagueLogo } from '$lib/espn';
	import { follows } from '$lib/follows.svelte';
	import { store } from '$lib/fantasy';
	import { teamKey } from '$lib/follows.svelte';
	import { settings, saveSettings } from '$lib/settings.svelte';
	import { events } from '$lib/alerts';
	import { getKey, setKey, model } from '$lib/claude';

	const tabs = ['General', 'Notifications', 'Following', 'Fantasy', 'Summaries'] as const;
	let tab = $state<(typeof tabs)[number]>('General');
	const inTauri = isTauri();

	// Launch at login is the system's own setting, read and written through the autostart plugin.
	let launchAtLogin = $state(false);
	$effect(() => {
		if (inTauri) import('@tauri-apps/plugin-autostart').then((a) => a.isEnabled()).then((on) => (launchAtLogin = on));
	});
	async function setLaunchAtLogin(on: boolean) {
		const a = await import('@tauri-apps/plugin-autostart');
		await (on ? a.enable() : a.disable());
		launchAtLogin = await a.isEnabled();
	}

	// Quiet hours are stored as minutes after midnight and shown as time fields.
	const toTime = (m: number) => `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
	const fromTime = (t: string) => {
		const [h, m] = t.split(':').map(Number);
		return h * 60 + m;
	};
	function toggleMute(key: string) {
		settings.muted = settings.muted.includes(key) ? settings.muted.filter((k) => k !== key) : [...settings.muted, key];
		saveSettings();
	}
	let fantasyLeagues = $state(store.leagues());

	// Summaries: the Anthropic key, kept in the Keychain (Credential Manager on Windows), never shown once saved.
	let hasKey = $state(false);
	let draft = $state('');
	let keyError = $state<string | undefined>();
	$effect(() => {
		getKey().then((k) => (hasKey = !!k));
	});
	async function saveKey(value: string) {
		try {
			await setKey(value);
			hasKey = !!value.trim();
			[draft, keyError] = ['', undefined];
		} catch {
			keyError = inTauri ? 'The Keychain couldn’t save the key.' : 'The key couldn’t be saved.';
		}
	}
	const leagueOf = (id: string) => leagues.find((l) => l.id === id);
</script>

<svelte:head><title>Settings · Halftime</title></svelte:head>
<Backdrop color="#1c1c1e" />

<header data-tauri-drag-region><h1 data-tauri-drag-region>Settings</h1></header>

<main>
	<div class="picker"><GlassPicker options={[...tabs]} bind:selected={tab} /></div>

	{#snippet toggle(label: string, checked: boolean, onchange: (on: boolean) => void, disabled = false)}
		<label class="toggle-row">
			<span>{label}</span>
			<input type="checkbox" role="switch" {checked} {disabled} onchange={(e) => onchange(e.currentTarget.checked)} />
		</label>
	{/snippet}

	{#if !inTauri && (tab === 'General' || tab === 'Notifications')}
		<p class="footnote">These settings take effect in the desktop app, which runs the menu-bar score and alerts.</p>
	{/if}

	{#if tab === 'General'}
		<section class="sports-card">
			{@render toggle('Launch at login', launchAtLogin, setLaunchAtLogin, !inTauri)}
			<p class="footnote">Alerts only arrive while Halftime is running, so it stays in the menu bar.</p>
			<hr />
			{@render toggle('Close to Menu', settings.closeToMenu, (on) => ((settings.closeToMenu = on), saveSettings()))}
			<p class="footnote">Closing the window leaves Halftime in the menu bar (the system tray on Windows). Scores and alerts keep coming.</p>
			<hr />
			<label class="toggle-row">
				<span>Units</span>
				<select class="units" value={settings.units} onchange={(e) => ((settings.units = e.currentTarget.value as 'metric' | 'imperial'), saveSettings())}>
					<option value="metric">Metric (°C, km/h)</option>
					<option value="imperial">Imperial (°F, mph)</option>
				</select>
			</label>
			<p class="footnote">For weather at the venue. Field and court measurements stay in each sport’s own units.</p>
		</section>
	{:else if tab === 'Notifications'}
		<section class="sports-card">
			<h2>Alert me about</h2>
			{#each events as event, i}
				{#if i > 0}<hr />{/if}
				{@render toggle(event.title, settings.alerts[event.type], (on) => ((settings.alerts[event.type] = on), saveSettings()))}
			{/each}
			<p class="footnote">These apply to everything you follow. Mute a team under Following.</p>
		</section>
		<section class="sports-card">
			{@render toggle('Quiet hours', settings.quietHours.enabled, (on) => ((settings.quietHours.enabled = on), saveSettings()))}
			{#if settings.quietHours.enabled}
				<hr />
				<label class="toggle-row">From <input type="time" value={toTime(settings.quietHours.start)} onchange={(e) => ((settings.quietHours.start = fromTime(e.currentTarget.value)), saveSettings())} /></label>
				<hr />
				<label class="toggle-row">Until <input type="time" value={toTime(settings.quietHours.end)} onchange={(e) => ((settings.quietHours.end = fromTime(e.currentTarget.value)), saveSettings())} /></label>
			{/if}
			<p class="footnote">Alerts during quiet hours are held until they end; you get the latest one per game.</p>
		</section>
	{:else if tab === 'Following'}
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
						<label class="mute"><input type="checkbox" role="switch" checked={settings.muted.includes(teamKey(leagueID, team.id))} onchange={() => toggleMute(teamKey(leagueID, team.id))} />Mute</label>
						<FollowButton {leagueID} {team} name={team.shortName} />
					</div>
				{/each}
			</section>
		{/if}
		<p class="footnote">Followed teams come first on Home under My Teams and in the menu bar. A muted team sends no alerts.</p>
	{:else if tab === 'Fantasy'}
		<LeagueSetup bind:leagues={fantasyLeagues} onclose={() => goto('/fantasy')} />
	{:else}
		<section class="sports-card">
			<h2>Anthropic API</h2>
			{#if hasKey}
				<div class="toggle-row">
					<span>API key</span>
					<span class="saved">Saved in {inTauri ? 'Keychain' : 'this browser session'} <button class="remove" onclick={() => saveKey('')}>Remove Key</button></span>
				</div>
			{:else}
				<form class="key-row" onsubmit={(e) => (e.preventDefault(), saveKey(draft))}>
					<input type="password" bind:value={draft} placeholder="sk-ant-…" aria-label="Anthropic API key" autocomplete="off" spellcheck="false" />
					<button class="glass save" disabled={!draft.trim()}>Save</button>
				</form>
			{/if}
			{#if keyError}<p class="footnote error" role="alert">{keyError}</p>{/if}
			<p class="footnote">
				Claude writes game recaps, answers questions the stats can't, and briefs you on your fantasy week, using {model}. Get a key at console.anthropic.com.
				{#if !inTauri}On the web the key is kept only until this tab closes.{/if}
			</p>
		</section>
		<p class="footnote">The Mac app can also use Apple's on-device model. It doesn't exist on Windows, so this version uses Claude only.</p>
	{/if}
</main>

<style>
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
	.toggle-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 12px;
		padding: 7px 0;
	}
	.sports-card > .footnote {
		margin-bottom: 4px;
	}
	/* A macOS-style switch. */
	input[type='checkbox'][role='switch'] {
		appearance: none;
		-webkit-appearance: none;
		position: relative;
		flex: none;
		width: 32px;
		height: 18px;
		margin: 0;
		border-radius: 999px;
		background: rgba(255, 255, 255, 0.18);
		transition: background 0.2s;
	}
	input[type='checkbox'][role='switch']::after {
		content: '';
		position: absolute;
		top: 2px;
		left: 2px;
		width: 14px;
		height: 14px;
		border-radius: 50%;
		background: white;
		box-shadow: 0 1px 2px rgba(0, 0, 0, 0.3);
		transition: transform 0.2s;
	}
	input[type='checkbox'][role='switch']:checked {
		background: #30d158;
	}
	input[type='checkbox'][role='switch']:checked::after {
		transform: translateX(14px);
	}
	input[type='checkbox'][role='switch']:disabled {
		opacity: 0.4;
	}
	input[type='time'] {
		font: inherit;
		color: var(--label);
		background: rgba(255, 255, 255, 0.08);
		border: 0.5px solid rgba(255, 255, 255, 0.18);
		border-radius: 6px;
		padding: 3px 6px;
		color-scheme: dark;
	}
	.units {
		font: inherit;
		color: var(--label);
		background: rgba(255, 255, 255, 0.08);
		border: 0.5px solid rgba(255, 255, 255, 0.18);
		border-radius: 6px;
		padding: 3px 6px;
		color-scheme: dark;
	}
	.saved {
		display: flex;
		align-items: center;
		gap: 12px;
		color: var(--secondary);
	}
	.remove {
		color: #ff6961;
		font-weight: 600;
	}
	.key-row {
		display: flex;
		gap: 8px;
		padding: 7px 0;
	}
	.key-row input {
		flex: 1;
		font: inherit;
		color: var(--label);
		background: rgba(255, 255, 255, 0.08);
		border: 0.5px solid rgba(255, 255, 255, 0.18);
		border-radius: 7px;
		padding: 5px 8px;
		user-select: text;
		-webkit-user-select: text;
	}
	.save {
		padding: 4px 14px;
		border-radius: 999px;
		font-weight: 600;
	}
	.save:disabled {
		opacity: 0.5;
	}
	.error {
		color: #ff6961;
	}
	.mute {
		display: flex;
		align-items: center;
		gap: 6px;
		font-size: var(--subheadline);
		color: var(--secondary);
	}
	.footnote {
		margin: 0;
		font-size: var(--caption);
		color: var(--secondary);
	}
</style>
