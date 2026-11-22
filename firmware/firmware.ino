#include <driver/rtc_io.h>
#include "configurations.h"
#include "clock.h"
#include "connections.h"
#include "coordinates.h"
#include "gnss.h"
#include "modem.h"
#include "ota.h"
#include "owner_tag.h"
#include "power.h"
#include "spool.h"
#include "track_filter.h"
#include "uplink.h"

using namespace proto;

// --- State kept in RTC memory across deep sleep ---
// Times use the RTC clock (clockNow()), it keeps counting in deep sleep
#define RTC_MAGIC 0x43415234
RTC_DATA_ATTR uint32_t rtcMagic = 0;
RTC_DATA_ATTR time_t rtcHeartbeatDue = 0;
// 0 = motion detection armed, otherwise the time it will be armed
RTC_DATA_ATTR time_t rtcMotionArmAt = 0;
RTC_DATA_ATTR Point rtcLastFix;
RTC_DATA_ATTR time_t rtcLastFixClock = 0;
RTC_DATA_ATTR bool rtcHasFix = false;
// Gravity vector of the parked car, measured at the arming of the motion detection
RTC_DATA_ATTR int16_t rtcTiltReference[3];
RTC_DATA_ATTR bool rtcTiltReferenceValid = false;
RTC_DATA_ATTR time_t rtcTiltCheckDue = 0;
// Commands of the server: live tracking and anti-theft pause end at these times (0 = off),
// a position requested with LOCATE is sent at the first wake up with the modem
RTC_DATA_ATTR time_t rtcLiveUntil = 0;
RTC_DATA_ATTR time_t rtcAntitheftPausedUntil = 0;
RTC_DATA_ATTR bool rtcLocateRequested = false;

// Wait for the ACK and the retained commands of the server in the short wake ups
#define REGISTRATION_TIMEOUT_MS 15000
#define COMMANDS_WAIT_MS 1500
// A LOCATE older than this is not executed anymore
#define LOCATE_MAX_AGE_SEC 3600

#if VEHICLE_VOLTAGE_SENSE
#define HEARTBEAT_CRITICAL_BATTERY_SEC 86400
#endif

static bool hardwareReady = false;
static bool sensorsReady = false;
static unsigned long nextConnectAttempt = 0;
static unsigned long reconnectDelay = RECONNECT_MIN_DELAY_MS;
// Timestamp of the last point that carried pressure, temperature and voltage
static uint32_t lastEnvironment = 0;

static bool isIgnitionOn() {
  return digitalRead(PIN_IGNITION_SENSE) == IGNITION_ACTIVE_LEVEL;
}

static bool motionArmed() {
  return rtcMotionArmAt == 0;
}

static bool liveActive() {
  return rtcLiveUntil != 0 && clockNow() < rtcLiveUntil;
}

static bool antitheftPaused() {
  return rtcAntitheftPausedUntil != 0 && clockNow() < rtcAntitheftPausedUntil;
}

// RTC time when a period of the server (frame time + seconds) ends, 0 when already over
static time_t serverDeadline(uint32_t frameTimestamp, uint32_t seconds) {
  uint32_t end = frameTimestamp + seconds;
  uint32_t now = utcNow();
  if (now == 0) now = frameTimestamp;  // utcFromServer() already ran, defensive
  if (end <= now) return 0;
  return clockNow() + (time_t)(end - now);
}

static CommandResult onCommand(const Command &command, uint32_t frameTimestamp) {
  switch (command.id) {
    case CMD_LIVE:
      if (command.seconds == 0) {
        rtcLiveUntil = 0;
        Serial.println("[COMMAND] Live off");
        return RESULT_OK;
      }
      rtcLiveUntil = serverDeadline(frameTimestamp, command.seconds);
      if (rtcLiveUntil == 0) return RESULT_EXPIRED;
      Serial.printf("[COMMAND] Live for %lds\n", (long)(rtcLiveUntil - clockNow()));
      return RESULT_OK;

    case CMD_ANTITHEFT:
      if (command.seconds == 0) {
        rtcAntitheftPausedUntil = 0;
        Serial.println("[COMMAND] Anti-theft resumed");
        return RESULT_OK;
      }
      rtcAntitheftPausedUntil = serverDeadline(frameTimestamp, command.seconds);
      if (rtcAntitheftPausedUntil == 0) return RESULT_EXPIRED;
      Serial.printf("[COMMAND] Anti-theft paused for %lds\n", (long)(rtcAntitheftPausedUntil - clockNow()));
      return RESULT_OK;

    case CMD_LOCATE:
      if (serverDeadline(frameTimestamp, LOCATE_MAX_AGE_SEC) == 0) return RESULT_EXPIRED;
      rtcLocateRequested = true;
      Serial.println("[COMMAND] Locate");
      return RESULT_OK;
  }
  return RESULT_UNKNOWN_COMMAND;
}

