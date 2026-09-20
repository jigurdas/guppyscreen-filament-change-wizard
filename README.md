# Guppy Screen Filament Change Wizard

A modular filament-change wizard for **Guppy Screen + Klipper + Moonraker + Spoolman** on the Creality Ender-3 V3 KE.

The project is split into two parts:

- `klipper/filament-change.cfg` — the printer-side state machine. It uses the existing slicer pause and never creates a second pause.
- `ui/patches/0001-filament-change-wizard.patch` — the Guppy Screen UI extension. It adds a `Filament Change` button, opens Spoolman from the wizard, returns to the wizard after spool selection, and renders progress updates.

## Intended workflow

The slicer remains responsible for inserting pauses at layer changes. When the print is paused, the user taps **Filament Change** on Guppy Screen.

The wizard then:

1. Saves the print temperature and fan state.
2. Heats the nozzle to the saved print temperature.
3. Unloads the old filament.
4. Displays an instruction to pull the extruder lever and remove the filament.
5. Opens the existing Guppy Screen Spoolman panel.
6. Lets the user select and activate the replacement spool.
7. Returns to the wizard.
8. Heats back to the saved print temperature, loads and purges the new filament.
9. Shows a real loading progress bar.
10. Offers **Continue print**, **Back to macros**, and **Cancel print**.

## Important behavior

`FILAMENT_CHANGE` must be started while the printer is already paused by the slicer's pause command. It intentionally does not call `PAUSE`.

The add-on does not use `M600`.

The active spool is changed using Guppy Screen's existing Spoolman panel. Spoolman usage tracking remains Moonraker's responsibility.

## Printer configuration

## One-command installation

On the Ender-3 V3 KE, SSH into the printer and run:

```sh
curl -fsSL https://raw.githubusercontent.com/jigurdas/guppyscreen-filament-change-wizard/main/install.sh | sh
```

The installer detects the Moonraker config path, creates a timestamped backup, installs the Klipper module, adds the GuppyScreen include only when it is missing, checks Spoolman, and restarts Klipper. It does not overwrite the existing printer configuration apart from adding the missing include line.

The supplied configuration already has:

```ini
[spoolman]
server: http://192.168.0.100:7912
sync_rate: 5
```

and:

```ini
[include GuppyScreen/*.cfg]
```

Therefore copy `klipper/filament-change.cfg` to:

```text
/usr/data/printer_data/config/GuppyScreen/filament-change.cfg
```

Do not add a second `[include GuppyScreen/*.cfg]` line.

After copying the file, restart Klipper. The macro will appear in Guppy's macro list as `FILAMENT_CHANGE` even before the custom UI patch is installed.

## Guppy Screen UI build

The current Guppy Screen release does not load arbitrary native panels as runtime plugins. The UI part is consequently kept as a small source patch against the upstream Guppy Screen tree.

Apply the patch to the matching Guppy Screen source revision:

```sh
git clone --recurse-submodules https://github.com/ballaswag/guppyscreen.git
git -C guppyscreen apply ui/patches/0001-filament-change-wizard.patch
```

Build and package the resulting Guppy Screen binary using the upstream release workflow. The patch is deliberately isolated to:

- `PromptPanel`: `prompt_spoolman` and `prompt_progress` actions;
- `SpoolmanPanel`: return callback to the active prompt;
- `MainPanel`: dedicated `Filament Change` button.

## Existing configuration note

The supplied printer configuration contains an older `M600` implementation in both `gcode_macro.cfg` and `Helper-Script/M600-support.cfg`. This add-on does not call `M600`, but those duplicate definitions should be cleaned up separately before installing the add-on if Klipper reports duplicate-section errors.

## Safety

Test first with a cold, unloaded printer and then with a short print. Verify the unload distance and the parking coordinates before leaving the machine unattended. The wizard keeps the printer paused when **Back to macros** or **Cancel** is selected; only **Continue print** invokes `RESUME`.
