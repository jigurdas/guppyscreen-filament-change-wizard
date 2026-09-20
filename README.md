# Guppy Screen Filament Change Wizard

A guarded filament-change wizard for **Guppy Screen + Klipper + Moonraker + Spoolman**. The bundled Klipper state machine is intended for the Creality Ender-3 V3 KE configuration it was developed against; it is not a drop-in universal M600 replacement.

## What changed in this release

This release fixes the source patch format, resets the wizard state when a print is cancelled, restores the saved nozzle temperature and fan speed when the wizard is cancelled, clears the LVGL progress-bar pointer after prompt cleanup, validates progress messages, avoids destructive failed updates, and removes the Moonraker Update Manager entry during uninstall.

## Intended workflow

The slicer remains responsible for inserting a pause. When the print is paused, the user taps **Filament Change** on Guppy Screen. The wizard then reheats to the saved print temperature, unloads the old filament, asks the user to remove it, opens the existing GuppyScreen Spoolman panel, waits for the replacement spool to be made active, loads and purges the new filament, and finally offers **Continue print**, **Back to macros**, and **Cancel print**.

`FILAMENT_CHANGE` must be started while the printer is already paused. It intentionally does not call `PAUSE`, does not use `M600`, and does not create a second pause. Only **Continue print** invokes `RESUME`; cancellation leaves the print paused, while **Cancel print** resets the wizard and invokes `CANCEL_PRINT`.

## Prerequisites and compatibility

The macros expect the printer configuration to expose a `PRINTER_PARAM` macro with a `hotend_temp` variable, as used by the Ender-3 V3 KE pause setup, and a standard Klipper `fan` object. The installer does not invent these objects. If the printer uses a different pause macro, fan section, extruder, or coordinate system, adapt and test the configuration before printing.

The unload/load distances are intentionally conservative defaults for the target printer and must be tested with the actual extruder and filament. Do not leave the printer unattended until the parking position, temperatures, fan recovery, and extrusion distances have been verified.

The UI patch targets GuppyScreen commit `07409cb031bbbfc57cd7817ba295e5385e3d5565`. It may require manual updates when upstream changes. The patch is now a plain, color-free Git patch and should pass `git apply --check` against that revision.

## One-command installation

SSH into the printer and run:

```sh
curl -fsSL https://raw.githubusercontent.com/jigurdas/guppyscreen-filament-change-wizard/main/install.sh | sh
```

The installer detects the Moonraker config path where possible, creates a timestamped backup, installs the Klipper macro, adds the GuppyScreen include only when it is missing, registers the repository with Moonraker Update Manager, reports whether a Spoolman section exists, and restarts Klipper and Moonraker. Updates are cloned into a temporary directory first so a failed network operation does not remove a working installation.

Backups are written under:

```text
/usr/data/printer_data/config/filament-change-backup-YYYYMMDD-HHMMSS-PID/
```

If a restart fails, do not continue printing. Restore the backed-up `printer.cfg`, `moonraker.conf`, and `GuppyScreen/filament-change.cfg`, then restart the affected service manually.

For a local checkout, use:

```sh
sudo sh install-klipper.sh /usr/data/printer_data/config
```

The local installer also creates a backup and prints its location. Restart Klipper only after reviewing the resulting configuration.

## UI build

The printer-side macro works without the custom UI patch and appears in GuppyScreen's macro list. The dedicated **Filament Change** button and Spoolman return flow require a patched GuppyScreen binary.

Build the pinned upstream revision:

```sh
git clone --recurse-submodules https://github.com/ballaswag/guppyscreen.git
git -C guppyscreen checkout 07409cb031bbbfc57cd7817ba295e5385e3d5565
git -C guppyscreen apply --check /path/to/guppyscreen-filament-change-wizard/ui/patches/0001-filament-change-wizard.patch
git -C guppyscreen apply /path/to/guppyscreen-filament-change-wizard/ui/patches/0001-filament-change-wizard.patch
cd guppyscreen
make -j2
```

Install the resulting binary using the upstream GuppyScreen installation procedure for the printer. Keep a copy of the previous binary so the UI can be rolled back independently of the Klipper macro.

## Uninstall and rollback

To remove the printer-side integration from a local checkout:

```sh
sudo sh uninstall-klipper.sh /usr/data/printer_data/config
```

The script backs up the files, removes `GuppyScreen/filament-change.cfg`, removes the exact `filament-change-wizard` Update Manager section, and removes the managed checkout. It intentionally leaves the shared `[include GuppyScreen/*.cfg]` line because other GuppyScreen configuration files may depend on it. Restart Klipper and Moonraker after reviewing the backup.

The UI patch is source-level; restore the previous GuppyScreen binary or rebuild the unpatched upstream revision to remove it.

## Safety checklist

Test first with a cold, unloaded printer and then with a short print. Confirm that the slicer pause parks the head safely. Confirm that the saved temperature comes from the active print, that the fan returns to its prior speed after cancel or resume, and that the extruder does not grind or over-purge. Confirm that **Cancel print** resets the wizard and that a later wizard can be started without a firmware restart.

The add-on does not modify Spoolman data directly. The active spool is selected through GuppyScreen's existing panel, while usage tracking remains Moonraker/Spoolman's responsibility.

## Development checks

Run the repository checks before committing:

```sh
sh -n install.sh install-klipper.sh uninstall-klipper.sh
git diff --check
git apply --check ui/patches/0001-filament-change-wizard.patch
```

The UI build also depends on the native toolchain and dependencies documented by upstream GuppyScreen.
