# DayNightCycle

A configurable, event-driven day/night cycle for Roblox experiences. It runs a full 24-hour game day over a real-world duration you choose, from server start to shutdown, and gives you named time events, variable-speed phases (so the night can pass faster than the day), and per-phase lighting looks that blend smoothly.

The server owns the clock and replicates it with attributes. Every machine derives the current time from `workspace:GetServerTimeNow()`, so there is no per-frame network traffic, late joiners are in sync the moment they start, and the Server and Clients fire time events together.

## Features

- **Server-authoritative clock**: One small state value is replicated. Everything else is calculated locally from the shared server time. No RemoteEvents.
- **Time events**: Fire named events at specific in-game hours (e.g. "Dawn", "Midnight") on both the Server and the Clients. Add and remove them at runtime.
- **Phases with variable speed**: Divide the day into phases (Night, Dawn, Day, Dusk by default) and give each a `TimeShare` that sets how fast it passes.
- **Lighting looks**: Each phase can set properties on `Lighting`, `Atmosphere`, `BloomEffect`, `SunRaysEffect` and `ColorCorrectionEffect`. The lighting blends between looks as the day moves through the phases.
- **Runtime control**: Pause, resume, jump to a time, set the day number, and change the day length from the Server.
- **HUD-friendly attributes**: `Day`, `IsPaused` and `Phase` are published as attributes on `Lighting`.
- **Lifecycle ready**: Works with the [ModuleLoader](https://github.com/Distracted-Games/ModuleLoader) framework.
- **Integrated logging**: Uses the included [Logger](https://github.com/Distracted-Games/Logger) utility for toggleable debug output.

## Installation

The easiest way to install DayNightCycle is to grab the latest `.rbxm` release.

1. Download the `DayNightCycle.rbxl` file from the [Latest Release Page](https://github.com/Distracted-Games/ProDayNightCycle/releases/latest).
2. Open the `.rbxl` file in Roblox Studio.
3. Everything you need is set up in that place, including `ServerAuthority` and the primary module being in the `ReplicatedStorage/Source/Simulation` folder, plus my [`ModuleLoader`](https://github.com/Distracted-Games/ModuleLoader) setup. 

If you use the above installation method and want to move the files into your own project, make sure to include the `ReplicatedStorage/Source/Utility/Logger` and `ReplicatedStorage/Source/Libs/Signal` modules as well. These are direct dependencies of the primary module. If not using my `ModuleLoader`, you will need to be sure and `require()` and call `DayNightCycle.Start()` from both the server and client.

## Configuration

All configuration lives in the `Config` module inside `DayNightCycle`. It is read when the cycle starts, so edit it in Studio rather than at runtime; use the [API](#api-reference) to change things while the game runs.

| Setting | Description |
|---------|-------------|
| `DayLengthInMinutes` | Real-world minutes for a full 24-hour game day (default `180`). |
| `StartTimeOfDay` | The hour (0-24) to start at. `nil` uses the current `Lighting` time. |
| `StartDay` | The value of `Day` when the cycle starts (default `1`). Each game decides what a "day" means. |
| `TimeEvents` | A dictionary mapping event names to game hours. |
| `Phases` | The parts of the day, with their speed and lighting. See [Phases and Lighting](#phases-and-lighting). |
| `Lighting.Enabled` | Whether phase looks are applied to `Lighting` on Clients (default `true`). |

```lua
const Config: Types.Config = {
	DayLengthInMinutes = 180,
	StartTimeOfDay = nil,
	StartDay = 1,
	TimeEvents = {
		Dawn = 4.75, -- 4:45 AM
		Sunrise = 5.75, -- 5:45 AM
		Midday = 12.0, -- 12:00 PM
		Sunset = 17.6, -- 5:36 PM
		Dusk = 18.25, -- 6:15 PM
		Midnight = 0.0, -- 12:00 AM
	},
	-- Phases = { ... }, Lighting = { Enabled = true },
}
```

> ***Note**: The default event times are synced with the default Roblox Lighting times for those events. If your lighting differs, you may have to adjust them.*

Event names may only contain letters, numbers and underscores, at most 40 characters, and there can be at most 63 events. These limits come from how Roblox limits attributes.

## Phases and Lighting

A phase is a named part of the day. It starts at the hour of one of your time events (its `StartEvent`) and lasts until the next phase starts, wrapping past midnight. The defaults are:

| Phase | Starts at event | TimeShare | Real-world time at 180 minutes |
|-------|-----------------|-----------|--------------------------------|
| Night | `Dusk` (18:15) | 28 | about 50 minutes |
| Dawn | `Dawn` (4:45) | 4 | about 7 minutes |
| Day | `Sunrise` (5:45) | 65 | about 117 minutes |
| Dusk | `Sunset` (17:36) | 3 | about 5 minutes |

```lua
{
	Name = "Dusk",
	StartEvent = "Sunset",
	TimeShare = 3,
	BlendHours = 0.35,
	Look = {
		Lighting = { Brightness = 2, ColorShift_Top = Color3.fromRGB(255, 190, 125) },
		Atmosphere = { Color = Color3.fromRGB(255, 180, 140), Haze = 2 },
		Bloom = { Intensity = 0.15 },
	},
}
```

- **`TimeShare`** is the phase's relative share of the real-world day length. Only the ratios matter. If you leave it out, the phase's length in game hours is used. Leave `Phases` empty for a constant speed.
- **`BlendHours`** is how many game hours, from the start of the phase, the lighting spends blending from the previous phase's look to this one (limited to the phase's length). The default is `0.75`. Blending follows game time, so it speeds up, slows down and pauses with the clock.
- **`Look`** has optional `Lighting`, `Atmosphere`, `Bloom`, `SunRays` and `ColorCorrection` tables, each with optional properties (see `Types.luau` for the full list; your editor will autocomplete them). A property a phase leaves out keeps the value from the closest earlier phase that sets it. Numbers and colors blend smoothly.
- Effects are found inside `Lighting`, or created on the Client if they are missing.
- The server never changes `Lighting`. Set `Lighting.Enabled = false` to control the lighting yourself; phases still set the speed of time.
- Events that start a phase belong to the phase: `AddTimeEvent` and `RemoveTimeEvent` refuse to change them.

## Usage

Call `Start()` once on the Server and once on each Client.

### Using the ModuleLoader
If you are using the [ModuleLoader](https://github.com/Distracted-Games/ModuleLoader) framework and have placed the module in `ReplicatedStorage/Source`, the loader will automatically call `Start()` on the Client.

**Important Note:** If you placed the module in `ReplicatedStorage`, the ModuleLoader will not automatically start it on the Server. Call `DayNightCycle.Start()` from your `ServerStart` script after all modules have finished their Setup phase:

```lua
-- Inside your ServerStart script:
const DayNightCycle = require(ReplicatedStorage.DayNightCycle)
DayNightCycle.Start()
```

If you did not place the module in a `Source` folder within `ReplicatedStorage`, call `Start()` on the Client yourself, as below.

### Standalone Usage
**Server Script:**
```lua
const ReplicatedStorage = game:GetService("ReplicatedStorage")
const DayNightCycle = require(ReplicatedStorage.DayNightCycle)

DayNightCycle.Start()
```

**Local Script:**
```lua
const ReplicatedStorage = game:GetService("ReplicatedStorage")
const DayNightCycle = require(ReplicatedStorage:WaitForChild("DayNightCycle"))

-- The Client follows the Server's clock, including when joining mid-cycle.
DayNightCycle.Start()
```

### Listening for Events
Connect to `DayNightCycle.TimeEvent` from any script, on the Server or a Client. Events fire when the clock crosses their hour.

```lua
const DayNightCycle = require(ReplicatedStorage.DayNightCycle)

DayNightCycle.TimeEvent:Connect(function(eventName: string, eventHour: number)
	if eventName == "Dusk" then
		print("The sun has set! Spawning night monsters...")
	elseif eventName == "Dawn" then
		print("The sun is rising! Despawning monsters...")
	end
end)

DayNightCycle.PhaseChanged:Connect(function(newPhase: string, previousPhase: string)
	print(`{previousPhase} -> {newPhase}`)
end)
```

By the time a listener runs, the clock, `GetPhase()`, `GetDay()` and the attributes on `Lighting` are all up to date. When one frame brings both a phase change and time events, `PhaseChanged` fires first. Listeners on the Server may call `SetTime`, `Pause`, `SetDay` and the other control functions; the new state is kept.

Events are detected from the clock, so they fire the same way on every machine. If a Client stalls (for example a phone app in the background), events from before the last 30 seconds are skipped rather than replayed all at once.

### Adding Time Events at Runtime
From the Server, events replicate to all Clients automatically.

```lua
DayNightCycle.AddTimeEvent("EveningRush", 17.5) -- Fires at 5:30 PM
```

### Controlling Time (Server)
```lua
DayNightCycle.Pause()
DayNightCycle.Resume()
DayNightCycle.SetTime(5.7) -- Jump to 5:42 AM on the current day, silently.
DayNightCycle.SetTime(5.7, true) -- Same, but fire the events passed on the way.
DayNightCycle.SetDayLength(30) -- A day now lasts 30 real-world minutes.
DayNightCycle.SetDay(12) -- Restore a saved day count. The time of day is unchanged.
```

Calls made in the same frame replicate as one update, so a `SetTime(hour, true)` followed by `Pause()` in that frame still fires its skipped events on Clients. Avoid chaining several `SetTime(hour, true)` calls in one frame; Clients fire the events of the final jump only.

### Reading Public State (HUDs)
`Day`, `IsPaused` and `Phase` are attributes on `Lighting`, so a HUD can read them without requiring the module. Use `DayNightCycle.AttributeNames` for the names:

```lua
const Lighting = game:GetService("Lighting")
const names = DayNightCycle.AttributeNames

Lighting:GetAttributeChangedSignal(names.Day):Connect(function()
	print("Day", Lighting:GetAttribute(names.Day))
end)
```

## API Reference

Server-only functions called from a Client log a warning and do nothing.

| Method | Description |
|--------|-------------|
| `Start()` | Starts the cycle on the Server, or begins following the Server's clock on a Client. Call once on each. |
| `AddTimeEvent(name, hour)` | **[Server]** Adds or updates a named time event. Replicates to Clients. |
| `RemoveTimeEvent(name): boolean` | **[Server]** Removes a named time event. Returns whether it existed. |
| `Pause()` | **[Server]** Freezes game time. Events do not fire while paused. |
| `Resume()` | **[Server]** Resumes game time where it paused. |
| `SetTime(hour, fireSkippedEvents?)` | **[Server]** Jumps to an hour on the current day. `Day` is unchanged. Events passed on the way fire in order only if `fireSkippedEvents` is true. |
| `SetDay(day)` | **[Server]** Sets the day number (a whole number), keeping the time. No events fire. Useful for restoring a saved day count. |
| `SetDayLength(minutes)` | **[Server]** Changes the real-world minutes per game day, keeping the current time. |
| `GetCurrentTime(): number` | The current in-game time (0-24). |
| `GetDay(): number` | The current day number. It increases each midnight. |
| `GetPhase(): string?` | The current phase name, or `nil` if no phases are configured. |
| `IsPaused(): boolean` | Whether game time is paused. |

| Property | Description |
|----------|-------------|
| `TimeEvent` | Signal fired when an event's hour is reached. Passes `eventName: string` and `eventHour: number`. |
| `PhaseChanged` | Signal fired when the day moves into a new phase, including after `SetTime`. Passes `newPhase: string` and `previousPhase: string`. |
| `AttributeNames` | The names of the attributes published on `Lighting`: `Day`, `IsPaused` and `Phase`. |

## Upgrading from 3.x

- `StartCycle()` and `StopCycle()` are removed. The cycle runs from `Start()` to shutdown; use `Pause()` and `Resume()` to stop time.
- Configuration moved from the top of the script to `Config.luau`.
- **Clients must call `Start()`.** They no longer start from a Server broadcast.
- The RemoteEvents are gone. State replicates with attributes, and a Client can no longer request a sync.
- Time events fire from the clock instead of per-event flags, and event names are limited to letters, numbers and underscores.
- New: phases, lighting looks, `Pause`, `Resume`, `SetTime`, `SetDay`, `SetDayLength`, `GetDay`, `GetPhase`, `IsPaused` and `PhaseChanged`.

## Performance Notes
- The Server only replicates when the clock changes (start, pause, resume, `SetTime`, `SetDayLength`) or an event is added or removed. Time passing costs no network traffic.
- Each Client applies the time to `Lighting` every frame, and blends the looks 12 times per second, and only when the blend changes.
- Late-joining Clients receive the current state automatically with the instance.

## Debugging
Verbose logging can be enabled by setting `Debug = true` where the module creates its `Logger` in `init.luau`. This prints detailed output about time events, phase changes and re-syncs.

## Development
The pure modules (clock, timeline, events, look blending) are tested outside of Studio with the standalone [Luau](https://github.com/luau-lang/luau) CLI:

```
luau tests/run.luau
```
