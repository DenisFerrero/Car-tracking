# Features

## Map

All the visible devices (own and shared) with their latest position, updated in real time.
Filters: mine / shared with me, owner, moving / stopped / unreachable (tracker silent beyond
`OFFLINE_AFTER_HOURS`, phone that stopped sharing), vehicles / phones, search by name; counter
of the devices shown and a button to frame the filtered ones. Nearby devices are grouped with
their number: a tap zooms in, or lists the ones at the same spot.

## Tabs of a device

- **Live**: realtime position (for the owner of a tracker it turns on live mode for 10
  minutes, renewed while the screen is open), trail of the last 2 hours, signal, satellites,
  battery, temperature; commands *Live 30 min*, *Locate*, *Pause anti-theft* (trackers only).
  **Walk there** opens Google Maps (app or browser) with the walking route to the car or the
  friend.
- **History**: route of the period colored by speed, **LTE signal** or **satellites**, dashed
  gaps, events, slider to replay the points.
- **Analysis**: km, driving time, trips; for trackers also speed, signal, satellites,
  altitude, car battery voltage, temperature and pressure, fix quality, **coverage map** and
  **SIM data** with the end-of-month projection. Every trip opens on the map; **export** to
  GPX or CSV.
- **Areas**: arrival areas of the user on a map and a list.
- **Settings** (owner): name, color, notifications by kind, sharing, firmware update, removal.

A shared device shows only **Live** and **Areas**, plus *Leave the share*.

## Dashboards

Personal dashboards with widgets chosen from a catalog of values (km, costs, tracker data,
deadlines, position) for one or more vehicles; the current one replaces the analysis of
every vehicle and the layout can be sent to friends: see [Custom dashboards](dashboards.md).

## Friends and sharing

- Everyone has a personal code (`ABCDE-FGHJK`, also as a QR code): whoever enters it sends a
  **friend request**, which the other accepts or declines. At most 20 pending requests; the
  code can be regenerated; removing a friend ends the shares between the two.
- The owner shares a device read-only with a friend, forever or until a date and time (quick
  choices from 1 hour to 7 days). The receiver sees name, position, state, speed, last contact
  and expiry: no IMEI, signal, battery, alarms, earlier history or commands.

## Arrival areas and alerts

- **Areas**: every user sets circular areas (50 m - 50 km) and gets a notification when the
  device enters (and, if wanted, leaves). Areas are personal. An area can alert **only at
  certain times** (days and time range; if the end comes before the start it goes past
  midnight, e.g. 23:00-6:00).
- **Long stop**: alert when the device stays still for more than 1-48 hours outside the areas
  of the user.
- **Low battery** of a shared phone: threshold 10-50%.
- **Car battery health** (trackers): average resting voltage of the last 7 days; < 12.2 V weak
  (alert at most every 14 days).

## Trips, log and costs

- **Trip log**: every trip is marked *work* or *personal* with a note; *Trip log of the month*
  downloads a CSV (Italian format with `;` and decimal comma, for Excel) with date, times,
  start, arrival, km, duration, kind, notes and costs, and the totals.
- **Trip costs** (trackers, vehicles and phones): model and **fuel** of the vehicle (petrol,
  diesel, LPG), unit of the consumption (*l/100 km* or *km/l*) and three **histories**: fuel
  price, **consumption** and **wear** in €/km. Every value holds from its date until the next
  one; every trip uses the values of the day it started. *Look up the ACI cost per km* opens
  the search for the model (there's no public API of the ACI tables).
- **National average price**: the backend downloads the weekly survey of the Italian ministry
  of the environment (MASE, open data, every Monday) of petrol, diesel and LPG; with *Price
  from the national average* every new week enters the history of the vehicle on its own (a
  price entered by hand on the same day wins).
- **Statistics over time**: for 12 months or 26 weeks km (work and personal), driving hours
  and trips; for trackers also battery health, MB on the SIM and alarms. Daily summary kept 3
  years for trackers and vehicles, 400 days for phones.

## Deadlines and maintenance

For trackers and [vehicles without a tracker](phone-vehicles.md): odometer (enter the
dashboard reading, then it follows the km of the trips; correct it when needed), standard
deadlines (service and tyres by km, inspection, insurance and road tax by date) or custom ones
(emission check, extinguisher...), recurring or one-off, with their state (ok / near /
overdue), *Done* (recurring ones move forward) and the history of the work. Alert when the
chosen days or km are left and at the deadline.

## Extra data (trackers)

Fields read by the tracker from another board of the vehicle (`EXTRA` frame, see the
[protocol](../reference/protocol.md#extra-data-extra)), shown as they arrive: latest value of
every field and readings with date and time, no charts.

## Your data

*Export my data* downloads a JSON with profile, sign-ins, friends, devices with positions,
areas, notifications, costs and extra data. *Delete account* deletes phones, vehicles,
positions, shares, friends, areas and notifications; trackers become free again and can be
paired again with the code on their label.
