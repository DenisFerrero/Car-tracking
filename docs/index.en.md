# Car Tracking

GPS tracker for cars based on the ESP32, with a multi-user platform for the realtime
position, the history, the cost of the trips, the deadlines of the vehicle and the anti-theft.
Web and Android app from the same Flutter code. Everything open source, no paid services:
OpenStreetMap maps, no Google token.

```text
[ESP32 tracker] --wss /tracker (encrypted binary frames)--+
[Android phone] --HTTPS (positions of the phone)----------+
                                                          v
[Android app / Browser] --HTTPS + WebSocket--> [Traefik, port 443] --> [Node.js backend] --> [TimescaleDB]
                                                                                  REST API, realtime,
                                                                                  tracker gateway,
                                                                                  web app, FCM push
```

## What it does

- **Hardware tracker** ([devices](devices/index.md)): GPS and LTE, adaptive sampling, offline
  queue, anti-theft with an accelerometer, wake-up from the ignition, remote updates (also
  automatic).
- **Phone as a tracker** ([phone and vehicles](app/phone-vehicles.md)): without hardware, the
  phone shares the position of the person or of a **vehicle** of the user, which has trips,
  costs, odometer and deadlines like a tracker.
- **Platform**: users invited by the administrator (no public sign-up), passkeys or password +
  TOTP, friends and temporary shares, arrival areas, push notifications.
- **Analysis** ([features](app/features.md)): trips, trip log for reimbursements, costs with
  the history of price, consumption and wear, national average fuel prices, statistics over
  time, deadlines (service, inspection, insurance, road tax).

## Repository

| Folder | Content |
| :--- | :--- |
| `firmware/` | Arduino firmware of the tracker (ESP32 + SIMCom A76xx modem) |
| `backend/` | Node.js 24 + TypeScript (Fastify): API, authentication, realtime, tracker gateway |
| `app/` | Flutter app, Android and web |
| `hardware/` | Bill of materials of the power board, owner key fob |
| `docs/` | This documentation (GitHub Pages) |
| `docker-compose.yml`, `traefik/`, `backup/` | Production stack |

One application container plus the database: no separate broker, authentication proxy or
Redis.

## Where to start

1. [Install the server](server/install.md) with Docker Compose.
2. [Choose and build a device](devices/index.md), or use just the phone.
3. [Install the app](app/index.md) on Android (APK of the releases, Obtainium) or use the web
   one.
