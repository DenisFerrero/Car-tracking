# Phone and vehicles without a tracker

## The phone as a tracker

*Devices → Add → This phone*: without hardware, the phone shares its position and becomes a
device like the others (sharing with friends, arrival areas, history). Android app only (the
browser can't send the position in the background).

- Foreground service with a persistent notification, in a separate isolate: it goes on with
  the app closed and, with the location allowed «All the time», restarts after a reboot.
- A point every 15 s or 20 m; when still the latest position every 5 minutes; battery level of
  the phone visible to friends; *Pause 1 hour* from the app or the notification.
- Upload with an **upload token** of the phone, not the session: it's valid only for the
  positions of that phone and changes at every start of the sharing. Points taken without a
  network stay in a queue and leave in batches.
- Personal positions are kept for `PHONE_RETENTION_DAYS` days.

## Sharing as a person or from the vehicle

On the *This phone* screen the **Share as** section offers:

- **Myself**: the position of the person, seen by friends.
- **One of your vehicles**: the positions become the car's. The personal position stays at
  the last point, the car records the trip.

The choice can change at any time, also while sharing, and stays for the next times. Points
queued without a network keep the choice made when they were taken. *Add vehicle* creates a
vehicle and chooses it at once.

## Vehicles without a tracker

*Devices → Add → Vehicle without a tracker* (also from the browser): name, model, fuel and
color. A vehicle is a device of the user fed by the phone of the owner while sharing from it.

| Feature | Vehicle from the phone | Tracker |
| :--- | :---: | :---: |
| Realtime position, history, trips, export | ✓ (only while the phone is on board and shares from the vehicle) | ✓ always |
| Trip costs with fuel, national average price | ✓ | ✓ |
| Work / personal trip log | ✓ | ✓ |
| Odometer and deadlines (service, inspection, road tax...) | ✓ | ✓ |
| Statistics over time (km, hours, trips) | ✓ | ✓ |
| Arrival areas, long stop, sharing with friends | ✓ | ✓ |
| «Walk there» to the parked car | ✓ (latest recorded position) | ✓ |
| Anti-theft, movement and lift alarms, power cut | ✗ (the phone doesn't stay in the car) | ✓ |
| Commands (Live, Locate, Pause anti-theft) | ✗ | ✓ |
| Signal, satellites, battery voltage, coverage, SIM data | ✗ | ✓ |
| Firmware updates, extra data | ✗ | ✓ |

- A vehicle is never «unreachable»: without a phone on board it's simply parked.
- Trips are split as for phones: a stop longer than 5 minutes ends the trip.
- Only the owner of both the vehicle and the phone can share from the vehicle; at most 10
  vehicles per user.
- The positions of the vehicle are kept for `RETENTION_DAYS` days like the trackers': they're
  data of the car, not of the person.
- Deleting the vehicle deletes history, costs, deadlines, areas and shares.
- A vehicle can receive a tracker later: the pairing asks for the vehicle and its data stay.
  The same way a tracker moves to another vehicle and the previous one stays, archived if you
  like ([New tracker](../devices/new-device.md#moving-the-tracker-to-another-vehicle)).

!!! tip "Several people in the same car"
    The vehicle can be shared read-only, but only the owner can feed it from their phone. For a
    family car driven by several people a tracker is the better choice.
