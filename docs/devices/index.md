# Catalogo dei dispositivi

Le schede che il firmware supporta e come costruire un localizzatore con ciascuna. Il catalogo
cresce con il firmware: ogni nuova scheda ha qui la sua riga e la sua pagina.

## Schede

| Scheda | Stato | Modem / rete | GNSS | Varianti delle release | Pagina |
| :--- | :--- | :--- | :--- | :--- | :--- |
| LilyGO T-Call A7670 V1.0 | <span class="status supported">SUPPORTATA</span> | SIMCom A7670E/SA/G, LTE Cat-1 (solo 4G) | Integrato nelle versioni *-FASE*, esterno con l'A7670G | `lilygo-sim`, `lilygo-wifi-sim` | [Dettagli](lilygo-t-call-a7670-v1-0.md) |
| LilyGO T-Call A7670 V1.1 | <span class="status planned">PREVISTA</span> | Come la V1.0, pin diversi | Come la V1.0 | — | Serve un file di scheda proprio |

**Stato**: *supportata* = nel firmware, compilata dalla CI, immagini ufficiali nelle release;
*sperimentale* = nel firmware, senza immagini ufficiali; *prevista* = non ancora nel firmware.

## Accessori

| Accessorio | A cosa serve | Pagina |
| :--- | :--- | :--- |
| Scheda di alimentazione | 12V dell'auto, protezioni, batteria tampone, misura della tensione, sotto chiave isolato | [Dettagli](carrier-board.md) |
| Portachiavi del proprietario | Ignora gli allarmi di movimento quando il proprietario è vicino | [Dettagli](owner-beacon.md) |
| Sensori LIS3DH e BMP390 | Movimento e sollevamento (antifurto), pressione e temperatura | Nella pagina della scheda |

## Senza hardware

Il telefono Android può fare da localizzatore per la persona o per un veicolo, con viaggi,
costi e scadenze ma senza antifurto: vedi [Telefono e veicoli](../app/phone-vehicles.md).

## Varianti delle immagini ufficiali

Le release contengono un'immagine `firmware-<variante>.bin` per variante. Il tracker accetta
gli aggiornamenti solo della propria variante (`FIRMWARE_VARIANT`), quindi la prima
installazione via USB va fatta con una build personale della stessa variante.

| Variante | Scheda | Connessione |
| :--- | :--- | :--- |
| `lilygo-sim` | LilyGO T-Call A7670 V1.0 | Solo SIM (LTE) |
| `lilygo-wifi-sim` | LilyGO T-Call A7670 V1.0 | WiFi quando disponibile, altrimenti SIM |

## Aggiungere una scheda al firmware

1. Scrivi `firmware/boards/<scheda>.h` con tutte le macro `BOARD_*` elencate in
   `firmware/boards/lilygo_t_call_a7670_v1_0.h` (nome, famiglia del modem, GNSS, pin).
2. Registrala in `firmware/board.h`.
3. Se il modem è di una famiglia nuova, aggiungi `firmware/modem_<famiglia>.cpp` che
   implementa `firmware/modem.h`.
4. Per le release: `firmware/release/<variante>.h` e la variante nella matrice di
   `.github/workflows/release.yml`.
5. Documentala qui: riga nella tabella, pagina con distinta, collegamenti e note (vedi
   `CLAUDE.md`).
