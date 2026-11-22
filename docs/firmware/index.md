# Firmware

Firmware Arduino per ESP32 (`firmware/`): GNSS con campionamento adattivo, invio a lotti su
WebSocket cifrato, coda offline in flash, antifurto, deep sleep, aggiornamenti a distanza. La
scheda si sceglie con `BOARD` in `firmware/configurations.h` (vedi il
[catalogo](../devices/index.md)).

## Configurazione

| File | Contenuto |
| :--- | :--- |
| `firmware/configurations.h` | Scheda, server, campionamento, sensori, opzioni (versionato) |
| `firmware/config_defaults.h` | Valori predefiniti di ogni opzione |
| `firmware/secrets.h` | Chiave del tracker, WiFi, APN, PIN (da `secrets.example.h`, escluso da git) |
| `firmware/release/` | Configurazione delle immagini ufficiali (nessuna credenziale) |

Principali opzioni: `SERVER_HOST` (= `DOMAIN`), `CONNECTION_MODE` (SIM, WiFi, WiFi + SIM),
`BATCH_SIZE`, `THRESHOLD_DISTANCE`, `IGNITION_ACTIVE_LEVEL`, `VEHICLE_VOLTAGE_SENSE`,
`POWER_GOOD_SENSE`, `GNSS_SOURCE`, `OWNER_TAG`, `AUTO_UPDATE`.

## Provisioning

Ogni tracker ha una chiave propria, derivata da `CRYPTO_MASTER_KEY` e dal suo IMEI (stampato
sul modulo o mostrato sulla seriale all'avvio):

```sh
docker compose exec backend node scripts/provision.ts 863820040182648 --label /tmp/label.svg
```

```text
IMEI:          863820040182648
Pairing code:  7KQ2-M9XA
QR code:       CT1:863820040182648:7KQ2M9XA

firmware/secrets.h:
#define DEVICE_KEY "3f9a..."
```

1. Copia `firmware/secrets.example.h` in `firmware/secrets.h` e inserisci `DEVICE_KEY` e APN.
   Non serve registrare nulla sul server: il backend ricalcola la chiave dall'IMEI.
2. Regola `firmware/configurations.h` (scheda, `SERVER_HOST`, porta 443, campionamento) e
   programma la scheda.
3. Stampa l'etichetta (`--label`, SVG con QR code, IMEI e codice) e applicala al tracker.
4. L'utente apre **Dispositivi → Aggiungi**: la procedura guidata legge il QR (o IMEI e codice
   a mano), chiede il veicolo (nuovo, con nome e colore, o uno senza tracker che ha già) e
   attende il primo collegamento. Il codice dimostra il possesso fisico: conoscere solo l'IMEI
   non basta. La procedura completa, dall'hardware all'auto, è in
   [Nuovo tracker](../devices/new-device.md).

Al primo avvio il firmware salva in NVS la chiave e le impostazioni di rete (server, WiFi, APN,
PIN): le immagini senza credenziali le riprendono da lì.

## Aggiornamento a distanza (OTA)

### Dalle release di GitHub

Con `GITHUB_REPO=<proprietario>/<repository>` il backend legge ogni 6 ore l'ultima release.
Le immagini `firmware-<variante>.bin` allegate dalla pipeline entrano fra gli aggiornamenti
disponibili (verificate con lo SHA-256 calcolato da GitHub) e i proprietari dei tracker di
quella variante ricevono la notifica *Nuovo firmware*. Controllo immediato:
`POST /api/admin/releases/check` (amministratore).

Le immagini ufficiali sono compilate con `SERVER_HOST ""` e senza chiave, WiFi o APN
(`firmware/release/`): usano le impostazioni salvate in NVS dalla prima installazione. La prima
installazione resta quindi via USB con una build personale della stessa variante
(`FIRMWARE_VARIANT "lilygo-sim"` o `"lilygo-wifi-sim"`).