static void ensureSensors() {
  if (sensorsReady) return;
  sensorsReady = true;
  initSensors();
}

static void rememberFix(const Point &point) {
  rtcLastFix = point;
  rtcLastFixClock = clockNow();
  rtcHasFix = true;
}

static void addEvents(Point &point, uint8_t events) {
  if (events == 0) return;
  point.events |= events;
  point.ext |= EXT_EVENTS;
}

// Slow changing values are sent at most every ENVIRONMENT_INTERVAL_SEC
static void limitEnvironment(Point &point) {
  bool hasEnvironment = (point.flags & (FLAG_PRESSURE | FLAG_TEMPERATURE)) || (point.ext & EXT_VOLTAGE);
  if (!hasEnvironment) return;

  if (lastEnvironment != 0 && point.timestamp - lastEnvironment < ENVIRONMENT_INTERVAL_SEC) {
    point.flags &= (uint8_t)~(FLAG_PRESSURE | FLAG_TEMPERATURE);
    point.ext &= (uint8_t)~EXT_VOLTAGE;
  } else {
    lastEnvironment = point.timestamp;
  }
}

// Low battery event on the points recorded with the engine off
static void addBatteryEvent(Point &point) {
#if VEHICLE_VOLTAGE_SENSE
  if ((point.ext & EXT_VOLTAGE) && point.voltage * 10UL < LOW_BATTERY_MV) addEvents(point, EVENT_LOW_BATTERY);
#else
  (void)point;
#endif
}

// Serving cell: the server estimates the position from it when the GNSS has no fix
static void addCell(Point &point) {
#if CELL_LOCATION
  CellInfo cell;
  if (!modemCellInfo(cell)) return;
  point.mcc = cell.mcc;
  point.mnc = cell.mnc;
  point.cellArea = cell.area;
  point.cellId = cell.id;
  point.ext |= EXT_CELL;
#else
  (void)point;
#endif
}

// Point without a fix (garage, tunnel, GNSS jammed or broken): the last known position
// marked as stale, with the serving cell and the current readings. Without any fix since
// the power on the position is 0,0 and only the cell locates the car.
static bool stalePosition(Point &point, Status status) {
  uint32_t now = utcNow();
  if (!rtcHasFix && now == 0) return false;

  if (rtcHasFix) {
    point = rtcLastFix;
    if (now == 0) now = rtcLastFix.timestamp + (uint32_t)(clockNow() - rtcLastFixClock);
  } else {
    memset(&point, 0, sizeof(point));
  }
  point.timestamp = now;
  point.flags = status & FLAG_STATUS_MASK;
  if (rtcHasFix && (rtcLastFix.flags & FLAG_ALTITUDE)) point.flags |= FLAG_ALTITUDE;
  point.ext = EXT_STALE;
  point.events = 0;
  addReadings(point);
  addCell(point);
  return true;
}

// Current position, or a stale one when the GNSS has no fix
static bool currentPosition(Point &point, Status status, unsigned long timeoutMs) {
  if (waitForFix(point, status, timeoutMs)) {
    rememberFix(point);
    return true;
  }
  return stalePosition(point, status);
}

static void initHardware() {
  if (hardwareReady) return;
  hardwareReady = true;

  ensureSensors();
  clearAccelInterrupt();
  spoolInit();

#if GNSS_SOURCE == GNSS_SOURCE_EXTERNAL
  gnssBegin();
#endif
  if (!modemPowerOn()) return;
#if GNSS_SOURCE == GNSS_SOURCE_MODEM
  gnssBegin();
#endif

  ModemInfo info = modemReadInfo();
  if (!uplinkInit(info)) return;

  uplinkSetCommandHandler(onCommand);
  serverBegin(uplinkOnFrame);
}

