#ifndef TRACK_FILTER_H
#define TRACK_FILTER_H

// Adaptive sampling: the GPS is sampled at a fixed interval, but only the points needed
// to redraw the route are recorded. Straight roads cost a point every maxIntervalSec,
// curves and turns keep every sample.
//
// Opening window line simplification: the samples after the last recorded point (the
// anchor) are kept aside while they all lie within toleranceMeters from the segment
// anchor -> newest sample. When one falls outside, the previous sample is recorded and
// becomes the new anchor.
//
// Plain C++ without Arduino dependencies, tested on the PC (firmware/test).

#include <stddef.h>
#include "protocol.h"

struct TrackFilterConfig {
  double toleranceMeters;     // max distance of the route from the recorded segments
  double minDistanceMeters;   // below this distance from the anchor the car is standing still
  uint32_t maxIntervalSec;    // a point at least every X seconds while moving
  uint32_t stationaryIntervalSec;  // a point every X seconds while standing still
};

class TrackFilter {
 public:
  explicit TrackFilter(const TrackFilterConfig &config);

  // Returns true when a point must be recorded, copied in out (it can be an earlier sample)
  bool push(const proto::Point &point, proto::Point &out);

  // The last sample not recorded yet (end of the trip), returns false when there's none
  bool flush(proto::Point &out);

  void reset();

 private:
  static const size_t WINDOW = 24;

  TrackFilterConfig config;
  proto::Point anchor;
  bool hasAnchor;
  proto::Point window[WINDOW];
  size_t windowSize;

  void setAnchor(const proto::Point &point);
  bool deviates(const proto::Point &end) const;
};

// Distance in meters, accurate for the few kilometers between two samples
double pointDistance(const proto::Point &a, const proto::Point &b);

#endif
