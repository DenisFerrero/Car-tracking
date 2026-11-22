# Nuovo tracker

Dalla scheda appena montata al tracker che invia posizioni nell'app. Servono il server già
installato ([Installazione](../server/install.md)), una scheda del
[catalogo](index.md) e una SIM dati con il PIN disattivato o noto.

## 1. Hardware

1. Monta la scheda seguendo la sua pagina (per la LilyGO:
   [distinta e collegamenti](lilygo-t-call-a7670-v1-0.md)), con la
   [scheda di alimentazione](carrier-board.md) se va collegata alla batteria dell'auto.
2. Inserisci la SIM e collega le antenne GNSS e LTE: senza antenna il modem non registra la
   rete e il GNSS non trova i satelliti.
3. Annota l'IMEI stampato sul modulo (lo mostra anche la seriale a 115200 baud all'avvio).

## 2. Chiave e codice di abbinamento

Sul server, con l'IMEI:

```sh
docker compose exec backend node scripts/provision.ts 863820040182648 --label /tmp/label.svg
docker compose cp backend:/tmp/label.svg .
```

Stampa la chiave del tracker (`DEVICE_KEY`), il codice di abbinamento e l'etichetta SVG con
QR code, IMEI e codice. Il server non memorizza nulla: chiave e codice derivano da
`CRYPTO_MASTER_KEY` e dall'IMEI, quindi il comando si può ripetere quando serve.

## 3. Firmware

1. Copia `firmware/secrets.example.h` in `firmware/secrets.h` e inserisci `DEVICE_KEY`, APN
   dell'operatore ed eventuale PIN (e la rete WiFi se usi `CONNECTION_MODE` con WiFi).
2. In `firmware/configurations.h` imposta `BOARD`, `SERVER_HOST` (il `DOMAIN` del server) e,
   se serve, campionamento e sensori ([opzioni](../firmware/index.md#configurazione)).
3. Compila e programma via USB (scheda *ESP32 Dev Module*, partizioni con due slot OTA):

    ```sh
    arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs firmware \
      --library <LilyGo-Modem-Series>/lib/TinyGSM
    arduino-cli upload --fqbn esp32:esp32:esp32:PartitionScheme=min_spiffs -p COM5 firmware
    ```

Al primo avvio il firmware salva chiave e impostazioni di rete in NVS: i successivi
aggiornamenti a distanza usano le immagini ufficiali senza credenziali
([OTA](../firmware/index.md#aggiornamento-a-distanza-ota)).

Applica l'etichetta sul contenitore del tracker. Il codice dimostra il possesso fisico:
chi conosce solo l'IMEI non può aggiungerlo.

## 4. Abbinamento nell'app

*Dispositivi → Aggiungi → Tracker*:

1. **Etichetta**: inquadra il QR code o scrivi IMEI e codice, poi *Verifica*.
2. **Veicolo**: scegli dove lo installi.
    - *Nuovo veicolo*: nome e colore sulla mappa.
    - Un **veicolo che hai già** senza tracker (ad esempio uno creato per il
      [telefono](../app/phone-vehicles.md)): storico, km, scadenze, costi e condivisioni
      restano e d'ora in poi li alimenta il tracker.
3. **Accensione**: alimenta il tracker all'aperto, con il cielo visibile. L'app attende il
   primo collegamento in tempo reale; il primo fix GNSS può richiedere qualche minuto.
4. **Fatto**: apri il veicolo per la posizione in tempo reale.

Il tracker può anche essere acceso prima dell'abbinamento: si collega, ma le posizioni inviate
prima non vengono mostrate a nessuno.

## 5. Installazione nell'auto e verifica

- Collega l'alimentazione e, se presente, il filo sotto chiave
  (`IGNITION_ACTIVE_LEVEL`): con il quadro spento il tracker passa al risparmio energetico.
- Nella scheda *Live* controlla segnale, satelliti e tensione; prova *Localizza*.
- In *Impostazioni* scegli gli allarmi da ricevere (movimento, sollevamento, alimentazione
  staccata...).

| Problema | Controllo |
| :--- | :--- |
| L'app resta su «In attesa del primo collegamento» | Seriale: registrazione alla rete, APN, PIN; il server raggiungibile su `https://DOMAIN` |
| `invalid_pairing` | IMEI e codice dell'etichetta, `CRYPTO_MASTER_KEY` invariata dal provisioning |
| Collegato ma senza posizione | Antenna GNSS, cielo visibile; senza fix arriva la posizione della cella |
| «Il tracker appartiene a un altro account» | Il tracker è ancora di qualcuno: va rimosso da quell'account |

## Spostare il tracker su un altro veicolo

I dati appartengono al **veicolo**, non al tracker. Da *Impostazioni → Tracker* del veicolo:

- **Sposta su un altro veicolo**: scegli un tuo veicolo senza tracker o creane uno nuovo.
  Il veicolo di prima resta con il suo storico, km, scadenze, costi e condivisioni, senza
  tracker; con *Archivia questo veicolo* sparisce dalla mappa e dalla scelta del telefono
  ma resta nell'elenco dei dispositivi (in fondo). I comandi in attesa vengono annullati.
- **Rimuovi il tracker dal veicolo** (auto venduta, tracker da riusare): il veicolo resta
  senza tracker e il tracker torna libero; chiunque abbia l'etichetta può abbinarlo di
  nuovo.
- **Elimina il veicolo** (*Zona pericolosa*): cancella il veicolo con tutto il suo storico;
  il tracker torna libero.

Un veicolo archiviato si ripristina dall'interruttore *Archiviato* nelle sue impostazioni e
torna automaticamente attivo quando riceve un tracker. L'elenco *Tracker installati* mostra
quale tracker è stato nel veicolo e in quale periodo.

Il tracker non va riprogrammato: il server chiude la sua connessione e alla successiva
l'ACK porta l'id del nuovo veicolo ([protocollo](../reference/protocol.md#flusso)).