// One connection attempt at a time with exponential back-off: every attempt costs data.
// Connected means acknowledged: the HELLO authenticates the tracker at every connection.
static bool ensureConnected() {
  if (uplinkReady()) return true;
  if (millis() < nextConnectAttempt) return false;

  if (serverConnect()) {
    uint32_t now = utcNow();
    uplinkOnConnected(now != 0 ? now : (rtcHasFix ? rtcLastFix.timestamp : 0));
    if (uplinkWaitAck(REGISTRATION_TIMEOUT_MS)) {
      reconnectDelay = RECONNECT_MIN_DELAY_MS;
      return true;
    }
    Serial.println("[UPLINK] No ACK from the server");
    serverDisconnect();
  }

  nextConnectAttempt = millis() + reconnectDelay;
  reconnectDelay = min(reconnectDelay * 2, (unsigned long)RECONNECT_MAX_DELAY_MS);
  return false;
}

// Sends the offline queue, a frame at a time. False when it couldn't send everything.
static bool drainSpool(unsigned long budgetMs) {
  Point buffer[40];
  unsigned long start = millis();

  while (spoolCount() > 0 && millis() - start < budgetMs) {
    size_t count = spoolPeek(buffer, 40);
    size_t sent = uplinkSend(buffer, count);
    if (sent == 0) return false;
    spoolConsume(sent);
    uplinkLoop();
  }
  return spoolCount() == 0;
}

// Sends the points keeping the chronological order with the offline queue
static void deliver(const Point *points, size_t count) {
  if (count == 0) return;

  if (spoolCount() == 0 && ensureConnected()) {
    size_t sent = uplinkSend(points, count);
    points += sent;
    count -= sent;
  }
  if (count > 0) spoolAppend(points, count);
}

// Connection with the ACK of the HELLO: device id at the first boot and server time.
// waitCommands gives time to the pending commands to arrive.
static void connectAndRegister(bool waitCommands) {
  if (!ensureConnected()) return;
  if (waitCommands) uplinkPoll(COMMANDS_WAIT_MS);
}

// Position requested by the server with LOCATE
static void serveLocate(Status status) {
  if (!rtcLocateRequested) return;
  Point point;
  if (currentPosition(point, status, GPS_FIX_TIMEOUT_SEC * 1000UL)) {
    deliver(&point, 1);
    rtcLocateRequested = false;
  }
}

// True when the car was lifted since the arming (tow truck, jack)
static bool checkTilt() {
#if TILT_THRESHOLD_DEG > 0
  if (!rtcTiltReferenceValid) return false;
  ensureSensors();
  int16_t gravity[3];
  if (!readGravity(gravity)) return false;

  float angle = tiltDegrees(rtcTiltReference, gravity);
  Serial.printf("[TILT] %.1f degrees from the parking position\n", angle);
  return angle >= TILT_THRESHOLD_DEG;
#else
  return false;
#endif
}

