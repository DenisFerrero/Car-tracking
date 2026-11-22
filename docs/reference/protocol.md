# Protocollo binario (v2)

Ogni messaggio è un frame binario cifrato con **ChaCha20-Poly1305** (RFC 8439). La specifica
completa è in `backend/src/protocol/protocol.ts`, l'implementazione del firmware in
`firmware/protocol.cpp`.

| Campo | Dimensione | Note |
| :--- | :--- | :--- |
| Header | 1 B | versione (4 bit) + tipo: HELLO, TELEMETRY, ACK, COMMAND, COMMAND_RESULT, FW_*, UPDATE_CHECK, EXTRA |
| Dispositivo | 8 B / 1-2 B / 0 | HELLO: IMEI; TELEMETRY, COMMAND_RESULT, UPDATE_CHECK ed EXTRA: id (varint); ACK e COMMAND: nessuno (lo identifica la connessione) |
| Contatore | 4 B | mai ripetuto con la stessa chiave (riservato a blocchi in NVS) |
| Timestamp | 4 B | secondi UNIX del primo punto |
| Payload | variabile | cifrato, header usato come AAD (autenticato) |
| Tag | 8 B | Poly1305 troncato (probabilità di falsificazione 2⁻⁶⁴) |

Nel payload TELEMETRY i punti sono codificati come **differenze dal punto precedente** (varint
zigzag): coordinate a 1e-5 gradi (~1 m), altitudine in metri, pressione in decimi di hPa,
temperatura in decimi di °C, velocità in km/h. Seguono, se presenti, satelliti, potenza del
segnale (dBm), tensione della batteria dell'auto, eventi (movimento, auto sollevata,
alimentazione staccata, batteria scarica), cella servente e il flag *stale*. Un punto completo
costa ~22 byte, i successivi ~8-10 byte.

## Canale

Un WebSocket per tracker su `/tracker`, un frame per messaggio binario. Ogni connessione
comincia con l'HELLO (entro 10 s), il server risponde con l'ACK e poi manda i comandi in
attesa; seguono telemetria, esiti dei comandi, la richiesta giornaliera di aggiornamento
(`UPDATE_CHECK`, senza payload) e i dati aggiuntivi (`EXTRA`). Keepalive con i ping WebSocket
(`KEEP_ALIVE_SEC`, 60 s quando il server tace); il server chiude le connessioni silenziose da 3
minuti.

## Dati aggiuntivi (EXTRA)

Il payload è un oggetto JSON in UTF-8 (al massimo 400 byte sul firmware, 50 campi, valori
qualsiasi anche annidati); il timestamp è l'ora della lettura (senza ora valida il server usa
quella di ricezione). Costo: ~95 byte sulla rete più il JSON.

## Comandi verso il tracker

I comandi restano in attesa nel database. Appena il tracker è collegato e ha ricevuto l'ACK, il
backend gli invia un frame COMMAND con tutti i comandi in attesa; il tracker li applica una
sola volta (contatore crescente salvato in NVS) e risponde con COMMAND_RESULT. Un nuovo comando
sostituisce quelli dello stesso tipo ancora in attesa; le durate sono relative all'ora del
frame.

| Comando | Parametro | Effetto |
| :--- | :--- | :--- |
| `LIVE` | secondi (0 = stop) | Ogni campione è registrato e inviato subito |
| `ANTITHEFT` | secondi (0 = riattiva) | Allarmi sospesi (es. auto dal meccanico) |
| `LOCATE` | - | Una posizione appena possibile (scade dopo un'ora) |

Con l'auto parcheggiata il tracker dorme: un comando arriva al risveglio successivo.

**Orologio**: l'ora UTC arriva dal GNSS o, senza fix, dal timestamp autenticato degli ACK e dei
comandi (solo in avanti).

## Flusso

1. **Registrazione**: a ogni accensione il tracker invia un HELLO cifrato con la propria chiave;
   il server deriva la chiave dall'IMEI, verifica il tag e risponde con un ACK con l'id.
2. **Telemetria**: GPS letto ogni 5 secondi con **campionamento adattivo** (tolleranza 10 m):
   ogni campione nelle curve, uno ogni 30 secondi in rettilineo; invio a lotti (`BATCH_SIZE` 3,
   o dopo 30 secondi).
3. **Coda offline**: senza rete i punti vanno nella flash (LittleFS, 192 KB ≈ 4900 punti) e al
   ritorno della rete partono in pochi frame grandi.
4. **Senza fix**: i punti portano l'ultima posizione nota marcata *stale* e la cella servente,
   (`AT+CPSI?`), da cui il server può stimare la posizione. In guida uno ogni
   `CELL_FALLBACK_INTERVAL_SEC` (60 s) senza fix.

## Telefoni

I telefoni non usano questo protocollo: inviano le posizioni in JSON su HTTPS
(`POST /api/phones/positions`) con il token di caricamento del telefono; ogni punto può
indicare il veicolo dell'utente da cui si condivide (`vehicleId`).
