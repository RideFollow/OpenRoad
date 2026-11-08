import 'dart:convert';
import 'dart:math' as math;

import 'package:xml/xml.dart';

class RoadPoint {
  const RoadPoint(this.latitude, this.longitude, this.elevationM);
  final double latitude;
  final double longitude;
  final double elevationM;
}

class RoutePosition {
  const RoutePosition({
    required this.point,
    required this.distanceKm,
    required this.gradePercent,
    required this.progress,
  });
  final RoadPoint point;
  final double distanceKm;
  final double gradePercent;
  final double progress;
}

class GpxRoute {
  GpxRoute._(this.points, this._cumulativeKm);

  final List<RoadPoint> points;
  final List<double> _cumulativeKm;
  double get distanceKm => _cumulativeKm.last;

  factory GpxRoute.parse(List<int> bytes) {
    final document = XmlDocument.parse(utf8.decode(bytes));
    final points = <RoadPoint>[];
    for (final node in document.descendants.whereType<XmlElement>()) {
      if (node.name.local != 'trkpt' && node.name.local != 'rtept') continue;
      final lat = double.tryParse(node.getAttribute('lat') ?? '');
      final lon = double.tryParse(node.getAttribute('lon') ?? '');
      if (lat == null || lon == null) continue;
      var elevation = 0.0;
      for (final child in node.childElements) {
        if (child.name.local == 'ele') {
          elevation = double.tryParse(child.innerText.trim()) ?? 0;
          break;
        }
      }
      points.add(RoadPoint(lat, lon, elevation));
    }
    if (points.length < 2) {
      throw const FormatException('GPX must contain at least two route points');
    }
    final cumulative = <double>[0];
    for (var i = 1; i < points.length; i++) {
      cumulative.add(cumulative.last + _haversineKm(points[i - 1], points[i]));
    }
    return GpxRoute._(List.unmodifiable(points), List.unmodifiable(cumulative));
  }

  RoutePosition at(double distanceKm) {
    final distance = distanceKm.clamp(0.0, this.distanceKm);
    var hi = _cumulativeKm.length - 1;
    var lo = 0;
    while (lo + 1 < hi) {
      final mid = (lo + hi) >> 1;
      if (_cumulativeKm[mid] <= distance) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final span = math.max(_cumulativeKm[hi] - _cumulativeKm[lo], 0.000001);
    final t = ((distance - _cumulativeKm[lo]) / span).clamp(0.0, 1.0);
    final a = points[lo];
    final b = points[hi];
    final point = RoadPoint(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
      a.elevationM + (b.elevationM - a.elevationM) * t,
    );
    // Smooth grade over roughly 50 m to avoid making the trainer chatter on
    // noisy consumer GPX elevation samples.
    final gradeStart = math.max(0.0, distance - 0.025);
    final gradeEnd = math.min(this.distanceKm, distance + 0.025);
    final start = _pointAtRaw(gradeStart);
    final end = _pointAtRaw(gradeEnd);
    final horizontalM = math.max((gradeEnd - gradeStart) * 1000, 1);
    final grade = ((end.elevationM - start.elevationM) / horizontalM * 100)
        .clamp(-20.0, 20.0);
    return RoutePosition(
      point: point,
      distanceKm: distance,
      gradePercent: grade,
      progress: this.distanceKm == 0 ? 0 : distance / this.distanceKm,
    );
  }

  RoadPoint _pointAtRaw(double distance) {
    var i = 1;
    while (i < _cumulativeKm.length && _cumulativeKm[i] < distance) {
      i++;
    }
    if (i >= points.length) return points.last;
    final span = math.max(_cumulativeKm[i] - _cumulativeKm[i - 1], 0.000001);
    final t = ((distance - _cumulativeKm[i - 1]) / span).clamp(0.0, 1.0);
    final a = points[i - 1];
    final b = points[i];
    return RoadPoint(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
      a.elevationM + (b.elevationM - a.elevationM) * t,
    );
  }

  static double _haversineKm(RoadPoint a, RoadPoint b) {
    const radiusKm = 6371.0088;
    double rad(double v) => v * math.pi / 180;
    final dLat = rad(b.latitude - a.latitude);
    final dLon = rad(b.longitude - a.longitude);
    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(a.latitude)) *
            math.cos(rad(b.latitude)) *
            math.pow(math.sin(dLon / 2), 2);
    return radiusKm * 2 * math.asin(math.sqrt(h));
  }
}