static void goToSleep() {
  time_t now = clockNow();
  if (rtcMotionArmAt != 0 && rtcMotionArmAt <= now) rtcMotionArmAt = 0;
  if (rtcAntitheftPausedUntil != 0 && rtcAntitheftPausedUntil <= now) rtcAntitheftPausedUntil = 0;
  bool paused = antitheftPaused();
  bool armed = motionArmed() && !paused;

#if TILT_THRESHOLD_DEG > 0
  // The parking position is measured once the car settled (arming delay)
  if (armed && !rtcTiltReferenceValid) {
    ensureSensors();
    rtcTiltReferenceValid = readGravity(rtcTiltReference);
    rtcTiltCheckDue = now + TILT_CHECK_INTERVAL_SEC;
  }
#endif

  // Next timer wake up: heartbeat, arming of the motion detection or tilt check
  time_t wakeAt = rtcHeartbeatDue;
  if (!motionArmed() && rtcMotionArmAt < wakeAt) wakeAt = rtcMotionArmAt;
  if (paused && rtcAntitheftPausedUntil < wakeAt) wakeAt = rtcAntitheftPausedUntil;
#if TILT_THRESHOLD_DEG > 0
  if (armed && rtcTiltReferenceValid && rtcTiltCheckDue < wakeAt) wakeAt = rtcTiltCheckDue;
#endif
  time_t seconds = wakeAt > now ? wakeAt - now : 1;
  esp_sleep_enable_timer_wakeup((uint64_t)seconds * 1000000ULL);

  // Ignition always wakes up the device
#if IGNITION_ACTIVE_LEVEL == LOW
  rtc_gpio_pullup_en((gpio_num_t)PIN_IGNITION_SENSE);
  rtc_gpio_pulldown_dis((gpio_num_t)PIN_IGNITION_SENSE);
#endif
  esp_sleep_enable_ext0_wakeup((gpio_num_t)PIN_IGNITION_SENSE, IGNITION_ACTIVE_LEVEL);

  uint64_t ext1Mask = 0;
  if (armed) {
    // A latched interrupt would wake up the device immediately
    ensureSensors();
    clearAccelInterrupt();
    ext1Mask |= 1ULL << PIN_ACCEL_INT;
  }
#if POWER_GOOD_SENSE
  // Wakes up when the car stops supplying the tracker (only while it's supplying it,
  // a high level at sleep time would wake up immediately)
  if (!paused && externalPowerPresent()) ext1Mask |= 1ULL << PIN_POWER_GOOD;
#endif
  if (ext1Mask) esp_sleep_enable_ext1_wakeup(ext1Mask, ESP_EXT1_WAKEUP_ANY_HIGH);

  Serial.printf("[POWER] Deep sleep for %lds, motion detection %s\n", (long)seconds,
                armed ? "armed" : (paused ? "paused by the owner" : "paused"));
  Serial.flush();
  esp_deep_sleep_start();
}

static void sleepNow() {
  // Firmware update offered by the server: installed before sleeping (reboots on success)
  if (otaPending()) otaRun(OTA_MAX_SEC * 1000UL, ensureConnected);
  if (hardwareReady) prepareForSleep();
  gnssSleep();
  goToSleep();
}

// Deep sleep paths after a motion, tilt or power alarm: tracking already done
static void endAlarm() {
  rtcMotionArmAt = clockNow() + ALARM_COOLDOWN_SEC;
  // Measured again at the next arming: a car left on a jack doesn't raise alarms forever
  rtcTiltReferenceValid = false;
}

