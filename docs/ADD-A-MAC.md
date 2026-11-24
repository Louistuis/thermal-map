# Add your Mac to Thermal Map

Thermal Map was built for one machine, the 13-inch MacBook Air with M3 (`Mac15,12`). Its sensors are read on any Apple silicon Mac, but the map, the sensor positions and the heat-model constants belong to that board. This guide is everything you need to add another Mac yourself: where the data comes from, how the code is laid out, and how to prove your layout is right.

You need an Apple silicon Mac (the one you are adding), the Xcode Command Line Tools (`xcode-select --install`), and a few evenings. No Xcode project, no paid developer account.

## How the app works, in one minute

1. **Read.** `Sources/Sensors.swift` opens the AppleSMC user client and lists every key whose name starts with `T` and has a temperature type (`flt`, `sp78`, `fp88`, `ioft`). It also asks the private `IOHIDEventSystemClient` API for thermal services (PMU dies, NAND, battery gas gauge). On the M3 Air that is 167 SMC keys and 38 HID services.
2. **Place.** `Sources/MacModel.swift` decides where each sensor sits, in millimetres, using the active model's table in `Sources/Models/` first and family rules by key prefix second.
3. **Solve.** `Sources/HeatSolver.swift` pins every placed reading to its spot on a 2 mm grid and solves two-layer heat conduction between them: the internal layer (board, heat sink, battery, trackpad on the top case) and the bottom case. Each part has its own conductance, so heat runs along the heat sink and barely into the battery.
4. **Check.** `Sources/Calibrate.swift` hides passive sensors from the model, predicts them, and fits the constants to minimise that error. That number is how you know a layout is good.

## Coordinates

Everything is in millimetres, **seen from above** (keyboard side, as if the top case were glass):

- origin at the **hinge, left** corner of the laptop
- x runs to the right, across the hinge, up to the chassis width
- y runs from the hinge (0) to the front lip (the chassis depth)

The bottom view in the app is the same data mirrored, so do not mirror anything yourself. If your source photo shows the underside (most teardown photos do), flip it left to right before measuring.

## Step 1: identify your Mac

```bash
sysctl -n hw.model
```

This prints the model identifier (for example `Mac15,12`). That string goes in `identifiers` and is how the app picks your layout. Note the marketing name and chip too. Apple's [Identify your MacBook Air](https://support.apple.com/en-us/102869) and [Identify your MacBook Pro](https://support.apple.com/en-us/108052) pages map identifiers to names.

## Step 2: dump your sensors

Build and run the dump:

```bash
./build.sh                     # builds and installs to /Applications (DEST=/some/dir ./build.sh to install elsewhere)
"/Applications/Thermal Map.app/Contents/MacOS/ThermalMap" --dump > my-mac-sensors.tsv
```

You get one line per sensor: source, key, type, live value, the zone and position the current layout gives it, and whether it feeds the map. On a Mac without a layout, the positions are the M3 Air's, which is exactly what you are about to replace. Keep this file; it goes in your pull request.

## Step 3: work out what each key measures

Apple does not document SMC keys. These prefixes held on the M3 Air and are common across Apple silicon, but check them on your machine:

| Prefix | What it is (M3 Air) | How it is placed |
|---|---|---|
| `Tp…` | P-core cluster die sensors | die inset only, P block |
| `Te…` | E-core cluster die sensors | die inset only, E block |
| `Tg…` | GPU die sensors | die inset only, GPU block |
| `TC…` | CPU summary values | listed, not mapped |
| `Ts0…`, `Ts1…` (most) | SoC package ring | ring around the die (`packageRadius`) |
| `Ts0P`, `Ts1P` | palm rests, left and right | your table |
| `Th…` | heat sink | your table |
| `TPD0-7`, `TPDX`, `TPMP` | main PMU die and proximity | ring around `anchors.pmu` |
| `TRD0-7`, `TRDX`, `TR0Z` | second PMU (PMU2) | ring around `anchors.pmu2` |
| `TB0T-TB2T`, `TG0B-TG2B` | battery cells | your table |
| `TG0C`, `TG0H`, `TG0V` | battery gas gauge | your table |
| `TH0T`, `TH0x` | NAND flash | your table |
| `TW0P` | Wi-Fi / Bluetooth module | your table |
| `TCHP`, `TPSP`, `TIOP`, `T5SP` | charger, power supply, I/O, 5 V supply | your table |
| `TVD0`, `TVS*`, `TVs1`, `TR2d`… | voltage regulators | your table |
| `TDBP`, `TDeL` | display / backlight (at the hinge) | your table |
| `TAOL` | ambient near the hinge, used as room air | your table, not pinned |

To identify an unknown key, **make one part warm and see which keys move**. Take a `--dump` before and after:

- **CPU load** (all cores): `for i in $(seq 8); do yes > /dev/null & done; sleep 60; killall yes`. Die, package and heat-sink keys rise first, then the regulators.
- **Charging** from a low battery: charger and battery keys rise.
- **A big file copy** to the internal SSD: NAND and storage keys rise.
- **A fast Wi-Fi download**: the Wi-Fi module key rises.

A key that rises with a part but lags it and moves less is probably *near* it, not on it.

## Step 4: map the board

You need the outlines of the parts that matter for heat: logic board, heat sink (or heat pipes and fans), SoC package, PMUs and regulators, NAND, battery cells, trackpad, speakers, and the ports.

Good sources, best first:

