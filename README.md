# DayNightCycle

A configurable, event-driven day/night cycle system for Roblox experiences. This module simulates a full 24-hour game day over a customizable real-world duration. It features a robust Client/Server architecture, ensuring smooth visual transitions on the client without flooding the network, while keeping the server synchronized for game logic.

The system allows developers to easily hook into specific times of day (e.g., "Dawn", "Midnight") with dynamic, named events that fire simultaneously on both the Client and the Server.

## Features

- **Client/Server Optimized**: The server tracks logical time and broadcasts state changes, while clients handle visual interpolation via `Lighting:SetMinutesAfterMidnight` for zero network overhead during the cycle.
- **Event-Driven**: Fires custom events at specific in-game hours using a high-performance `Signal` class.
- **Dynamic Events**: Add or remove custom time-based events at runtime. Changes on the Server are automatically replicated to all Clients.
- **Lifecycle Ready**: Integrates seamlessly with the [ModuleLoader](https://github.com/Distracted-Games/ModuleLoader) framework.
- **Integrated Logging**: Uses the included [Logger](https://github.com/Distracted-Games/Logger) utility for clear, toggleable debug output.

## Installation

The easiest way to install DayNightCycle is to grab the latest `.rbxm` release.

1. Download the `DayNightCycle.rbxm` file from the [Latest Release Page](https://github.com/Distracted-Games/ProDayNightCycle/releases/latest).
2. Drag and drop the `.rbxm` file into Roblox Studio.
3. Because this module must run on both the Client and the Server, it is highly recommended to place the contained `DayNightCycle` module into **ReplicatedStorage**.

## Configuration

The module's configuration can be modified in the `config` table at the top of the script. The default settings are:

```lua
local config: DayNightCycleConfig = {
    DayLengthInMinutes = 180, -- The duration of a full 24-hour game day in real-world minutes.
    StartTimeOfDay = nil,     -- A specific hour (0-24) to start at. `nil` uses the current `Lighting` time.
    TimeEvents = { -- A dictionary mapping event names to game hours.
        Dawn = 4.75, -- 4:45 AM
		Sunrise = 5.75, -- 5:45 AM
		Midday = 12.0, -- 12:00 PM
		Sunset = 17.6, -- 5:36 PM
		Dusk = 18.25, -- 6:15 PM
		Midnight = 0.0, -- 12:00 AM
    },
}
```

> ***Note**: The default event times were synched up with the default Roblox Lighting times for those actual events. If your lighting differs, you may have to adjust these default event times.*

## Usage

### Using the ModuleLoader
If you are using the [ModuleLoader](https://github.com/Distracted-Games/ModuleLoader) framework and have placed the module in `ReplicatedStorage/Source`, the loader will automatically call the `Start()` method on the Client. 

**Important Note:** If you placed the module in `ReplicatedStorage`, the ModuleLoader will not automatically start it on the Server. You must manually call `DayNightCycle.Start()` from your `ServerStart` script after all modules have finished their Setup phase:

```lua
-- Inside your ServerStart script:
local DayNightCycle = require(ReplicatedStorage.DayNightCycle)
DayNightCycle.Start()
```

Similarly, if you did not place the module in a `Source` folder within `ReplicatedStorage`, you will manually have to call `Start()` ont he client as well, similar to the standalone instructions below.

### Standalone Usage
If you are not using my `ModuleLoader` framework at all, you can start the cycle manually by calling `Start()` on both the Client and the Server. The Client will automatically request a time sync from the Server.

**Server Script:**
```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DayNightCycle = require(ReplicatedStorage.DayNightCycle)

DayNightCycle.Start()
```

**Local Script:**
```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DayNightCycle = require(ReplicatedStorage:WaitForChild("DayNightCycle"))

-- The client will ask the server for the current time and begin interpolating
DayNightCycle.Start() 
```

### Adding Custom Time Events dynamically
You can add or modify events at runtime. If called from the Server, the event will automatically replicate to all Clients.

```lua
DayNightCycle.AddTimeEvent("EveningRush", 17.5) -- Fires at 5:30 PM
```

### Listening for Events
The module utilizes a custom `Signal` class for high-performance event dispatching. You can connect to `DayNightCycle.TimeEvent` from any script.

**Example: A server script spawning monsters at night.**
```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DayNightCycle = require(ReplicatedStorage.DayNightCycle)

local function onTimeChanged(eventName: string, eventHour: number)
    if eventName == "Dusk" then
        print("The sun has set! Spawning night monsters...")
    elseif eventName == "Dawn" then
        print("The sun is rising! Despawning monsters...")
    end
end

-- Connect to the signal
DayNightCycle.TimeEvent:Connect(onTimeChanged)
```

## API Reference

| Method                        | Description                                                                 |
|-------------------------------|-----------------------------------------------------------------------------|
| `StartCycle()`                | Begins the day/night cycle. Called automatically if using `Start()`.        |
| `StopCycle()`                 | Stops the cycle and disconnects updates.                                    |
| `AddTimeEvent(name, hour)`    | Adds or updates a named time event. Replicates to clients if on the server. |
| `RemoveTimeEvent(name)` | Removes a named time event. Replicates to clients if on the server.         |
| `GetCurrentTime()`            | Returns the current in-game time (0–24) as a number. Slightly different than using Lighting.                        |
| `Start()`                     | Lifecycle method for ModuleLoader integration or initial sync.              |

### Public Properties
`DayNightCycle.TimeEvent: Signal`  
The signal that fires when a configured time is reached. It passes two arguments to connected callbacks: `eventName: string` and `eventHour: number`.

## Performance Notes
- Visual time interpolation is handled entirely on the Client via `RunService.Heartbeat`.
- The Server tracks logical time without polling or flooding network queues with `Lighting` property changes.
- Late-joining clients automatically request a sync, ensuring seamless time transitions for all players.

## Debugging
Verbose logging can be enabled by setting `Debug = true` in the Logger configuration inside the module. This will print detailed output regarding time progression, synchronization, and event triggers.
