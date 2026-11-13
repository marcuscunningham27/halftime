<script lang="ts">
	// FieldView.swift: a tilted ESPN-style field with the drive drawn on it. Away end zone left, home right.
	import { type Game, type FieldState, type PlayMark, yardsGained, backdropHex, hex } from './espn';
	let { game, field }: { game: Game; field: FieldState } = $props();

	const height = 170;
	let width = $state(700);

	/** Horizontal position of a spot measured from the home goal; the field is 120 units including end zones. */
	const x = (yards: number) => (width * (10 + (100 - yards))) / 120;
	const pinHeight = 40;
	/** Plays stack from the top of the field down, oldest first, leaving room for the pin and the yardage label. */
	const rowY = (i: number) => {
		const rows = Math.max(field.marks.length, 4), top = pinHeight + 4, bottom = 28;
		return top + ((height - top - bottom) * i) / (rows - 1);
	};

	const teams = $derived([game.away.team, game.home.team]);
	const offense = $derived(teams.find((t) => t.id === field.offenseTeamID));
	const homeOffense = $derived(field.offenseTeamID === game.home.team.id);
	const offenseColor = $derived(hex(offense?.color));
	const direction = $derived(homeOffense ? -1 : 1);
	const ballX = $derived(x(field.ball));
	const ballY = $derived(rowY(Math.max(field.marks.length - 1, 0)));
	const last = $derived(field.marks.at(-1));

	function path(m: PlayMark, y: number): string {
		const from = x(m.start), to = x(m.end);
		if (m.kind === 'pass' || m.kind === 'incomplete') {
			// Passes arc up between snap and catch (or where the ball fell incomplete, at the line).
			const land = m.kind === 'incomplete' ? from + (to === from ? direction * 22 : to - from) : to;
			return `M${from},${y} Q${(from + land) / 2},${y - 14} ${land},${y}`;
		}
		return `M${from},${y} L${to},${y}`;
	}
	const stroke = (m: PlayMark) =>
		m.kind === 'incomplete' ? 'rgba(255,255,255,0.5)'
		: m.kind === 'loss' ? '#ff3b30'
		: m.kind === 'penalty' ? 'rgba(255,214,10,0.8)'
		: `color-mix(in srgb, ${offenseColor}, white 35%)`;
	const dash = (m: PlayMark) => (m.kind === 'incomplete' ? '3 3' : m.kind === 'penalty' ? '1 3' : undefined);

	function yardage(m: PlayMark): string | undefined {
		if (m.kind === 'incomplete') return 'Incomplete';
		const y = yardsGained(m.play, homeOffense);
		return y === undefined ? undefined : y === 0 ? 'No Gain' : y > 0 ? `+${y} Yds` : `−${-y} Yds`;
	}

	const label = $derived([field.down, field.ballOn && `ball on ${field.ballOn}`, field.drive, field.lastPlay?.text].filter(Boolean).join(', '));
</script>