### Aggiornamenti automatici

Le build con `AUTO_UPDATE 1` (le immagini ufficiali) una volta al giorno, dopo l'ACK, mandano
un frame `UPDATE_CHECK` (~100 B, ~3 KB al mese). Se il proprietario non li ha disattivati
(*Impostazioni → Aggiornamenti automatici*) il server offre la versione più recente della
variante e il tracker la installa da solo (~1,3 MB di SIM per aggiornamento). Un'immagine che
ha già fallito su quel tracker non viene riproposta.

**Firmware personalizzati**: lasciano `AUTO_UPDATE 0` e non chiedono mai aggiornamenti, così
una versione modificata non viene sostituita da quella ufficiale; l'installazione manuale resta
possibile.

### A mano, senza GitHub

1. Compila con `DEVICE_KEY` tutta a zero, la nuova `FIRMWARE_VERSION` e la `FIRMWARE_VARIANT`
   dei tracker, con uno schema di partizioni con due slot OTA.
2. Caricala sul server:
   ```sh
   docker compose cp build/firmware.ino.bin backend:/tmp/fw.bin
   docker compose exec backend node scripts/firmware.ts /tmp/fw.bin 2.4.0 default "Note"
   ```
3. Il proprietario apre *Impostazioni* del tracker → *Installa*.

### Come avviene

Alla connessione il tracker riceve l'offerta (firmata con la sua chiave), scarica l'immagine a
blocchi da 1 KB, verifica lo SHA-256, la scrive nello slot libero e si riavvia. Il nuovo
firmware diventa definitivo solo al primo ACK del server: se non riesce a collegarsi il
bootloader torna alla versione precedente (stato *non applicato*). Il download dura al massimo
`OTA_MAX_SEC` (15 minuti) per ciclo e riprende dal punto raggiunto.

## Gestione energetica e antifurto

| Evento | Comportamento |
| :--- | :--- |
| Quadro acceso | Campionamento ogni 5 s, invio a lotti, coda offline senza rete |
| Quadro spento (dopo 5 s) | Posizione di parcheggio e coda, poi deep sleep |
| Ogni 4 ore | Risveglio, posizione di standby (heartbeat), di nuovo in deep sleep |
| Movimento (LIS3DH) | Allarme: tracciamento per 60 s, esteso finché l'auto si sposta (max 15 min) |
| Auto sollevata | Inclinazione oltre 4° rispetto al parcheggio (carro attrezzi, cric) |
| Alimentazione staccata | Con la [scheda di alimentazione](../devices/carrier-board.md): allarme e tracciamento a batteria |
| Portachiavi vicino | Con `OWNER_TAG` il movimento è ignorato ([dettagli](../devices/owner-beacon.md)) |
| Antifurto in pausa | Comando `ANTITHEFT`: nessun allarme fino alla scadenza |

- Il rilevamento di movimento si arma 3 minuti dopo lo spegnimento e resta in pausa 10 minuti
  dopo un allarme, per limitare i dati in caso di falsi allarmi.
- Senza fix GPS heartbeat e allarmi usano l'ultima posizione nota, marcata *stale*, con la
  cella servente.

## Dati aggiuntivi

`uplinkQueueExtra("{\"rpm\":820}")` mette in coda un oggetto JSON (al massimo 400 byte) letto
da un'altra scheda del veicolo; viene inviato appena la connessione è pronta (frame `EXTRA`,
vedi il [protocollo](../reference/protocol.md#dati-aggiuntivi-extra)). La lettura dalla scheda
esterna (es. seriale) è da scrivere: protocollo, backend e app non cambiano quando si
aggiungono campi.

## TLS

Il tracker si collega in `wss://` sulla porta 443 e verifica il certificato con le CA radice di
`firmware/certificates.h` (Let's Encrypt, Google Trust Services, SSL.com). Il file si rigenera
con `npm run ca-bundle` (cartella `backend`).
