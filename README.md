# Guppy Screen Filament Change Wizard

A step-by-step filament-change wizard for **Guppy Screen + Klipper + Moonraker + Spoolman**, built and tested on a Creality Ender-3 V3 KE. Everything runs from one macro, `FILAMENT_CHANGE`, and is shown as Klipper `action:prompt` dialogs, so it works on Guppy Screen, Fluidd and Mainsail without a patched UI.

## What changed in this release

- **Works from the macro list in any state.** While printing it offers to pause first; while paused it changes filament and resumes; while idle it asks for the filament temperature and just swaps the filament.
- **Live heating progress.** Heating runs on a timer instead of a blocking `M109`, so the dialog shows `Nozzle 150C / 210C [=============.......] 67%` and **Cancel** works while the nozzle heats.
- **Spoolman spool picker inside the wizard.** A small Klipper module (`fc_spoolman.py`) lists your spools through Moonraker's Spoolman proxy, three per page with a **More** button, the active spool first. Picking one makes it active in Spoolman.
- **Step headers and progress** for unloading and loading (`Step 1/4 - Unloading ... 66%`).
- **Fixed:** the wizard failed on printers without a `[fan]` section (the KE uses `output_pin fan0`); every dialog now starts with `prompt_end`, because Guppy Screen otherwise keeps the previous dialog's buttons; a stale **Cancel** pressed during a move no longer closes the next step; running `FILAMENT_CHANGE` again returns to the current step.

## Workflow

1. Run **FILAMENT_CHANGE** from the Guppy Screen or Fluidd macro list.
2. **Step 1/4** heats the nozzle and unloads the old filament.
3. **Step 2/4** asks you to pull back the extruder lever and remove the filament; the nozzle waits at 140C.
4. **Step 3/4** shows your Spoolman spools (or **Skip**), then asks you to insert the new filament.
5. **Step 4/4** heats again, loads and purges.
6. The last dialog offers **Purge more**, then **Continue** / **Keep paused** / **Cancel print** for a paused print, or **Done** (heater off) when no print is running.

Only **Continue** invokes `RESUME`. **Keep paused** and **Cancel** leave a paused print paused at its print temperature; **Cancel print** resets the wizard and runs `CANCEL_PRINT`.

## Prerequisites and compatibility

- A `PRINTER_PARAM` macro with a `hotend_temp` variable and a `PAUSE` macro that stores the print temperature there, as in the Ender-3 V3 KE stock configuration.
- The part-cooling fan as `[output_pin fan0]` (KE/K1 style).
- Moonraker with a `[spoolman]` section and the `SET_ACTIVE_SPOOL` macro from the Moonraker Spoolman docs. Without Spoolman the picker says so and **Skip** continues.
- Klipper's `[respond]` and `[pause_resume]`.

The unload/load distances are conservative defaults for the KE extruder. Test with your own extruder and filament before leaving a print unattended.

## One-command installation

SSH into the printer and run:

```sh
git clone --depth=1 https://github.com/jigurdas/guppyscreen-filament-change-wizard.git /tmp/fcw && sh /tmp/fcw/install.sh
```

(The busybox `curl` on Creality firmware has no TLS support, so `curl ... | sh` does not work there; `git` does.)

The installer creates a timestamped backup, installs `fc_spoolman.py` into `klippy/extras` and the macros into `GuppyScreen/filament-change.cfg`, adds the GuppyScreen include only when it is missing, registers the repository with Moonraker Update Manager, and restarts the Klipper and Moonraker services. Klipper's extras folder is found automatically (`/usr/share/klipper/klippy/extras` on Creality firmware, `~/klipper/klippy/extras` on KIAUH installs); set `KLIPPER_EXTRAS=/path/to/klippy/extras` to override.

Backups are written under:

```text
/usr/data/printer_data/config/filament-change-backup-YYYYMMDD-HHMMSS-PID/
```

For a local checkout, use:

```sh
sudo sh install-klipper.sh /usr/data/printer_data/config
```

Then restart the **Klipper service** (`/etc/init.d/S55klipper_service restart` on Creality firmware). A `RESTART` or `FIRMWARE_RESTART` command reloads the configuration but not new Python modules. If Klipper then reports that the MCU is shut down, run `FIRMWARE_RESTART` once.

A Creality firmware update replaces `klippy/extras` and removes `fc_spoolman.py`. Run the installer again afterwards, or Klipper stops with an unknown `[fc_spoolman]` section.

## Optional UI patch

`ui/patches/0001-filament-change-wizard.patch` adds a dedicated **Filament Change** button to Guppy Screen. It targets GuppyScreen commit `07409cb031bbbfc57cd7817ba295e5385e3d5565` and is no longer needed: the wizard works from the macro list, and the spool picker replaces the patch's Spoolman panel hand-off.

```sh
git clone --recurse-submodules https://github.com/ballaswag/guppyscreen.git
git -C guppyscreen checkout 07409cb031bbbfc57cd7817ba295e5385e3d5565
git -C guppyscreen apply /path/to/guppyscreen-filament-change-wizard/ui/patches/0001-filament-change-wizard.patch
cd guppyscreen
make -j2
```

## Uninstall and rollback

```sh
sudo sh uninstall-klipper.sh /usr/data/printer_data/config
```

The script backs up and removes `GuppyScreen/filament-change.cfg` and `fc_spoolman.py`, removes the `filament-change-wizard` Update Manager section and the managed checkout. It leaves the shared `[include GuppyScreen/*.cfg]` line because other GuppyScreen files may depend on it. Restart the Klipper and Moonraker services afterwards.

## Safety checklist

Test first with a cold, unloaded printer and then with a short print. Confirm that the pause parks the head safely, that the print temperature is restored, that the fan returns to its prior speed after cancel or resume, and that the extruder does not grind or over-purge.

## Development checks

```sh
./tests/validate.sh
```
