# LilyGO T-Call A7670 V1.0

<span class="status supported">SUPPORTATA</span> · file di scheda
`firmware/boards/lilygo_t_call_a7670_v1_0.h` · driver `firmware/modem_a76xx.cpp` · varianti
`lilygo-sim`, `lilygo-wifi-sim`

ESP32 con modem SIMCom A7670 (LTE Cat-1). Il firmware usa solo il 4G (`MODEM_LTE_ONLY`).

!!! warning "GNSS"
    Solo le varianti **A7670E-FASE** e **A7670SA-FASE** del modem hanno il GNSS integrato
    (verificabile con `AT+SIMCOMATI`). La variante globale **A7670G** non lo ha: serve un
    modulo GNSS esterno (`GNSS_SOURCE_EXTERNAL`, vedi la
    [scheda di alimentazione](carrier-board.md#7-gnss-esterno-opzionale-non-montato)).

## Distinta dei materiali

### Componenti principali

| # | Componente | Ruolo | Q.tà | Prezzo indicativo |
| :---: | :--- | :--- | :---: | :---: |
| 1 | **LilyGO T-Call A7670 V1.0** | ESP32 con modem LTE e GNSS integrato (versioni *-FASE*) | 1 | ~€ 25–35 |
| 2 | **BMP390** | Pressione e temperatura (I2C) | 1 | ~€ 5–10 |
| 3 | **LIS3DH** | Accelerometro a basso consumo (I2C), risveglio per movimento su INT1 | 1 | ~€ 3–8 |

### Alimentazione e protezione (montaggio base)

| # | Componente | Ruolo | Q.tà | Prezzo indicativo |
| :---: | :--- | :--- | :---: | :---: |
| 4 | **Convertitore step-down 12V → 5V, ≥ 1A** | Alimenta il T-Call dall'impianto dell'auto | 1 | ~€ 2–5 |
| 5 | **Portafusibile in linea + fusibile 1A** | Protezione sul +12V | 1 | ~€ 1–3 |
| 6 | **Optoisolatore PC817** *(consigliato)* | Isola il sotto chiave dal GPIO 32 | 1 | ~€ 0,50–1 |
| 7 | **Resistenza 1 kΩ** | Limita la corrente nel LED dell'optoisolatore | 1 | ~€ 0,10 |
| — | *Alternativa: resistenze 12 kΩ + 3,3 kΩ* | Partitore per il sotto chiave senza optoisolatore | 1+1 | ~€ 0,20 |

Per un'installazione definitiva, con batteria tampone e protezioni dal *load dump*, usa la
[scheda di alimentazione](carrier-board.md).

### Connettività e accessori

| # | Componente | Ruolo | Q.tà | Prezzo indicativo |
| :---: | :--- | :--- | :---: | :---: |
| 8 | **SIM dati IoT/M2M** | Bastano 100-200 MB al mese (vedi [consumo dati](../reference/data-usage.md)) | 1 | ~€ 5–15/anno |
| 9 | Antenna GNSS esterna *(opzionale)* | Ricezione migliore sotto il cruscotto | 1 | ~€ 3–8 |
| 10 | Antenna LTE esterna *(opzionale)* | Copertura debole | 1 | ~€ 3–8 |
| 11 | Cavi, millefori, scatola | Montaggio | — | ~€ 7–20 |

**Costo stimato**: ~€ 40–55 nella configurazione minima, ~€ 55–80 con optoisolatore, antenne
e scatola (meno di € 40 dai marketplace asiatici). Operatori IoT come Onomondo, 1NCE o Tele2
IoT offrono piani da pochi euro l'anno.

## Collegamenti

| Linea | Pin del sensore | Pin del T-Call | Note |
| :--- | :--- | :--- | :--- |
| Alimentazione sensori | VCC / VIN | **3V3** | 3,3V |
| Massa | GND | **GND** | Comune |
| I2C dati | SDA | **GPIO 21** | BMP390 + LIS3DH |
| I2C clock | SCL | **GPIO 22** | BMP390 + LIS3DH |
| Allarme LIS3DH | INT1 | **GPIO 33** | Risveglio per movimento |
| Sotto chiave | segnale | **GPIO 32** | Via optoisolatore o partitore |
| PGOOD *(scheda di alimentazione)* | — | GPIO 34 | Alimentazione staccata |
| Tensione batteria *(scheda di alimentazione)* | — | GPIO 35 | ADC1 |

Non usare GPIO 4, 12, 13, 14, 25, 26 e 27 (modem e LED) né 16/17 (PSRAM).

```text
+------------------+          +------------------+
|   LIS3DH (Acc.)  |          |   BMP390 (Baro.) |
+--+---+---+---+---+          +--+---+---+---+---+
   |   |   |   |                 |   |   |   |
  3V3 GND SDA SCL               3V3 GND SDA SCL
   |   |   |   +--------+--------|---|---|---+--> GPIO22
   |   |   +------------|--------|---|---+------> GPIO21
   +---|----------------|--------+---|----------> 3V3
       +----------------|------------+----------> GND
  INT1 -----------------+-----------------------> GPIO33 (risveglio antifurto)

  Sotto chiave (+12V) --[ optoisolatore ]-------> GPIO32 (accensione)
```

## Ingresso sotto chiave (+12V → 3,3V)

L'ESP32 accetta al massimo 3,3V sui GPIO: la tensione dell'auto (12-14,4V) lo brucia.

**Opzione A, optoisolatore (consigliata)**: +12V sotto chiave → resistenza **1 kΩ** → anodo
del LED del PC817, catodo a massa. Lato ESP32: collettore al GPIO 32, emettitore a GND, con
il pull-up interno. Il segnale è attivo basso: `IGNITION_ACTIVE_LEVEL LOW` (il firmware
abilita il pull-up anche durante il deep sleep). La [scheda di alimentazione](carrier-board.md)
usa invece un inseguitore di emettitore, attivo alto.

**Opzione B, partitore (economica)**: R1 **12 kΩ** verso il +12V, R2 **3,3 kΩ** verso massa,
punto centrale al GPIO 32 con `IGNITION_ACTIVE_LEVEL HIGH`: circa 2,6V a 12V e 3,1V a 14,4V.
Con 10 kΩ al posto di 12 kΩ si arriverebbe a 3,57V, al limite assoluto dell'ESP32.

## Firmware

```c
// firmware/configurations.h
#define BOARD BOARD_LILYGO_T_CALL_A7670_V1_0
```

- Compilazione con la libreria TinyGSM di LilyGO (repository
  [Xinyuan-LilyGO/LilyGo-Modem-Series](https://github.com/Xinyuan-LilyGO/LilyGo-Modem-Series),
  cartella `lib/TinyGSM`), commentando `COMPILING_WITH_STANDARD_TINYGSM`. Scheda *ESP32 Dev
  Module*, schema di partizioni con due slot OTA (predefinito o *Minimal SPIFFS*).
- Configurazione, provisioning e aggiornamenti: vedi [Firmware](../firmware/index.md).

## Versione V1.1

La V1.1 del T-Call usa pin diversi e i GPIO 32/33 sono occupati dal modem: serve un proprio
file di scheda. Il firmware dà errore di compilazione se la configurazione non è compatibile.
