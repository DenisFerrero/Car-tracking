# SIM data usage

Values measured on the real frames, including everything the SIM sends and receives for each
upload: WebSocket (6 B), TLS record (29 B), TCP/IP (40 B) and the TCP ACK of the server
(40 B).

## Size of an upload

| Configuration | Frame | On the wire | Per driving hour |
| :--- | :---: | :---: | :---: |
| Previous protocol (JSON + hex, 1 point every 5s) | ~238 B | ~339 B | ~244 KB |
| **v2, `BATCH_SIZE 1`** (position every 5s) | 35 B | 126 B | 91 KB |
| **v2, `BATCH_SIZE 3`** (default, every 15s) | 51 B | 142 B | 34 KB |
| **v2, `BATCH_SIZE 6`** (every 30s) | 75 B | 166 B | 20 KB |

With the same sampling, the default configuration uses about **7 times less** than the
previous protocol.

## Usage profiles

- **A. Commuter**: 41 driving hours a month
- **B. Professional**: 84 driving hours a month
- **C. Fleet / Taxi**: 208 driving hours a month (8 hours a day, 26 days)

| Profile | `BATCH_SIZE 1` | `BATCH_SIZE 3` | `BATCH_SIZE 6` |
| :--- | :---: | :---: | :---: |
| **A. Commuter** | 3.7 MB | **1.4 MB** | 0.8 MB |
| **B. Professional** | 7.6 MB | **2.9 MB** | 1.7 MB |
| **C. Fleet** | 18.9 MB | **7.1 MB** | 4.1 MB |

On top of these values:

| Item | Monthly usage |
| :--- | :---: |
| Connection at every ignition (TCP, WebSocket, HELLO/ACK ≈ 1.5 KB, 4 a day) | ~0.2 MB |
| Heartbeat every 4 hours (connection + 1 point) | ~0.3 MB |
| TLS (handshake ~5 KB per connection, ~29 B per frame) | ~2 MB |
| Alarms: worst case, a false alarm every 10 minutes for the whole month | ~11 MB |
| Daily update check (`AUTO_UPDATE 1`) | ~3 KB |
| A firmware update (when a version comes out) | ~1.3 MB |

**Realistic worst case** (profile C, position every 5 seconds, continuous false alarms, TLS):
**~35 MB/month**, well below a **200 MB/month** SIM. A `LIVE` session costs like
`BATCH_SIZE 1`, ~90 KB per hour.

## Optimizations

1. **Binary delta protocol**: ~8 bytes per point, against ~238 bytes of encrypted
   hex-encoded JSON.
2. **Batching**: the fixed overhead of ~85 bytes per upload (TCP/IP, WebSocket) is split among
   several points.
3. **A single write per WebSocket frame**: header and payload in the same TCP segment.
4. **Distance filter**: no points when parked or in a queue, except one every 5 minutes
   (`THRESHOLD_DISTANCE`, `STATIONARY_INTERVAL_SEC`).
5. **Compact offline queue**: when the network is back up to 40 points per frame.
6. **Reconnection with exponential back-off** (5s → 2 min): with poor coverage attempts don't
   waste data.
7. **60s keep-alive** only when nothing else is sent (Cloudflare closes idle WebSockets after
   100s).
8. **Alarm limits**: delayed arming and a pause after every alarm.

Vehicles fed by the phone don't use the SIM of the tracker: the traffic is the phone's (~1 KB
every 15 seconds while driving, JSON over HTTPS).
