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
- **Temporary links to the position** (*Settings → Temporary links to the position*): for
  someone without an account ("I'm on my way"). The owner creates a link valid 1 to 24 hours,
  with an optional label; the address is shown only when it's created (the server keeps its
  hash). Whoever opens it sees in the browser the name, color and latest position of the
  device, refreshed every 15 seconds, until it ends: no history, tracker data or account. At
  most 5 active links per device; the list shows when each was opened and each can be revoked
  at any time. An expired, revoked or wrong link gives the same *Link expired or revoked*
  page.

## Arrival areas and alerts

- **Areas**: every user sets **circular** areas (50 m - 50 km) or **polygons** (3 to 50
  vertices tapped on the map, up to 50 km: a neighbourhood, a car park, a stretch of road)
  and gets a notification when the device enters (and, if wanted, leaves). Leaving a polygon
  has a margin of 30 m, so an inaccurate GPS point on the border doesn't send double alerts.
  Areas are personal. An area can alert **only at certain times** (days and time range; if
  the end comes before the start it goes past midnight, e.g. 23:00-6:00).
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
  diesel, LPG, hybrid, electric), unit of the consumption (*l/100 km* or *km/l*; for electric
  ones *kWh/100 km* or *km/kWh*) and the **histories**: fuel price (or energy price in €/kWh),
  **consumption**, **wear** in €/km and **mileage allowance**. Every value holds from its date
  until the next one; every trip uses the values of the day it started. *Look up the ACI cost
  per km* opens the search for the model (there's no public API of the ACI tables).
- **Mileage allowance**: the euro per km paid back for the business trips (ACI tables or the
  agreement with the company). The trip log of the month adds the *Allowance (€)* column to the
  business trips and their totals; the monthly summary and the dashboards show the total.
- **National average price**: the backend downloads the weekly survey of the Italian ministry
  of the environment (MASE, open data, every Monday) of petrol, diesel and LPG; with *Price
  from the national average* every new week enters the history of the vehicle on its own (a
  price entered by hand on the same day wins). A hybrid follows the average of petrol; there's
  no public average for electric cars: the price is entered by hand or comes from the
  charges.
- **Refuels** (trackers and vehicles, *Analysis → Refuels*): date, litres, amount, odometer
  (the current one proposed), full tank or partial, note. Between two full tanks the **real
  consumption** is the litres put in since the previous full tank (partial ones included)
  divided by the km driven; values outside 1-50 l/100 km don't count. The amount gives the
  price per litre. With *Price and consumption from the refuels* (in the costs, on at first)
  every refuel with an amount adds to the history the price paid from its day and every full
  tank measured the consumption from the previous full tank: they are marked *from the
  refuels*, follow the changes of the refuels and can't be deleted by hand; a value entered by
  hand on the same day wins and the national average stops for 14 days after a refuel with an
  amount.
- **Charges** (electric vehicles): like the refuels, in kWh, with the place (*at home* or
  *charging station*); between two full charges the real consumption in kWh/100 km, from the
  amount the price per kWh. The dashboard metrics in litres skip the electric ones and those in
  kWh count only them.
- **Statistics over time**: for 12 months or 26 weeks km (work and personal), driving hours
  and trips; for trackers also battery health, MB on the SIM and alarms. Daily summary kept 3
  years for trackers and vehicles, 400 days for phones.

## Monthly summary

On the 1st of every month, from 8:00 (time zone `TIMEZONE`), a notification with the km, trips
and costs of the month just ended reaches who had trips or refuels; it's turned off in
**Account → Notification at the start of the month**. The *Monthly summary* page (from the
account or tapping the notification) shows the totals with the change on the month before,
every vehicle (km, trips, driving time, work km, costs, mileage allowance, refuels or charges
and real consumption, data on the SIM, alarms) and the deadlines near or overdue (with the
expected day for those by km); the arrows change month (up to 3 years
back), the current month goes up to today.

## Deadlines and maintenance

For trackers and [vehicles without a tracker](phone-vehicles.md): odometer (enter the
dashboard reading, then it follows the km of the trips; correct it when needed), standard
deadlines (service and tyres by km, inspection, insurance and road tax by date) or custom ones
(emission check, extinguisher...), recurring or one-off, with their state (ok / near /
overdue), *Done* (recurring ones move forward) and the history of the work. Alert when the
chosen days or km are left and at the deadline.

For the deadlines by km the app shows the **expected day**, from the average km a day of the
last 60 days (at least 14 days of data are needed; beyond 3 years it isn't shown): "in 900 km
(expected around 4 December)". The expected day appears in the alerts and in the monthly
summary too, and a deadline becomes *near* also when the expected day falls within the reminder
days.

## Parking

For trackers and vehicles, from the panel of the live map (*Park*):

- the place is the latest position of the vehicle, marked on the map with a **P**;
- the **end of the ticket** is optional (up to 31 days): with it a **reminder** arrives 0 to 60
  minutes before and a notice when it ends; without it (paid by the minute, e.g. Telepass or an
  app) only the place is kept;
- a note (level, spot, color of the lines);
- the parking ends by itself when the vehicle leaves (moving faster than 10 km/h 2 minutes
  after the start) or with *End parking*; ended parkings are deleted after 30 days.

With *Settings → Suggest the parking at ignition off* (trackers) a notification at ignition off
suggests setting it, at most once every 10 minutes and not while one is active. If the backend
was down at the end and more than 60 minutes have passed, the notice doesn't arrive late.

## Extra data (trackers)

Fields read by the tracker from another board of the vehicle (`EXTRA` frame, see the
[protocol](../reference/protocol.md#extra-data-extra)), shown as they arrive: latest value of
every field and readings with date and time, no charts.

## Your data

*Export my data* downloads a JSON with profile, sign-ins, friends, devices with positions,
areas, notifications, costs, refuels, parkings, temporary links and extra data. *Delete account* deletes phones, vehicles,
positions, shares, friends, areas and notifications; trackers become free again and can be
paired again with the code on their label.
