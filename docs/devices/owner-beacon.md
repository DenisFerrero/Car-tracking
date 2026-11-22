# Portachiavi del proprietario

<span class="status experimental">PROGETTO</span> · opzionale · sketch in `hardware/owner-beacon/`

Con `OWNER_TAG` il tracker, al risveglio per un movimento, cerca via Bluetooth il
portachiavi del proprietario per 4 secondi e, se lo trova, ignora l'allarme (inclinazione
e alimentazione staccata danno sempre l'allarme).

**Samsung SmartTag, AirTag e simili non sono utilizzabili**: per privacy cambiano
indirizzo Bluetooth e identificativi ogni 15 minuti circa, con chiavi note solo
all'ecosistema del produttore. Restano due possibilità:

| `OWNER_TAG` | Portachiavi | Sicurezza |
| :---: | :--- | :--- |
| 1 | Qualsiasi tag BLE con indirizzo fisso (beacon iBeacon/Eddystone economici, ~5€). L'indirizzo, letto con l'app *nRF Connect*, va in `OWNER_TAG_ADDRESS` | Bassa: l'indirizzo si legge da lontano e si clona con un telefono |
| 2 | Beacon di questo progetto, `hardware/owner-beacon` | Codice a rotazione HMAC-SHA256 con chiave condivisa (`OWNER_TAG_KEY` / `TAG_KEY`), un codice registrato non vale una seconda volta |

Beacon (`OWNER_TAG 2`):

- **Seeed XIAO nRF52840** (~10€), core *Seeed nRF52 Boards* (non la versione mbed),
  sketch `hardware/owner-beacon/owner-beacon.ino`; copia `secrets.example.h` in
  `secrets.h` con la stessa chiave del tracker (`openssl rand -hex 32`)
- batteria LiPo 3,7V 100-150 mAh sui pad `BAT+`/`BAT-`, ricaricata dall'USB-C della XIAO
- guscio portachiavi stampato in 3D o una scatoletta 30×25×10 mm
- advertising ogni secondo, codice nuovo ogni 30 secondi. Il contatore è salvato in flash
  a blocchi di un giorno: dopo un reset salta in avanti e non si ripete mai

> Il consumo del beacon e la portata reale in auto vanno misurati: non sono stati
> verificati. Con `TX_POWER` si riduce la portata (es. -8 dBm, solo vicino alla portiera).
> Lo stack Bluetooth occupa ~740 KB di flash sul tracker: con `OWNER_TAG` attivo scegli lo
> schema di partizioni *Minimal SPIFFS (1.9MB APP with OTA/190KB SPIFFS)*; la coda offline
> si riduce da sola a circa 1200 punti.