<div class="wrap" role="img" aria-label={label}>
	<div class="header">
		{#each [['Down', field.down], ['Ball On', field.ballOn], ['Drive', field.drive]] as [title, value], i}
			{#if i > 0}<span class="divider"></span>{/if}
			<div class="stat"><span class="title">{title}:</span><span class="value">{value ?? '–'}</span></div>
		{/each}
	</div>

	<div class="stage">
		<div class="tilt">
			<div class="field" bind:clientWidth={width}>
				<svg {width} {height} aria-hidden="true">
					<defs>
						<linearGradient id="light" x1="0" y1="0" x2="1" y2="1">
							<stop offset="0" stop-color="white" stop-opacity="0.1" />
							<stop offset="0.5" stop-color="white" stop-opacity="0" />
							<stop offset="1" stop-color="black" stop-opacity="0.12" />
						</linearGradient>
						<linearGradient id="possession" x1={homeOffense ? 0 : 1} x2={homeOffense ? 1 : 0} y1="0" y2="0">
							<stop offset="0" stop-color={offenseColor} stop-opacity="0.55" />
							<stop offset="1" stop-color={offenseColor} stop-opacity="0.05" />
						</linearGradient>
					</defs>
					<!-- Grass mown in 10-yard stripes, end zones in team colours. -->
					<rect width={width / 12} {height} fill={hex(backdropHex(game.away.team))} />
					{#each { length: 10 } as _, i}
						<rect x={(width * (i + 1)) / 12} width={width / 12 + 0.5} {height} fill={i % 2 ? '#40983c' : '#4ca846'} />
					{/each}
					<rect x={(width * 11) / 12} width={width / 12} {height} fill={hex(backdropHex(game.home.team))} />
					<text class="endzone" transform="translate({width / 24},{height / 2}) rotate(-90)">{game.away.team.abbreviation}</text>
					<text class="endzone" transform="translate({(width * 23) / 24},{height / 2}) rotate(90)">{game.home.team.abbreviation}</text>
					<rect {width} {height} fill="url(#light)" />
					<!-- Yard lines every 5 (brighter every 10, brightest at midfield), and a tick each yard on both hash rows. -->
					{#each { length: 19 } as _, i}
						{@const yard = (i + 1) * 5}
						<rect x={x(yard) - 0.5} width="1" {height} fill="white" fill-opacity={yard === 50 ? 0.6 : yard % 10 === 0 ? 0.35 : 0.18} />
					{/each}
					{#each { length: 99 } as _, i}
						{#if (i + 1) % 5 !== 0}
							<rect x={x(i + 1) - 0.5} y={height * 0.36 - 2.5} width="1" height="5" fill="white" fill-opacity="0.3" />
							<rect x={x(i + 1) - 0.5} y={height * 0.64 - 2.5} width="1" height="5" fill="white" fill-opacity="0.3" />
						{/if}
					{/each}
					<!-- Yard numbers along both sidelines, the far row upside down as on a real field. -->
					{#each { length: 9 } as _, i}
						{@const n = Math.min(i + 1, 9 - i) * 10}
						<text class="yard" x={x((i + 1) * 10)} y={height - 11}>{n}</text>
						<text class="yard" transform="translate({x((i + 1) * 10)},11) rotate(180)" y="-5">{n}</text>
					{/each}
					<image href={game.home.team.logo} x={width / 2 - height * 0.19} y={height * 0.31} width={height * 0.38} height={height * 0.38} opacity="0.8" />
					{#if game.status === 'live' && offense}
						<!-- The offence's attacking side shaded from the ball, chevrons running toward the end zone. -->
						{@const end = homeOffense ? 0 : width}
						<rect x={Math.min(ballX, end)} width={Math.abs(end - ballX)} {height} fill="url(#possession)" />
						{#each [0, 1, 2] as i}
							<path
								class="chevron"
								style:animation-delay="{(-i * 1.6) / 3}s"
								style:--dx="{direction * Math.abs(end - ballX) * 22 / 47}px"
								d="M{ballX + direction * Math.abs(end - ballX) * 6 / 47 - direction * height * 0.06},{height * 0.36} l{direction * height * 0.12},{height * 0.14} l{-direction * height * 0.12},{height * 0.14}"
								stroke-width={height * 0.044}
							/>
						{/each}
					{/if}
					<!-- ESPN's lines: blue at the line of scrimmage, yellow at the line to gain. -->
					<rect class="slide" x={ballX - 1} width="2" {height} fill="#4080ff" />
					{#if field.lineToGain !== undefined}<rect class="slide" x={x(field.lineToGain) - 1} width="2" {height} fill="#ffd60a" />{/if}
					{#each field.marks as m, i}
						<path d={path(m, rowY(i))} fill="none" stroke={stroke(m)} stroke-width="2" stroke-linecap="round" stroke-dasharray={dash(m)} />
						<circle cx={x(m.start)} cy={rowY(i)} r="2" fill="white" fill-opacity="0.7" />
					{/each}
				</svg>

				{#if last && yardage(last)}
					<span class="yardage" style:left="{x(last.end)}px" style:top="{rowY(field.marks.length - 1) + 15}px">{yardage(last)}</span>
				{/if}
				<span class="pulse" style:left="{ballX}px" style:top="{ballY}px" style:--c="color-mix(in srgb, {offenseColor}, white 40%)"></span>
				{#if offense}
					<!-- ESPN's possession marker: a white pin with the offence's logo, its point on the ball. -->
					<span class="pin" style:left="{ballX}px" style:top="{ballY - pinHeight}px">
						<svg width="32" height={pinHeight} viewBox="0 0 32 40" aria-hidden="true">
							<path d="M4.7,27.3 A16,16 0 1 1 27.3,27.3 L16,40 Z" fill="white" stroke="rgba(0,0,0,0.75)" stroke-width="1.5" />
						</svg>
						<img src={offense.logo} alt="" width="20" height="20" />
					</span>
				{/if}
			</div>
			<!-- The field's front edge, for ESPN's raised look. -->
			<div class="edge">
				<span style:background={hex(backdropHex(game.away.team))}></span>
				<span style:flex="10" style:background="#40983c"></span>
				<span style:background={hex(backdropHex(game.home.team))}></span>
			</div>
		</div>
		<!-- Goalposts stand upright, outside the tilt, just behind each end line. -->
		{#each ['left', 'right'] as side}
			<svg class="goalpost {side}" viewBox="0 0 36 100" width="36" height="100" aria-hidden="true">
				<path d="M6,90 L6,74 Q6,62 18,60 M10,66 L26,54 M10,66 L10,12 M26,54 L26,0" fill="none" stroke="#e3c940" stroke-width="3" stroke-linejoin="round" />
				<rect x="3" y="86" width="6" height="14" rx="2" fill="#595959" />
			</svg>
		{/each}
	</div>
</div>

<style>
	.wrap {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}
	.header {
		display: flex;
		align-items: center;
		padding-bottom: 4px;
	}
	.divider {
		width: 1px;
		height: 34px;
		background: var(--separator);
	}
	.stat {
		flex: 1;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 2px;
		min-width: 0;
	}
	.title {
		font-size: var(--caption);
		font-weight: 500;
		color: var(--secondary);
		text-transform: uppercase;
	}
	.value {
		font-size: var(--title3);
		font-weight: 500;
		white-space: nowrap;
	}
	.stage {
		position: relative;
		padding-top: 28px;
	}
	/* SwiftUI's rotation3DEffect(22°, x axis, perspective 0.5). */
	.tilt {
		transform: perspective(700px) rotateX(22deg);
		transform-origin: center;
		border-radius: 8px;
		overflow: hidden;
		box-shadow: 0 0 0 1.5px rgba(255, 255, 255, 0.85);
	}
	.field {
		position: relative;
		height: 170px;
	}
	.field svg {
		display: block;
	}
	.endzone {
		font: 900 13px system-ui;
		font-stretch: expanded;
		letter-spacing: 0.08em;
		fill: rgba(255, 255, 255, 0.9);
		text-anchor: middle;
		dominant-baseline: central;
	}
	.yard {
		font: 700 13px system-ui;
		fill: rgba(255, 255, 255, 0.6);
		text-anchor: middle;
		dominant-baseline: central;
	}
	.chevron {
		fill: none;
		stroke: white;
		stroke-linecap: round;
		stroke-linejoin: round;
		animation: drift 1.6s linear infinite;
	}
	@keyframes drift {
		0% { transform: translateX(0); opacity: 0; }
		50% { opacity: 0.55; }
		100% { transform: translateX(var(--dx)); opacity: 0; }
	}
	.slide, .pin, .pulse, .yardage {
		transition: x 0.8s cubic-bezier(0.3, 1.2, 0.5, 1), left 0.8s cubic-bezier(0.3, 1.2, 0.5, 1), top 0.8s;
	}
	.yardage {
		position: absolute;
		transform: translate(-50%, -50%);
		padding: 2px 7px;
		border-radius: 5px;
		background: #e6e6e6;
		color: rgba(0, 0, 0, 0.8);
		font-size: var(--caption);
		font-weight: 700;
		white-space: nowrap;
	}
	.pulse {
		position: absolute;
		width: 16px;
		height: 16px;
		margin: -8px 0 0 -8px;
		border-radius: 50%;
		border: 1.5px solid var(--c);
		animation: pulse 1.4s ease-out infinite;
		pointer-events: none;
	}
	@keyframes pulse {
		from { transform: scale(1); opacity: 1; }
		to { transform: scale(2.1); opacity: 0; }
	}
	.pin {
		position: absolute;
		width: 32px;
		height: 40px;
		margin-left: -16px;
		filter: drop-shadow(0 1px 2px rgba(0, 0, 0, 0.3));
	}
	.pin svg {
		position: absolute;
		inset: 0;
	}
	.pin img {
		position: absolute;
		top: 6px;
		left: 6px;
	}
	.edge {
		display: flex;
		height: 7px;
		filter: brightness(0.75);
	}
	.edge span {
		flex: 1;
	}
	.goalpost {
		position: absolute;
		top: 14px;
	}
	.goalpost.left {
		left: -4px;
	}
	.goalpost.right {
		right: -4px;
		transform: scaleX(-1);
	}
	@media (prefers-reduced-motion: reduce) {
		.chevron, .pulse { animation: none; }
	}
</style>
