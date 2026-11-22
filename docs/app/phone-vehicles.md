# Telefono e veicoli senza tracker

## Il telefono come localizzatore

*Dispositivi → Aggiungi → Questo telefono*: senza hardware, il telefono condivide la propria
posizione e diventa un dispositivo come gli altri (condivisione con gli amici, aree di arrivo,
storico). Solo nell'app Android (il browser non può inviare la posizione in background).

- Servizio in primo piano con notifica fissa, in un isolate separato: continua con l'app
  chiusa e, con la posizione consentita «Sempre», riparte dopo un riavvio.
- Un punto ogni 15 s o 20 m; da fermo l'ultima posizione ogni 5 minuti; livello della batteria
  del telefono visibile agli amici; *Pausa 1 ora* dall'app o dalla notifica.
- Invio con un **token di caricamento** del telefono, non con la sessione: vale solo per le
  posizioni di quel telefono e cambia a ogni avvio della condivisione. I punti senza rete
  restano in coda e partono a lotti.
- Le posizioni personali si conservano `PHONE_RETENTION_DAYS` giorni.

## Condividere come persona o dal veicolo

Nella schermata *Questo telefono* la sezione **Condividi come** propone:

- **Me stesso**: la posizione della persona, vista dagli amici.
- **Uno dei tuoi veicoli**: le posizioni diventano quelle dell'auto. La posizione personale
  resta ferma all'ultimo punto, l'auto registra il viaggio.

La scelta si cambia in qualsiasi momento, anche durante la condivisione, e resta per le volte
successive. I punti in coda senza rete mantengono la scelta fatta quando sono stati presi.
*Aggiungi veicolo* crea un veicolo e lo sceglie subito.

## Veicoli senza tracker

*Dispositivi → Aggiungi → Veicolo senza tracker* (anche dal browser): nome, modello,
carburante e colore. Un veicolo è un dispositivo dell'utente alimentato dal telefono del
proprietario quando condivide da lì.

| Funzione | Veicolo dal telefono | Tracker |
| :--- | :---: | :---: |
| Posizione in tempo reale, storico, viaggi, esportazione | ✓ (solo mentre il telefono è a bordo e condivide dal veicolo) | ✓ sempre |
| Costi dei viaggi con carburante, prezzo medio nazionale | ✓ | ✓ |
| Registro viaggi lavoro / personali | ✓ | ✓ |
| Contachilometri e scadenze (tagliando, revisione, bollo...) | ✓ | ✓ |
| Statistiche nel tempo (km, ore, viaggi) | ✓ | ✓ |
| Aree di arrivo, sosta prolungata, condivisione con gli amici | ✓ | ✓ |
| «Raggiungi a piedi» fino all'auto parcheggiata | ✓ (ultima posizione registrata) | ✓ |
| Antifurto, allarmi di movimento e sollevamento, alimentazione staccata | ✗ (il telefono non resta in auto) | ✓ |
| Comandi (Live, Localizza, Pausa antifurto) | ✗ | ✓ |
| Segnale, satelliti, tensione della batteria, copertura, dati SIM | ✗ | ✓ |
| Aggiornamenti del firmware, dati aggiuntivi | ✗ | ✓ |

- Un veicolo non è mai «non raggiungibile»: senza telefono a bordo è semplicemente fermo.
- I viaggi si dividono come per i telefoni: una sosta oltre 5 minuti chiude il viaggio.
- Solo il proprietario del veicolo e del telefono può condividere dal veicolo; al massimo 10
  veicoli per utente.
- Le posizioni del veicolo si conservano `RETENTION_DAYS` giorni come quelle dei tracker:
  sono dati dell'auto, non della persona.
- Eliminare il veicolo cancella storico, costi, scadenze, aree e condivisioni.

!!! tip "Più persone sulla stessa auto"
    Il veicolo può essere condiviso in sola visione, ma solo il proprietario può alimentarlo
    dal proprio telefono. Per un'auto di famiglia guidata da più persone conviene un tracker.
