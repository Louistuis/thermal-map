# Thermal Map

A live, thermal-camera style map of every temperature sensor inside a MacBook Air 13" (M3). Thermal Map reads all 205 SMC and HID temperature sensors once a second, pins each reading to the part it measures on a layout calibrated to Apple's repair manual, and solves the heat flow in between, so you can watch heat move from the M3 across the heat sink, the logic board and the battery in real time.

<!-- SCREENSHOT SLOT: docs/screenshot-internal.png (INTERNAL view, bottom side, ironbow) -->
![Thermal Map, internal view](docs/screenshot-internal.png)

<!-- VIDEO SLOT: link the demo MP4 attached to the latest release, or a GIF in docs/ -->

## Features

- **Every sensor.** All 167 SMC temperature keys (die, heat sink, PMU, regulators, NAND, battery, palm rests, Wi-Fi, display) plus 38 HID thermal services (PMU and PMU2 die sensors, NAND, battery gas gauge). Keys that never return a valid value are detected and skipped.
- **Heat-conduction model, not a blur.** A two-layer steady-state heat equation on a 2 mm grid. Each part has its own conductivity (aluminium heat sink, logic board, battery cells, trackpad), sensors are fixed at the spots they measure, and the solver fills in the rest. Heat runs along the heat sink and board instead of spreading in round blobs.
- **Bottom case view.** A second modelled layer for the outer aluminium shell, coupled to the internals and cooled by room air: roughly what an IR camera pointed at the underside would see.
- **Bottom and top views.** Look at the board from underneath (as with a thermal camera on the bottom case) or from the keyboard side.
- **Vector isotherms** traced with marching squares, with labelled major levels.
- **SoC die inset** showing the 80 on-die sensors across the P-cluster, E-cluster and GPU, with the core peak.
- **Palettes:** Ironbow, Rainbow HC, Arctic, White Hot. Auto range or fixed range.
- **Sensor table** with live, min and max for every key, filterable, and hover to highlight a sensor on the map.
- **Light on the Mac it measures:** about 7% of one core with the window open, about 5% when hidden (the map pauses when no window is visible).

<!-- SCREENSHOT SLOT: docs/screenshot-bottom-case.png (BOTTOM CASE view under load) -->
![Thermal Map, bottom case view](docs/screenshot-bottom-case.png)

## Download

1. Download **Thermal-Map.zip** from the [latest release](https://github.com/Louistuis/thermal-map/releases/latest).
2. Unzip it and move **Thermal Map.app** to your Applications folder.
3. The app is ad-hoc signed, not notarized (no paid Apple Developer ID), so the first launch is blocked by Gatekeeper. Either right-click the app, choose **Open**, then **Open** again, or run:

   ```bash
   xattr -dr com.apple.quarantine "/Applications/Thermal Map.app"
   ```

**Requirements**

- macOS 14 Sonoma or later, Apple silicon.
- The layout is built and calibrated for the **MacBook Air 13-inch M3 (Mac15,12)** only. On any other Mac the app still reads every sensor and the table is correct, but the map will show the wrong board. Layouts for other models are welcome as pull requests (see `Sources/Layout.swift`).
- No admin rights, no kernel extension, no helper tool. It only reads sensors.

## Setup: build from source

You need the Xcode Command Line Tools (full Xcode is not required):

```bash
xcode-select --install
```

Then:

```bash
git clone https://github.com/Louistuis/thermal-map.git
cd thermal-map
./build.sh
```

`build.sh` compiles `Sources/*.swift` with `swiftc`, generates the app icon, writes the `Info.plist`, ad-hoc signs the bundle and installs it to `/Applications`. To install somewhere else, set `DEST`:

```bash
DEST="$HOME/Applications" ./build.sh
```

The built bundle is also left at `build/Thermal Map.app`.

### Headless rendering

The binary can render without opening a window, which is how the screenshots and the demo video are made:

```bash
# one PNG after a few seconds of live data
"/Applications/Thermal Map.app/Contents/MacOS/ThermalMap" --render=out.png [--top] [--surface] [--labels]

# a PNG frame sequence of live data, with timed view switches
"/Applications/Thermal Map.app/Contents/MacOS/ThermalMap" --record=frames --seconds=60 --fps=2 --at=30:surface
```

`Tools/demo/record-demo.sh` records a run under a short all-core load, and `Tools/demo/make-demo.sh` turns the frames into the 16:9 and 4:5 demo videos (needs `ffmpeg`).

## How it works

- **SMC.** Talks to the `AppleSMC` user client directly (`IOConnectCallStructMethod`, the same interface tools like iStat use), enumerates all keys, keeps every `T*` key with a temperature type (`flt`, `sp78`, `fp88`, `ioft`) and reads them on a background queue.
- **HID.** Reads the thermal services exposed through the private `IOHIDEventSystemClient` API (usage page `0xff00`, usage 5). This is a private API, which is fine for an app distributed outside the Mac App Store.
- **Layout.** Part outlines (logic board, heat sink, M3, NAND, PMUs, regulators, battery cells, trackpad, speakers, ports) are calibrated to Apple's Self Service Repair manual for this exact model (J613), mirrored where needed, within roughly 3 to 5 mm. Each sensor is placed on the part it measures, using its key name and zone.
- **Solver.** Red-black successive over-relaxation on a 153 x 108 grid with two coupled layers (internals and bottom case). Sensors are Dirichlet pins, the room-air sensor sets the ambient, and each frame warm-starts from the previous solution, so only a few sweeps are needed at 5 frames per second. The result is resampled to a 1 mm grid, colorized and contoured.

### Honest limits

- Apple does not publish sensor coordinates. Which part a sensor measures is known from its key name; its exact spot within that part is inferred.
- The die inset places the on-die sensors on an even grid inside each cluster, not at their real silicon positions.
- Some key meanings are educated guesses (for example `TAOL`, `TVA0` and the `Tp` triples).
- The conductivities and the bottom-case coupling are tuned to plausible values (about 33 °C over the chip at idle), not measured with an IR camera. Treat the bottom case view as a model, not a measurement.

## Project layout

```
Sources/Sensors.swift     SMC and HID readers
Sources/Layout.swift      board geometry and the sensor placement map
Sources/HeatSolver.swift  two-layer heat-conduction solver
Sources/Model.swift       sampling, smoothing, field, isotherms, palettes
Sources/Views.swift       SwiftUI interface
Sources/Recorder.swift    headless frame recorder
Sources/main.swift        app entry, --render and --record
Tools/                    icon generator, layout calibration notes, demo video scripts
probe/                    the original sensor dumps from this Mac
```

## License

MIT. See [LICENSE](LICENSE).
