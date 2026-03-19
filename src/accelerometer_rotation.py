import logging
import math


def _matrix_multiply(left, right):
    return tuple([
        tuple([
            sum([left[row][idx] * right[idx][col] for idx in range(3)])
            for col in range(3)])
        for row in range(3)])


def _build_rotation_transform(axes_rotation):
    x_angle, y_angle, z_angle = [
        math.radians(angle) for angle in axes_rotation]
    sin_x, sin_y, sin_z = math.sin(x_angle), math.sin(y_angle), math.sin(z_angle)
    cos_x, cos_y, cos_z = math.cos(x_angle), math.cos(y_angle), math.cos(z_angle)
    rot_x = (
        (1., 0., 0.),
        (0., cos_x, -sin_x),
        (0., sin_x, cos_x))
    rot_y = (
        (cos_y, 0., sin_y),
        (0., 1., 0.),
        (-sin_y, 0., cos_y))
    rot_z = (
        (cos_z, -sin_z, 0.),
        (sin_z, cos_z, 0.),
        (0., 0., 1.))
    return _matrix_multiply(rot_z, _matrix_multiply(rot_y, rot_x))


def _apply_rotation(raw_xyz, axes_transform):
    return tuple([
        round(sum([
            axis_value * coeff for axis_value, coeff in zip(raw_xyz, axis_coeffs)
        ]), 6)
        for axis_coeffs in axes_transform])


def _is_accelerometer(obj):
    return hasattr(obj, 'start_internal_client') and hasattr(obj, '_convert_samples')


class AccelerometerRotation:
    def __init__(self, config):
        self.printer = config.get_printer()
        self.section_name = config.get_name()
        self.axes_rotation = tuple(config.getfloatlist('axes_rotation', count=3))
        self.rotation_transform = _build_rotation_transform(self.axes_rotation)
        option_chip_name = config.get('chip', None)
        if option_chip_name is not None:
            option_chip_name = option_chip_name.strip() or None
        self.chip_name = option_chip_name
        self.printer.register_event_handler("klippy:connect", self._handle_connect)

    def _find_accelerometer_names(self):
        return [
            name for name, obj in self.printer.lookup_objects()
            if _is_accelerometer(obj)]

    def _resolve_chip_name(self):
        if self.chip_name is not None:
            return self.chip_name
        accelerometers = self._find_accelerometer_names()
        if not accelerometers:
            raise self.printer.config_error(
                "Section '%s' could not find any configured accelerometer"
                % (self.section_name,))
        if len(accelerometers) > 1:
            raise self.printer.config_error(
                "Option 'chip' in section '%s' must be specified when multiple "
                "accelerometers are configured: %s"
                % (self.section_name, ', '.join(accelerometers)))
        return accelerometers[0]

    def _handle_connect(self):
        chip_name = self._resolve_chip_name()
        chip = self.printer.lookup_object(chip_name, None)
        if chip is None:
            raise self.printer.config_error(
                "Accelerometer '%s' in section '%s' was not found"
                % (chip_name, self.section_name))
        if not _is_accelerometer(chip):
            raise self.printer.config_error(
                "'%s' in section '%s' is not a supported accelerometer"
                % (chip_name, self.section_name))
        existing_owner = getattr(chip, '_accelerometer_rotation_section', None)
        if existing_owner is not None:
            raise self.printer.config_error(
                "Accelerometer '%s' already has rotation configured by section '%s'"
                % (chip_name, existing_owner))

        original_convert_samples = chip._convert_samples
        rotation_transform = self.rotation_transform

        def rotated_convert_samples(samples):
            original_convert_samples(samples)
            for index, sample in enumerate(samples):
                sample_time, accel_x, accel_y, accel_z = sample
                rotated_xyz = _apply_rotation(
                    (accel_x, accel_y, accel_z), rotation_transform)
                samples[index] = (sample_time,) + rotated_xyz

        chip._convert_samples = rotated_convert_samples
        chip._accelerometer_rotation_section = self.section_name
        logging.info(
            "Applied accelerometer rotation %s to '%s' from section '%s'",
            self.axes_rotation, chip_name, self.section_name)


def load_config(config):
    return AccelerometerRotation(config)


def load_config_prefix(config):
    return AccelerometerRotation(config)
