# Custom dashboards

Besides the screens of each vehicle, every user can build their own **dashboards**: widgets
chosen from a catalog of values, on a grid that follows the screen (2 columns on a phone, up
to 8 on a desktop). Dashboards are personal; friends can be sent just the layout, which
they use with their own vehicles.

## Creating a dashboard

*Dashboards* in the navigation bar. The first time you start from a template:

- **Vehicles overview**: km, driving time, trips and cost of the period, km per day and per
  vehicle, map with position and state, deadlines;
- **Tracker diagnostics**: voltage, signal, satellites, data on the SIM, battery at rest over
  the last 90 days, alarms;
- **Blank**.

**+** adds more dashboards (20 at most), the menu renames or deletes them; the name at the
top picks the one shown. The calendar icon changes the **period** of the dashboard (today,
7 / 30 / 90 days, 12 months, year to date or chosen dates).

## Current dashboard

From the menu **⋮ › Set as current** a dashboard becomes the **current** one (★ next to the
name; one per user):

- it opens first in *Dashboards*;
- it takes the place of the standard analysis in the **Analysis** tab of every vehicle: its
  widgets show only that vehicle, in the period chosen at the top of the screen (widgets with
  their own period keep it). Widgets of values the vehicle doesn't have (e.g. LTE signal on a
  car without a tracker) don't appear.

In the tab, **Standard analysis** goes back to the classic view (trips, charts, coverage) and
the icon next to it opens the dashboard to edit it. *⋮ › No longer current* brings back the
standard analysis for all the vehicles.

## Sharing with friends

**⋮ › Share with a friend** sends one of your [friends](features.md#friends-and-sharing) **just the layout**:
widgets, views and periods, never your vehicles or their data (in the copy sent every widget
is on "all vehicles"). Sending it again replaces the previous copy; deleting the dashboard
or removing the friend withdraws the copies not used yet.

The friend finds it at the top of their dashboards (and gets a message in the app):

- **Use** asks for the name and which **of their own vehicles** it shows: *all my active
  vehicles* or the chosen ones. A widget of values none of the chosen vehicles has (e.g.
  tracker data choosing only a car without a tracker) stays on the chosen vehicles and shows
  them as not available;
- **Decline** drops it, without telling the sender.

The dashboard created is entirely theirs: changing it doesn't change the friend's one.

## Editing the widgets

**Edit** opens the list of the widgets: add them, tap one to change it, duplicate or remove
it from the menu, drag it by the handle to change the order. *Save* confirms everything
together; leaving without saving asks first.

For each widget you choose:

| Option | Values |
| :--- | :--- |
| **Value** | from the catalog below |
| **View** | number, line over time, bars over time, bars per vehicle, table per vehicle; list or map for the current state |
| **Value** (tracker data) | average, minimum, maximum or latest value |
| **Grouping** | automatic, hours (tracker data), days, weeks, months |
| **Period** | the one of the dashboard, or its own |
| **Vehicles** | *all my active vehicles* (also the ones added later, not the archived ones) or the chosen ones |
| **Title, width, height** | optional title, 1-4 columns, 1-2 rows |

The **preview** at the bottom shows the real values right away.

## Catalog of values

| Group | Values | Devices | Longest period |
| :--- | :--- | :--- | :--- |
| Trips | distance, business and personal km, driving time, number of trips, top speed | all | 3 years |
| Trips | alarms, data on the SIM, battery at rest | trackers | 3 years |
| Costs | estimated cost, fuel cost, wear, litres (from the consumption, prices and wear entered) | all | 3 years |
| Costs | spent on refuels, litres refuelled, price paid per litre, real consumption (from the [refuels](features.md#trips-log-and-costs)) | trackers and vehicles | 3 years |
| Tracker data | moving speed, altitude | all | 93 days |
| Tracker data | LTE signal, satellites, voltage, temperature, pressure | trackers | 93 days |
| Tracker data | a numeric field of the **extra data** (e.g. `rpm`) | trackers | 93 days |
| Current state | odometer, deadlines | vehicles | — |
| Current state | position and state | all, shared ones too | — |

Trip and cost totals come from the daily summaries (fast even over years); tracker data are
read from the points, so their period is limited to 93 days: with a longer period the widget
says so. Days follow the time zone of the platform (`TIMEZONE`).

## Vehicles no longer available

A widget keeps the vehicles chosen. When a vehicle is deleted or a share ends or is revoked,
the widget stays and shows «N vehicles no longer available» instead of their data. Of the
vehicles **shared with you** only *Position and state* is shown: the other data belong to the
owner.

## API

| Method | Path | |
| :--- | :--- | :--- |
| `GET` | `/api/dashboards` | dashboards of the user |
| `POST` | `/api/dashboards` | `{ name, layout }` |
| `PUT` / `DELETE` | `/api/dashboards/:id` | change, delete |
| `PUT` | `/api/dashboards/:id/current` | `{ current }`: current dashboard (only one) |
| `POST` | `/api/dashboards/:id/share` | `{ friendId }`: sends the layout to a friend |
| `GET` | `/api/dashboards/shares` | layouts received and waiting (20 at most) |
| `POST` | `/api/dashboards/shares/:id/accept` | `{ name, devices: "all" \| [id…] }` → new dashboard |
| `DELETE` | `/api/dashboards/shares/:id` | declines a layout received |
| `POST` | `/api/dashboards/data` | `{ period, widgets }` → `{ results: { <widget id>: … } }` |

The `layout` is `{ version: 1, period, widgets }`, validated by the backend (30 widgets at
most, 20 vehicles per widget). Widgets of values removed from the catalog in the future are
dropped when read. The catalog is in `backend/src/services/metrics.ts` and
`app/lib/screens/dashboards/catalog.dart`.
