# Consumo dati SIM

Valori misurati sui frame reali, includendo tutto ciò che la SIM trasmette e
riceve per ogni invio: WebSocket (6 B), record TLS (29 B), TCP/IP (40 B) e l'ACK TCP
del server (40 B).

## Peso di un invio

| Configurazione | Frame | Sulla rete | Per ora di guida |
| :--- | :---: | :---: | :---: |
| Protocollo precedente (JSON + hex, 1 punto ogni 5s) | ~238 B | ~339 B | ~244 KB |
| **v2, `BATCH_SIZE 1`** (posizione ogni 5s) | 35 B | 126 B | 91 KB |
| **v2, `BATCH_SIZE 3`** (default, ogni 15s) | 51 B | 142 B | 34 KB |
| **v2, `BATCH_SIZE 6`** (ogni 30s) | 75 B | 166 B | 20 KB |

A parità di campionamento, la configurazione di default consuma circa **7 volte
meno** del protocollo precedente.

## Profili di utilizzo

- **A. Pendolare**: 41 ore di guida al mese
- **B. Professionista**: 84 ore di guida al mese
- **C. Flotta / Taxi**: 208 ore di guida al mese (8 ore al giorno, 26 giorni)

| Profilo | `BATCH_SIZE 1` | `BATCH_SIZE 3` | `BATCH_SIZE 6` |
| :--- | :---: | :---: | :---: |
| **A. Pendolare** | 3,7 MB | **1,4 MB** | 0,8 MB |
| **B. Professionista** | 7,6 MB | **2,9 MB** | 1,7 MB |
| **C. Flotta** | 18,9 MB | **7,1 MB** | 4,1 MB |

A questi valori si aggiungono:

| Voce | Consumo mensile |
| :--- | :---: |
| Connessione a ogni accensione (TCP, WebSocket, HELLO/ACK ≈ 1,5 KB, 4 al giorno) | ~0,2 MB |
| Heartbeat ogni 4 ore (connessione + 1 punto) | ~0,3 MB |
| TLS (handshake ~5 KB a connessione, ~29 B per frame) | ~2 MB |
| Allarmi: caso peggiore, un falso allarme ogni 10 minuti per tutto il mese | ~11 MB |
| Richiesta giornaliera di aggiornamento (`AUTO_UPDATE 1`) | ~3 KB |
| Un aggiornamento del firmware (quando esce una versione) | ~1,3 MB |

**Caso peggiore realistico** (profilo C, posizione ogni 5 secondi, falsi allarmi
continui, TLS): **~35 MB/mese**, ben sotto una SIM da **200 MB/mese**. Una sessione
`LIVE` costa come `BATCH_SIZE 1`, ~90 KB per ora.

## Ottimizzazioni

1. **Protocollo binario a differenze**: ~8 byte per punto, contro ~238 byte di JSON
   cifrato e codificato in esadecimale.
2. **Invio a lotti**: l'overhead fisso di ~85 byte per invio (TCP/IP, WebSocket) è
   diviso fra più punti.
3. **Una sola scrittura per frame WebSocket**: header e payload nello stesso
   segmento TCP.
4. **Filtro di distanza**: in sosta o in coda nessun punto, salvo uno ogni 5 minuti
   (`THRESHOLD_DISTANCE`, `STATIONARY_INTERVAL_SEC`).
5. **Coda offline compatta**: al ritorno della rete fino a 40 punti per frame.
6. **Riconnessione con back-off esponenziale** (5s → 2 min): con copertura scarsa i
   tentativi non consumano dati inutilmente.
7. **Keep-alive a 60s** solo quando non ci sono altri invii (Cloudflare chiude i
   WebSocket inattivi dopo 100s).
8. **Limiti sugli allarmi**: armamento ritardato e pausa dopo ogni allarme.

I veicoli alimentati dal telefono non usano la SIM del tracker: il traffico è quello del
telefono (~1 KB ogni 15 secondi in viaggio, in JSON su HTTPS).
