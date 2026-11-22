# Scheda di alimentazione e I/O (carrier board)

Scheda millefori da affiancare al LilyGO T-Call A7670 V1.0. Collega il tracker
all'impianto a 12V dell'auto e aggiunge:

- protezione da sovratensioni (load dump), inversione di polarità e cortocircuiti
- batteria tampone: il tracker continua a funzionare se il ladro stacca l'alimentazione
  e lo segnala (evento `POWER_LOST`)
- misura della tensione della batteria dell'auto (eventi `LOW_BATTERY`)
- ingresso sotto chiave isolato con optoaccoppiatore
- connettori per accelerometro LIS3DH e barometro BMP390
- predisposizione per un modulo GNSS esterno (opzionale, non montato)

Le funzioni sono già nel firmware, disattivate in `firmware/configurations.h`
(vedi [Abilitazione nel firmware](#abilitazione-nel-firmware)).

> Progetto non ancora realizzato né collaudato: verifica ogni collegamento con il
> multimetro prima di collegare la scheda, e la prima accensione fallo con un
> alimentatore da banco limitato in corrente (12V, 0,5A) invece della batteria dell'auto.

---

## Perché questa architettura

Il T-Call A7670 V1.0 **non ha un ingresso batteria**: si alimenta solo a 5V da USB-C
(riportato sul pin `VBUS` dell'header). Il 5V alimenta un buck SY8089 (4,2V per il
modem) e un LDO ME6217 (3,3V per l'ESP32). Entrambi funzionano anche con una tensione di
ingresso da 3,5V a 5V, quindi `VBUS` può essere alimentato direttamente dall'uscita di un
caricatore con *power path* (load sharing):

- quadro acceso o spento, con l'auto collegata: l'uscita del caricatore vale 4,4V e
  intanto la batteria si ricarica
- alimentazione staccata: l'uscita passa senza interruzioni alla batteria (3,5-4,2V)

```text
 +30 (batteria) ──F1 2A──┬──────────────┬──D1──┬── C1/C2 ──[ BUCK 5V ]──[ bq24074 ]──OUT 4.4V──┬── VBUS T-Call
                         │              │      │            U1            U2  │            C5   │
                       TVS1          R1/R2                                 LIPO │                 ├── 3V3 (dal T-Call) → sensori
                     5KP24A        470k/100k                             18650 + NTC              │
                         │              │                                  PGOOD ─────────────────┼── GPIO 34
 GND (massa) ────────────┴──────────────┴──────────────────────────────────┴──────────────────────┴── GND
                                        └──────────────────────────────────────────────────────────── GPIO 35 (ADC)

 +15 (sotto chiave) ──F2 1A──D2──R3 4.7k──[ PC817 LED ]── GND
                                           [ PC817 transistor ]: collettore 3V3, emettitore → GPIO 32 (+ R4 10k verso GND)
```

---

## Schema per blocchi

### 1. Ingresso e protezioni

```text
+30 ──[F1 2A, portafusibile in linea sul cablaggio]──┬──────────── nodo VPROT ──[D1 SB3100 →]── VIN_BUCK
                                                     │                                              │
                                              TVS1 5KP24A                               C1 100µF 63V (105°C)
                                              (catodo su VPROT)                         C2 1µF 100V ceramico
                                                     │                                              │
GND ─────────────────────────────────────────────────┴──────────────────────────────────────────────┘
```

| Componente | Scelta | Motivo |
| :--- | :--- | :--- |
| **F1** | Fusibile lamellare 2A in un portafusibile in linea, prelevato con un *add-a-fuse* da un circuito sempre alimentato | Protegge il cablaggio dell'auto da cortocircuiti. È anche il "fusibile sacrificale" della TVS |
| **TVS1** | **5KP24A** (5000 W, standoff 24V, clamping ~39V) | Su un'auto vecchia l'alternatore può non avere la soppressione del *load dump*: staccando la batteria a motore acceso si possono avere 80-100V per centinaia di ms. Lo standoff di 24V tollera l'avviamento con booster a 24V. Con polarità invertita conduce in diretta e brucia F1 |
| **D1** | **SB3100** (Schottky 3A 100V) | Protezione dall'inversione di polarità senza consumo a riposo, caduta di circa 0,4V |
| **C1/C2** | 100µF 63V elettrolitico low-ESR **105°C**, 1µF 100V ceramico | Riserva per i disturbi e i cali brevi. In auto servono componenti per alte temperature |

La tensione massima a valle della TVS (circa 39V durante un picco) resta sotto i 50V
massimi del regolatore.

### 2. Regolatore 5V

**U1: Pololu D36V28F5** (ingresso 5,3-50V, uscita 5V fino a 3,2A, protezione
dall'inversione integrata). Uscita sull'ingresso `VBUS` del caricatore.

- Durante l'avviamento la tensione può scendere a 6-8V (anche sotto, su batterie vecchie):
  il regolatore si spegne ma la batteria tampone alimenta il tracker senza interruzioni.
- Consumo a riposo: massimo 3 mA secondo il costruttore. Insieme al resto della scheda,
  stimo 3-5 mA a vuoto, circa 2-4 Ah al mese: va bene per un'auto usata regolarmente
  (una batteria da 45 Ah perde meno del 10% in un mese). **Misuralo** a scheda finita.

### 3. Batteria tampone e caricatore

**U2: Adafruit bq24074** (Universal USB / DC / Solar Lithium charger, prodotto 4755).

| Impostazione | Valore | Come |
| :--- | :--- | :--- |
| Corrente di carica | **500 mA** | Taglia la pista del ponticello 1.0A e chiudi quello da 0.5A: meno calore e meno carico sul regolatore |
| Termistore | NTC 10k incollato alla cella | Taglia il ponticello `THERM` e collega l'NTC tra `THERM` e GND. Il caricatore sospende la carica fuori dall'intervallo di temperatura sicuro (circa 0-50°C) |
| Uscita | `OUT` → `VBUS` del T-Call | Al massimo 4,4V con l'auto collegata, la tensione della batteria senza |
| Stato | `PGOOD` → GPIO 34 | Open drain, basso con l'alimentazione presente. Pull-up R5 470k verso 3V3 (il GPIO 34 non ha pull-up interni) |

**Batteria: cella 18650 Li-ion protetta** (con circuito di protezione integrato), per
esempio Samsung 35E, LG MJ1 o Panasonic NCR18650B nella versione protetta, in un
portabatterie con fili.

- **Temperatura**: d'estate l'abitacolo supera i 70°C. Una cella cilindrica in acciaio è
  più robusta di una LiPo a sacchetto, il termistore blocca la carica quando fa caldo, e
  la scarica è ammessa fino a circa 60°C. **Monta la scheda in basso, sotto il cruscotto o
  sotto un sedile, mai esposta al sole**. Una LiFePO4 sarebbe più sicura al calore ma
  richiede un caricatore diverso (3,6V invece di 4,2V).
- **Autonomia** senza l'auto (stime, da verificare): 10-15 ore di tracciamento continuo, o
  diverse settimane in deep sleep con gli heartbeat.
- **Picchi del modem**: il firmware usa solo il 4G (`MODEM_LTE_ONLY`), dove i picchi
  restano intorno a 1A. In 2G (fallback con `MODEM_LTE_ONLY 0`) il modem assorbe impulsi
  fino a 2A, oltre gli 1,5A del caricatore. **C5, 2200µF 6,3V low-ESR, va saldato vicino
  al pin `VBUS` del T-Call** in ogni caso: costa poco e copre anche i transitori di
  accensione del modem.

> Non collegare l'USB-C del T-Call al PC mentre la scheda è alimentata: le due sorgenti
> sarebbero in parallelo. Per programmare il firmware scollega il connettore `VBUS` della
> carrier (o tutta la carrier).

### 4. Misura della tensione della batteria

```text
VPROT (prima di D1) ──R1 470k 1%──┬── GPIO 35
                                  │
                              R2 100k 1%  C3 100nF
                                  │        │
GND ──────────────────────────────┴────────┘
```

- Rapporto (470k + 100k) / 100k = 5,7: 14,4V diventano 2,53V, misurabili fino a circa 17V.
- Consumo continuo 25 µA. C3 filtra i disturbi e fornisce la carica al campionamento
  dell'ADC, nonostante l'alta impedenza del partitore.
- Durante un picco limitato dalla TVS (39V) il pin riceve circa 75 µA attraverso R1, assorbiti
  dai diodi di protezione dell'ESP32.
- **GPIO 35 appartiene all'ADC1**: l'ADC2 non funziona con il WiFi attivo.
- Taratura: misura la batteria con un multimetro e imposta
  `VEHICLE_VOLTAGE_CALIBRATION = tensione reale / tensione letta`.

### 5. Ingresso sotto chiave (optoaccoppiatore)

```text
+15 ──F2 1A──D2 1N4007 →──R3 4.7k 1W──[A  PC817  K]── GND

3V3 ──[C  PC817  E]──┬── GPIO 32
                     │
                 R4 10k  C4 100nF
                     │    │
GND ─────────────────┴────┘
```

- **Uscita attiva alta** (inseguitore di emettitore): con il quadro acceso il GPIO 32
  legge circa 3,1V, quindi resta `IGNITION_ACTIVE_LEVEL HIGH` e in deep sleep non serve il
  pull-up interno.
- Corrente nel LED: 2,7 mA a 14,4V, 1,5 mA a 9V (avviamento). Con un CTR minimo del 50% il
  transistor fornisce più dei 0,33 mA necessari.
- D2 protegge dall'inversione. R3 da 1W regge i picchi di load dump (fino a 1,6W per 400 ms).
- L'isolamento galvanico tiene i disturbi dell'impianto lontani dall'ESP32.

### 6. Sensori

| Modulo | Collegamenti |
| :--- | :--- |
| LIS3DH (es. Adafruit 2809) | 3V3, GND, SDA → GPIO 21, SCL → GPIO 22, **INT1 → GPIO 33** |
| BMP390 (es. Adafruit 4816) | 3V3, GND, SDA → GPIO 21, SCL → GPIO 22 |

Monta l'accelerometro **rigidamente** sulla scheda e la scheda rigidamente all'auto: il
rilevamento dell'auto sollevata confronta l'inclinazione con quella del parcheggio
(soglia 4°), quindi una scheda libera di muoversi genera falsi allarmi.

### 7. GNSS esterno (opzionale, non montato)

Serve con un modem senza GNSS, per esempio l'**A7670G** (bande LTE di tutto il mondo,
nessun GNSS integrato), oppure per ottenere un fix più rapido e preciso.

```text
3V3 ──[S  Q1 AO3401A  D]──── VCC modulo GNSS
           G
           ├── R6 100k ── 3V3      (spento di default)
           └── GPIO 23             (LOW = acceso)

GPIO 18 (RX ESP32) ←── TX modulo
GPIO 19 (TX ESP32) ──→ RX modulo
3V3 sempre acceso ──── V_BCKP modulo (se presente): mantiene effemeridi e orologio,
                       fix in 1-2 secondi al risveglio invece di 30 o più
```

- Modulo consigliato: **u-blox M10** (MAX-M10S o moduli simili), con GPS, Galileo, GLONASS
  e BeiDou in contemporanea e circa 25 mW. Antenna attiva verso il cielo (sotto il
  cruscotto, non sotto un parabrezza atermico metallizzato).
- In alternativa il Quectel L76K, usato da LilyGO nelle versioni "with GPS".

---

## Collegamenti all'header del T-Call V1.0

Controlla sempre i nomi serigrafati sulla scheda. Non usare GPIO 4, 12, 13, 14, 25, 26
e 27 (modem e LED) né 16/17 (PSRAM).

| Carrier | T-Call | Note |
| :--- | :--- | :--- |
| `OUT` del bq24074 (via C5) | `VBUS` | Filo corto da almeno 0,5 mm² |
| GND | `GND` | Due fili, vicino a VBUS |
| 3V3 (sensori, collettore PC817, R5, R6) | `3V3` | Solo carichi piccoli (< 100 mA) |
| Sotto chiave | GPIO 32 | `PIN_IGNITION_SENSE` |
| LIS3DH INT1 | GPIO 33 | `PIN_ACCEL_INT` |
| PGOOD | GPIO 34 | `PIN_POWER_GOOD` |
| Partitore tensione | GPIO 35 | `PIN_VEHICLE_VOLTAGE` |
| I2C | GPIO 21 (SDA), 22 (SCL) | LIS3DH e BMP390 |
| GNSS (opz.) | GPIO 18, 19, 23 | `GNSS_RX_PIN`, `GNSS_TX_PIN`, `GNSS_POWER_PIN` |

**T-Call V1.1**: usa pin diversi e i GPIO 32/33 sono occupati dal modem. Il firmware dà
errore di compilazione se la configurazione non è compatibile.

---

## Cablaggio in auto

| Filo | Dove | Sezione |
| :--- | :--- | :--- |
| +30 permanente | *Add-a-fuse* su un fusibile sempre alimentato (es. luci interne), F1 2A | 0,75 mm² |
| +15 sotto chiave | *Add-a-fuse* su un fusibile alimentato solo con il quadro acceso (es. autoradio), F2 1A | 0,5 mm² |
| Massa | Bullone della carrozzeria, con occhiello | 0,75 mm² |

- Morsettiera a vite o connettore a innesto (es. Molex Micro-Fit) con fissaggio dei cavi,
  per poter staccare la scheda.
- Scatola in ABS, fissata in un punto nascosto e lontano da fonti di calore. Antenna LTE
  lontana da superfici metalliche, antenna GNSS rivolta verso il cielo.

---

## Montaggio e collaudo

Montaggio su millefori a passo 2,54 mm, circa 7 × 9 cm:

1. Blocco di ingresso (F1 escluso), TVS, D1 e C1/C2. Con l'alimentatore da banco a 12V,
   0,5A: verifica la polarità su VIN_BUCK e che, invertendo i fili, la corrente vada in
   limitazione (la TVS conduce).
2. Regolatore U1: 5,0V in uscita, a vuoto.
3. Caricatore U2 senza batteria: impostazioni, poi 4,4V su `OUT`. Collega la batteria:
   il LED CHG si accende. Staccando il 12V, `OUT` deve seguire la batteria senza
   interruzioni e `PGOOD` passare da 0V a 3,3V (con il T-Call collegato).
4. Partitore: 12,0V in ingresso → circa 2,1V su GPIO 35.
5. Optoaccoppiatore: 12V sul +15 → circa 3,1V su GPIO 32, 0V senza.
6. T-Call collegato, firmware con le opzioni abilitate: controlla sulla seriale tensione,
   eventi e risvegli. Misura il consumo in deep sleep sul +30.

---

## Abilitazione nel firmware

In `firmware/configurations.h`:

```c
#define VEHICLE_VOLTAGE_SENSE 1     // partitore su GPIO 35
#define VEHICLE_VOLTAGE_CALIBRATION 1.0f  // dopo la taratura con il multimetro
#define POWER_GOOD_SENSE 1          // PGOOD del bq24074 su GPIO 34

// Solo con il modulo GNSS esterno
#define GNSS_SOURCE GNSS_SOURCE_EXTERNAL
#define GNSS_POWER_PIN BOARD_GNSS_POWER_PIN  // 23
```

I pin predefiniti di questo progetto sono nel file della scheda,
`firmware/boards/lilygo_t_call_a7670_v1_0.h` (`BOARD_PIN_*`). Per spostarne uno basta
definire in `configurations.h` il corrispondente `PIN_*` (es. `PIN_VEHICLE_VOLTAGE`).
`IGNITION_ACTIVE_LEVEL` resta `HIGH` con l'optoaccoppiatore di questo progetto.

---

## Portachiavi del proprietario (opzionale)

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

---

## Distinta componenti

Il file [bom.csv](bom.csv) contiene la distinta completa. Costo indicativo della carrier,
esclusi T-Call, sensori e GNSS opzionale: **40-50 €**, di cui circa 20 € per regolatore e
caricatore e 10 € per la batteria.
