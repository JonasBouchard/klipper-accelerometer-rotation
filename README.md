# Klipper Accelerometer Rotation

Standalone Klipper extension that adds `axes_rotation` support to the
built-in accelerometer modules. It allows accelerometers mounted at
arbitrary angles to be described with rotations in degrees instead of
only axis swaps and sign flips.

## Supported Klipper sections

- `[adxl345]`
- `[lis2dw]`
- `[lis3dh]`
- `[mpu9250]`
- `[icm20948]`
- `[bmi160]`

The repository installs patched versions of these Klipper extras:

- `adxl345.py`
- `lis2dw.py`
- `mpu9250.py`
- `icm20948.py`
- `bmi160.py`

`[lis3dh]` is covered automatically because upstream `lis3dh.py`
delegates to `lis2dw.py`.

## What it adds

You can keep using `axes_map` for the coarse orientation and add:

```ini
axes_rotation: <x_degrees>, <y_degrees>, <z_degrees>
```

Example:

```ini
[adxl345]
cs_pin: some_mcu:gpio1
axes_map: x, y, z
axes_rotation: 0, 0, 45
```

Rotations:

- are in degrees
- use the right-hand rule
- are applied in X, then Y, then Z order
- are applied after `axes_map`

## Installation

Automatic install:

```bash
cd ~
git clone https://github.com/JonasBouchard/klipper-accelerometer-rotation.git
cd klipper-accelerometer-rotation
chmod +x install.sh
./install.sh
```

What the installer does:

1. Stops Klipper.
2. Backs up the original built-in accelerometer extras.
3. Symlinks the patched files from this repository into `klippy/extras`.
4. Optionally adds a Moonraker `update_manager` block.
5. Starts Klipper again.

## Uninstall

```bash
cd ~/klipper-accelerometer-rotation
./install.sh -u
```

This removes the symlinks, restores the original Klipper files from the
backup created during install, and removes the Moonraker updater block.

## Moonraker updater

The installer appends this updater section:

```ini
[update_manager accelerometer_rotation]
type: git_repo
path: /path/to/this/repo
origin: __SET_YOUR_GIT_REMOTE__
is_system_service: False
```

Replace `origin` with the real git remote if you want Moonraker updates
to work. The installer fills it automatically when the repository has a
configured `remote.origin.url`; otherwise it leaves the placeholder.

## Notes

- This extension overrides built-in Klipper modules, so reinstall it
  after a Klipper update if upstream overwrites those files.
- It is derived from Klipper code and distributed under GPLv3. See
  `COPYING`.
