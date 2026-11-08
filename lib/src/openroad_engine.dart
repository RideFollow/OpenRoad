import 'dart:math' as math;

import 'ftms.dart';
import 'gpx_route.dart';

/// Physical inputs used by OpenRoad to translate trainer power into movement.
///
/// Defaults model a typical road-bike rider and can be overridden by the host
/// app. Keeping these values explicit makes a simulated ride reproducible.
class OpenRoadParameters {
  const OpenRoadParameters({
    this.riderWeightKg = 75,
    this.bikeWeightKg = 9,
    this.dragAreaM2 = 0.32,
    this.rollingResistance = 0.004,
    this.drivetrainEfficiency = 0.97,
    this.airDensityKgM3 = 1.225,
    this.windSpeedMps = 0,
  })  : assert(riderWeightKg > 0),
        assert(bikeWeightKg > 0),
        assert(dragAreaM2 > 0),
        assert(rollingResistance >= 0),
        assert(drivetrainEfficiency > 0 && drivetrainEfficiency <= 1),
        assert(airDensityKgM3 > 0);

  final double riderWeightKg;
  final double bikeWeightKg;

  /// Effective frontal area multiplied by drag coefficient (CdA).
  final double dragAreaM2;
  final double rollingResistance;
  final double drivetrainEfficiency;
  final double airDensityKgM3;

  /// Positive values are headwind; negative values are tailwind.
  final double windSpeedMps;

  double get totalWeightKg => riderWeightKg + bikeWeightKg;

  /// FTMS represents the wind coefficient in kg/m with a 0.01 resolution.
  double get ftmsWindResistanceKgM => 0.5 * airDensityKgM3 * dragAreaM2;
}

class OpenRoadFrame {
  const OpenRoadFrame({
    required this.position,
    required this.virtualSpeedKmh,
    required this.trainerSpeedKmh,
    required this.powerWatts,
    required this.cadenceRpm,
    required this.heartRateBpm,
    required this.resistanceLevel,
  });

  final RoutePosition position;
  final double virtualSpeedKmh;
  final double? trainerSpeedKmh;
  final int powerWatts;
  final double? cadenceRpm;
  final int? heartRateBpm;
  final double? resistanceLevel;
}

/// Pure, platform-independent GPX + cycling-physics engine.
///
/// Bluetooth belongs to the adapter/controller. This class can also be used by
/// tests, desktop bridges, recorded FIT replays, or a future ANT+ adapter.
class OpenRoadEngine {
  OpenRoadEngine(
      {required this.route, this.parameters = const OpenRoadParameters()});

  final GpxRoute route;
  final OpenRoadParameters parameters;

  double _distanceKm = 0;
  double _speedMps = 0;

  double get distanceKm => _distanceKm;
  double get virtualSpeedKmh => _speedMps * 3.6;
  RoutePosition get position => route.at(_distanceKm);
  bool get finished => _distanceKm >= route.distanceKm;

  OpenRoadFrame advance(FtmsBikeData trainer, Duration elapsed) {
    final seconds = elapsed.inMicroseconds.clamp(0, 3000000) / 1000000;
    final power = math.max(trainer.powerWatts ?? 0, 0);

    if (seconds > 0) {
      if (trainer.powerWatts == null) {
        // A read-only FTMS implementation may omit power. Its reported speed
        // remains a useful standards-based fallback.
        _speedMps = math.max((trainer.speedKmh ?? 0) / 3.6, 0);
      } else {
        _integratePower(power.toDouble(), seconds);
      }
      _distanceKm = math.min(
        _distanceKm + _speedMps * seconds / 1000,
        route.distanceKm,
      );
    }

    return OpenRoadFrame(
      position: position,
      virtualSpeedKmh: virtualSpeedKmh,
      trainerSpeedKmh: trainer.speedKmh,
      powerWatts: power,
      cadenceRpm: trainer.cadenceRpm,
      heartRateBpm: trainer.heartRateBpm,
      resistanceLevel: trainer.resistanceLevel,
    );
  }

  void _integratePower(double powerWatts, double seconds) {
    const gravity = 9.80665;
    final p = parameters;
    final mass = p.totalWeightKg;
    final grade = position.gradePercent / 100;
    final slopeAngle = math.atan(grade);
    final relativeAir = _speedMps + p.windSpeedMps;
    final aeroForce =
        0.5 * p.airDensityKgM3 * p.dragAreaM2 * relativeAir.abs() * relativeAir;
    final rollingForce =
        mass * gravity * p.rollingResistance * math.cos(slopeAngle);
    final gravityForce = mass * gravity * math.sin(slopeAngle);

    // At walking speed, use a finite effective speed so starting from rest
    // does not create an infinite drive force.
    final effectiveSpeed = math.max(_speedMps, 2.0);
    final driveForce = powerWatts * p.drivetrainEfficiency / effectiveSpeed;
    final acceleration =
        ((driveForce - aeroForce - rollingForce - gravityForce) / mass)
            .clamp(-4.0, 3.0);
    _speedMps = math.max(0, _speedMps + acceleration * seconds);
  }
}