1. **Apple's Self Service Repair manual** for your exact model ([support.apple.com/self-service-repair](https://support.apple.com/self-service-repair), manuals list). The logic board, heat sink and battery photos show parts at a known scale, and the screw callouts pin the positions.
2. **iFixit teardowns** of your model, for close-up board photos with the chips identified.
3. Apple's **tech specs** page for the chassis width and depth, your scale reference.

To measure: put a photo in any image editor, rotate it square, mirror it if it shows the underside, and work out millimetres per pixel from the chassis width. Then read each part's rectangle (x, y, width, height) off the photo. `Tools/calibrate_layout.py` holds the measurements made for the M3 Air as a worked example. Within 3 to 5 mm is good.

## Step 5: write your model file

1. Copy `Sources/Models/MacBookAir13M3.swift` to `Sources/Models/<YourMac>.swift` and rename the static (for example `static let macBookPro14M4Pro`).
2. Fill in:
   - `name`, `shortName`, `identifiers` (from step 1), `chip`
   - `width`, `depth`, `corner` (chassis, mm), `dieCenter` (SoC die centre)
   - `parts`: every outline from step 4. `kind` sets the material: `.sink` conducts best, then `.chip`, `.board`, `.module`; `.battery` and `.trackpad` conduct poorly; `.port` is drawn only.
   - `dieBlocks`: the SoC floorplan in a unit square for the sidebar inset. Use a labelled die shot of your chip if one exists, and say in a comment where it came from.
   - `feet`: rubber feet positions, drawn on the bottom view.
   - `anchors`: PMU, PMU2, NAND, battery sites, gauge, and the package ring radius.
   - `sensors`: one line per key you placed in step 3, as `"KEY": ("Zone label", CGPoint(x:, y:), influenceRadius)`.
   - `params`: start from `HeatSolver.Params()` (physical defaults) and fit them in step 6.
3. Add your model to `MacModel.all` in `Sources/MacModel.swift`.
4. Look at it without opening a window:

   ```bash
   ./build.sh
   APP="/Applications/Thermal Map.app/Contents/MacOS/ThermalMap"
   "$APP" --render=internal.png --labels      # every SMC key labelled at its spot
   "$APP" --render=case.png --surface         # modelled bottom case
   "$APP" --render=top.png --top
   ```

## Step 6: prove it, then fit it

Save three snapshots of real readings: idle, under load, and cooling down.

```bash
mkdir -p calib/<your-mac>
"$APP" --snapshot=calib/<your-mac>/idle.json
for i in $(seq 8); do yes > /dev/null & done; sleep 70
"$APP" --snapshot=calib/<your-mac>/load.json
killall yes; sleep 45
"$APP" --snapshot=calib/<your-mac>/cooling.json
S=calib/<your-mac>/idle.json,calib/<your-mac>/load.json,calib/<your-mac>/cooling.json
```

Then:

- **`"$APP" --score=$S`** hides each group of passive sensors (heat sink, battery, gas gauge, palm rests), solves without them, and prints the error between the model and what they really read. `TM_V=1` prints every sensor.
- **Placement experiments:** `TM_MOVE="Th08:-10:0,Th09:-10:0" "$APP" --score=$S` shifts those sensors by (dx, dy) mm before scoring. If the error drops a lot, the sensor really sits there. This is how the M3 Air's heat-sink sensors were found 15 to 27 mm from the die, not at the far end of the heat sink as first guessed.
- **`"$APP" --fit=$S`** fits the internal conductances and losses by coordinate descent, within 4x of the physical defaults, and prints the constants. Copy them into your model's `params`. If a constant ends on that 4x limit, a sensor is probably misplaced; fix that first.

For reference, the M3 Air went from 5.8 to 1.8 °C RMS (4.7 to 1.5 °C mean) on held-out sensors.

The bottom case has no sensor of its own, so it cannot be fitted this way. Keep `gSink`, `gBase`, `hCase` and `kCase` physical unless you can measure the case with an IR camera or a thermocouple, and say so if you do.

### Macs with fans

MacBook Pros have heat pipes and fans. The current solver has no forced airflow, so a fan-cooled model will probably need a higher heat loss over the heat sink while the fans spin (for example scaling the sink's loss with fan speed from the `F0Ac`/`F1Ac` keys). That is open work and very welcome.

## Step 7: open a pull request

Include:

- `Sources/Models/<YourMac>.swift` and the `MacModel.all` entry
- `my-mac-sensors.tsv` from step 2 (in `calib/<your-mac>/`)
- the three snapshots, and the `--score` numbers before and after fitting
- the three renders from step 5
- your sources for the board outlines (manual pages, teardown links)

Keep each pull request to one Mac. If a key's meaning is a guess, say so in a comment next to it. Honest uncertainty is more useful than a confident wrong label.

## Building it with Claude

Thermal Map was built with [Claude Code](https://claude.com/claude-code) using **Claude Opus 5.5 at high effort**: the SMC and HID readers, the board calibration from Apple's repair manual, the heat solver, the accuracy test and this guide. You can add your Mac the same way. Open this repository in Claude Code and start with something like:

> Read docs/ADD-A-MAC.md and the code it points to. My Mac is `<sysctl hw.model output>`, a `<marketing name>`. Run `--dump`, help me identify the keys with load tests, map the board from Apple's Self Service Repair manual for this model, write `Sources/Models/<YourMac>.swift`, then take idle, load and cooling snapshots and use `--score` and `--fit` until the held-out error is as low as we can honestly get it. Check every render headlessly, never put windows on screen.

Check what it produces against the real readings. The `--score` numbers are the ground truth, not how good the map looks.

Questions and half-finished layouts are welcome as issues too.
