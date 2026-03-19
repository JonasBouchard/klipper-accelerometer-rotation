# Klipper Accelerometer Rotation

Standalone Klipper extra that adds an `[accelerometer_rotation]`
configuration section. It rotates accelerometer samples after Klipper's
built-in `axes_map`, so you can describe arbitrary mounting angles in
degrees without replacing any of Klipper's default accelerometer files.

## Supported accelerometers

The standalone extra patches configured accelerometer objects at runtime.
It works with Klipper accelerometers that expose the standard
`start_internal_client()` and `_convert_samples()` hooks, including:

- `[adxl345]`
- `[lis2dw]`
- `[lis3dh]`
- `[mpu9250]`
- `[icm20948]`
- `[bmi160]`

## What it adds

Keep using the normal accelerometer section for wiring and `axes_map`.
Add a separate rotation section with:

```ini
[accelerometer_rotation]
chip: <accelerometer section name>
axes_rotation: <x_degrees>, <y_degrees>, <z_degrees>
```

`chip:` is optional when exactly one accelerometer is configured.
The section name stays the same for every accelerometer model. `chip:`
selects the real Klipper accelerometer section, for example `adxl345`,
`lis2dw`, or `mpu9250 my_accel`.

Example:

```ini
[adxl345]
cs_pin: some_mcu:gpio1
axes_map: x, y, z

[accelerometer_rotation]
chip: adxl345
axes_rotation: 0, 0, 45
```

Rotations:

- are in degrees
- use the right-hand rule
- are applied in X, then Y, then Z order
- are applied after `axes_map`

If you have more than one accelerometer, either set `chip:` explicitly or
use additional generic rotation sections:

```ini
[mpu9250 my_accel]
i2c_mcu: rpi
i2c_bus: i2c.1
axes_map: x, y, z

[accelerometer_rotation toolhead]
chip: mpu9250 my_accel
axes_rotation: 0, -30, 0
```

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
2. Symlinks `accelerometer_rotation.py` from this repository into
   `klippy/extras`.
3. Optionally adds a Moonraker `update_manager` block.
4. Starts Klipper again.

## Uninstall

```bash
cd ~/klipper-accelerometer-rotation
./install.sh -u
```

This removes the standalone extra symlink and the Moonraker updater
block.

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

- This extension does not overwrite Klipper's built-in accelerometer
  modules. It only adds a new standalone extra.
- It is derived from Klipper code and distributed under GPLv3. See
  `COPYING`.