static void runDriving() {
  Serial.println("[MODE] Driving");
  rtcTiltReferenceValid = false;
  initHardware();
  connectAndRegister(false);

  TrackFilterConfig filterConfig = {
    ADAPTIVE_TOLERANCE_METERS,
    THRESHOLD_DISTANCE,
#if ADAPTIVE_SAMPLING
    ADAPTIVE_MAX_INTERVAL_SEC,
#else
    0,  // Every sample farther than THRESHOLD_DISTANCE is recorded
#endif
    STATIONARY_INTERVAL_SEC
  };
  TrackFilter filter(filterConfig);

  Point batch[BATCH_SIZE];
  size_t batchSize = 0;
  unsigned long batchStartedAt = 0;
  uint32_t lastRecorded = 0;
  unsigned long lastSample = 0;
  unsigned long ignitionOffSince = 0;
  unsigned long lastFixAt = millis();
  unsigned long lastStaleAt = 0;
  bool forceSend = false;
  uint8_t pendingEvents = 0;
  bool hadPower = externalPowerPresent();

  auto record = [&](Point &point) {
    limitEnvironment(point);
    lastRecorded = point.timestamp;
    if (batchSize == 0) batchStartedAt = millis();
    batch[batchSize++] = point;
    if (batchSize >= BATCH_SIZE) {
      deliver(batch, batchSize);
      batchSize = 0;
    }
  };

  while (true) {
    gnssPoll();

    // Ignition off, debounced
    if (!isIgnitionOn()) {
      if (ignitionOffSince == 0) ignitionOffSince = millis();
      if (millis() - ignitionOffSince >= IGNITION_DEBOUNCE_MS) break;
    } else {
      ignitionOffSince = 0;
    }

    // The tracker supply was cut while driving
    bool hasPower = externalPowerPresent();
    if (hadPower && !hasPower && !antitheftPaused()) pendingEvents |= EVENT_POWER_LOST;
    hadPower = hasPower;

    if (ensureConnected()) {
      uplinkLoop();
      drainSpool(2000);
    }
    if (rtcLocateRequested) {
      // LOCATE: the next sample is recorded and sent right away
      rtcLocateRequested = false;
      forceSend = true;
      lastSample = 0;
    }

    if (millis() - lastSample >= SAMPLE_INTERVAL_MS) {
      lastSample = millis();

      bool live = liveActive() || forceSend;
      Point point;
      if (samplePoint(point, MOVING)) {
        rememberFix(point);
        lastFixAt = millis();
        Point out;
        if (pendingEvents) {
          // An event is always recorded, and restarts the route from its point
          addEvents(point, pendingEvents);
          pendingEvents = 0;
          filter.reset();
        }
        if (live) {
          // Somebody is watching: every sample, the filter restarts from it
          filter.reset();
          Point ignored;
          filter.push(point, ignored);
          record(point);
          forceSend = false;
        } else if (filter.push(point, out)) {
          record(out);
        }
      } else if (millis() - lastFixAt >= CELL_FALLBACK_INTERVAL_SEC * 1000UL &&
                 (lastStaleAt == 0 || millis() - lastStaleAt >= CELL_FALLBACK_INTERVAL_SEC * 1000UL)) {
        // No fix for a while (tunnel, underground car park, GNSS jammed): the serving
        // cell keeps an approximate track
        lastStaleAt = millis();
        if (stalePosition(point, MOVING)) {
          addEvents(point, pendingEvents);
          pendingEvents = 0;
          record(point);
        }
      }

      // Partial batch: the position must not get too old on the map (live: right away)
      if (batchSize > 0 && (live || millis() - batchStartedAt >= BATCH_MAX_DELAY_SEC * 1000UL)) {
        deliver(batch, batchSize);
        batchSize = 0;
      }
    }

    delay(20);
  }

  Serial.println("[POWER] Ignition off");

  // End of the route and parking position, flushed with the pending points
  Point last;
  if (filter.flush(last)) record(last);

  Point parking;
  if (currentPosition(parking, ENGINE_OFF, 3000) && parking.timestamp > lastRecorded) {
    lastEnvironment = 0;  // Always with the environment values
    addBatteryEvent(parking);
    record(parking);
  }
  deliver(batch, batchSize);
  if (uplinkReady()) drainSpool(30000);

  time_t now = clockNow();
  rtcHeartbeatDue = now + HEARTBEAT_PERIOD_SEC;
  rtcMotionArmAt = now + ALARM_ARM_DELAY_SEC;
  sleepNow();
}

static void runHeartbeat() {
  Serial.println("[MODE] Heartbeat");
  rtcHeartbeatDue = clockNow() + HEARTBEAT_PERIOD_SEC;

  initHardware();
  connectAndRegister(true);
  rtcLocateRequested = false;  // The heartbeat position answers it

  Point point;
  if (currentPosition(point, HEARTBEAT, GPS_FIX_TIMEOUT_SEC * 1000UL)) {
    addBatteryEvent(point);
#if VEHICLE_VOLTAGE_SENSE
    // Battery almost flat: the engine start matters more than the heartbeats
    if ((point.ext & EXT_VOLTAGE) && point.voltage * 10UL < CRITICAL_BATTERY_MV) {
      rtcHeartbeatDue = clockNow() + HEARTBEAT_CRITICAL_BATTERY_SEC;
    }
#endif
    deliver(&point, 1);
  }
  if (uplinkReady()) drainSpool(30000);
}

