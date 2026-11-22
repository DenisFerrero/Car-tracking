#include "track_filter.h"
#include <math.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

using namespace proto;

namespace {

// Meters of one unit (1e-5 degrees) of latitude
const double METERS_PER_UNIT = 1.1132;

struct Vector {
  double x, y;
};

// Local planar coordinates in meters, relative to the origin point
Vector project(const Point &origin, const Point &point) {
  double cosLat = cos(origin.lat * 1e-5 * M_PI / 180.0);
  return {(point.lon - origin.lon) * METERS_PER_UNIT * cosLat, (point.lat - origin.lat) * METERS_PER_UNIT};
}

// Distance of p from the segment a-b (a is the origin)
double segmentDistance(Vector b, Vector p) {
  double length2 = b.x * b.x + b.y * b.y;
  // Degenerate segment, back to the starting point: distance from the start
  if (length2 < 1.0) return sqrt(p.x * p.x + p.y * p.y);

  double t = (p.x * b.x + p.y * b.y) / length2;
  if (t < 0) t = 0;
  if (t > 1) t = 1;
  double dx = p.x - t * b.x;
  double dy = p.y - t * b.y;
  return sqrt(dx * dx + dy * dy);
}

}  // namespace

double pointDistance(const Point &a, const Point &b) {
  Vector v = project(a, b);
  return sqrt(v.x * v.x + v.y * v.y);
}

TrackFilter::TrackFilter(const TrackFilterConfig &filterConfig) : config(filterConfig) {
  reset();
}

void TrackFilter::reset() {
  hasAnchor = false;
  windowSize = 0;
}

void TrackFilter::setAnchor(const Point &point) {
  anchor = point;
  hasAnchor = true;
  windowSize = 0;
}

bool TrackFilter::deviates(const Point &end) const {
  Vector b = project(anchor, end);
  for (size_t i = 0; i < windowSize; i++) {
    if (segmentDistance(b, project(anchor, window[i])) > config.toleranceMeters) return true;
  }
  return false;
}

bool TrackFilter::push(const Point &point, Point &out) {
  if (!hasAnchor) {
    setAnchor(point);
    out = point;
    return true;
  }
  // The encoder needs points in chronological order
  if (point.timestamp <= anchor.timestamp) return false;

  uint32_t elapsed = point.timestamp - anchor.timestamp;

  // Standing still: GPS noise around the anchor is not a movement
  if (windowSize == 0 && pointDistance(anchor, point) < config.minDistanceMeters) {
    if (elapsed < config.stationaryIntervalSec) return false;
    setAnchor(point);
    out = point;
    return true;
  }

  // The route left the straight line: the last sample before the deviation is a vertex
  if (windowSize > 0 && deviates(point)) {
    Point vertex = window[windowSize - 1];
    setAnchor(vertex);
    window[windowSize++] = point;
    out = vertex;
    return true;
  }

  // Straight line, but the position must stay fresh
  if (elapsed >= config.maxIntervalSec || windowSize == WINDOW) {
    setAnchor(point);
    out = point;
    return true;
  }

  window[windowSize++] = point;
  return false;
}

bool TrackFilter::flush(Point &out) {
  if (windowSize == 0) return false;
  out = window[windowSize - 1];
  setAnchor(out);
  return true;
}