static void runAlarm(uint8_t events) {
  Serial.printf("[MODE] Alarm! Events 0x%02x\n", (unsigned)events);

  initHardware();
  connectAndRegister(true);
  // The owner paused the anti-theft (commands just received): no tracking
  if (antitheftPaused()) {
    Serial.println("[ALARM] Anti-theft paused by the owner, ignored");
    return;
  }

  Point start;
  bool hasStart = currentPosition(start, ALARM, 20000);
  if (hasStart) {
    addEvents(start, events);
    deliver(&start, 1);
  }

  // Follows the car while it moves, up to ALARM_MAX_TRACK_SEC
  unsigned long begin = millis();
  unsigned long trackUntil = begin + ALARM_TRACK_SEC * 1000UL;
  unsigned long maxUntil = begin + ALARM_MAX_TRACK_SEC * 1000UL;
  unsigned long lastSample = millis();

  while ((long)(millis() - trackUntil) < 0) {
    // The owner started the engine
    if (isIgnitionOn()) return;

    gnssPoll();
    if (ensureConnected()) uplinkLoop();

    unsigned long interval = liveActive() ? SAMPLE_INTERVAL_MS : ALARM_SAMPLE_INTERVAL_MS;
    if (millis() - lastSample >= interval) {
      lastSample = millis();
      Point point;
      bool fix = samplePoint(point, ALARM);
      if (!fix && stalePosition(point, ALARM)) {
        // Without a fix the cell may still follow a car loaded on a truck
        if (!hasStart) {
          addEvents(point, events);
          hasStart = true;
          start = point;
        }
        deliver(&point, 1);
      }
      if (fix) {
        rememberFix(point);
        if (!hasStart) {
          addEvents(point, events);
          start = point;
          hasStart = true;
        } else if (distanceMeters(start, point) >= ALARM_MOVE_METERS) {
          trackUntil = min(millis() + ALARM_TRACK_SEC * 1000UL, maxUntil);
          start = point;
        }
        deliver(&point, 1);
      }
    }
    delay(50);
  }
}

void setup() {
  Serial.begin(115200);

#if IGNITION_ACTIVE_LEVEL == LOW
  pinMode(PIN_IGNITION_SENSE, INPUT_PULLUP);
#else
  pinMode(PIN_IGNITION_SENSE, INPUT);
#endif
  pinMode(PIN_ACCEL_INT, INPUT);
  powerInit();

  esp_sleep_wakeup_cause_t cause = esp_sleep_get_wakeup_cause();
  if (cause == ESP_SLEEP_WAKEUP_UNDEFINED || rtcMagic != RTC_MAGIC) {
    // Power on: clean RTC state
    rtcMagic = RTC_MAGIC;
    clockReset();
    rtcHasFix = false;
    rtcTiltReferenceValid = false;
    rtcLiveUntil = 0;
    rtcAntitheftPausedUntil = 0;
    rtcLocateRequested = false;
    rtcHeartbeatDue = clockNow() + HEARTBEAT_PERIOD_SEC;
    rtcMotionArmAt = clockNow() + ALARM_ARM_DELAY_SEC;
    printVariables();
  }

  if (isIgnitionOn()) {
    runDriving();  // Never returns: sleeps at the engine off
  }

  uint8_t events = 0;
  if (cause == ESP_SLEEP_WAKEUP_EXT1) {
    uint64_t pins = esp_sleep_get_ext1_wakeup_status();
#if POWER_GOOD_SENSE
    if ((pins & (1ULL << PIN_POWER_GOOD)) && !externalPowerPresent()) events |= EVENT_POWER_LOST;
#endif
    if ((pins & (1ULL << PIN_ACCEL_INT)) && motionArmed()) {
      events |= EVENT_MOTION;
      if (checkTilt()) events |= EVENT_TILT;
    }
  } else if (cause == ESP_SLEEP_WAKEUP_TIMER && motionArmed() && rtcTiltReferenceValid &&
             clockNow() >= rtcTiltCheckDue) {
    rtcTiltCheckDue = clockNow() + TILT_CHECK_INTERVAL_SEC;
    if (checkTilt()) events |= EVENT_TILT;
  }
  if (antitheftPaused()) events = 0;

#if OWNER_TAG
  // Only a motion (the owner opening the car): tilt and power loss always raise the alarm
  if (events == EVENT_MOTION && ownerTagNearby(OWNER_TAG_SCAN_MS)) {
    Serial.println("[ALARM] Owner tag nearby, motion ignored");
    rtcMotionArmAt = clockNow() + ALARM_ARM_DELAY_SEC;
    events = 0;
  }
#endif

  if (events) {
    runAlarm(events);
    if (isIgnitionOn()) runDriving();
    endAlarm();
  } else if (cause == ESP_SLEEP_WAKEUP_TIMER && clockNow() >= rtcHeartbeatDue) {
    runHeartbeat();
  }
  if (hardwareReady) serveLocate(HEARTBEAT);

  // Timer wake ups for the arming or the tilt check end here, without the modem
  sleepNow();
}

void loop() {
  // Unreachable: every path of setup() ends in deep sleep
}
