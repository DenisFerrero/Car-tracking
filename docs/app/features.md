# Funzioni

## Mappa

Tutti i dispositivi visibili (propri e condivisi) con l'ultima posizione, aggiornata in tempo
reale. Filtri: miei / condivisi con me, proprietario, in movimento / fermi / non raggiungibili
(tracker silenzioso oltre `OFFLINE_AFTER_HOURS`, telefono che ha smesso di condividere),
veicoli / telefoni, ricerca per nome; contatore dei dispositivi mostrati e pulsante per
inquadrare quelli filtrati. I dispositivi vicini si raggruppano con il numero: il tocco
ingrandisce, oppure elenca quelli nello stesso punto.

## Schede di un dispositivo

- **Live**: posizione in tempo reale (per il proprietario di un tracker attiva la modalità
  live per 10 minuti, rinnovata finché la schermata è aperta), scia delle ultime 2 ore,
  segnale, satelliti, batteria, temperatura; comandi *Live 30 min*, *Localizza*, *Pausa
  antifurto* (solo tracker). **Raggiungi a piedi** apre Google Maps (app o browser) con il
  percorso a piedi fino all'auto o all'amico.
- **Storico**: percorso del periodo colorato per velocità, **segnale LTE** o **satelliti**,
  interruzioni tratteggiate, eventi, cursore per ripercorrere i punti.
- **Analisi**: km, tempo di guida, viaggi; per i tracker anche velocità, segnale, satelliti,
  altitudine, tensione della batteria dell'auto, temperatura e pressione, qualità del fix,
  **mappa di copertura** e **dati SIM** con proiezione a fine mese. Ogni viaggio si apre sulla
  mappa; **esportazione** in GPX o CSV.
- **Aree**: aree di arrivo dell'utente su mappa ed elenco.
- **Impostazioni** (proprietario): nome, colore, notifiche per tipo, condivisione,
  aggiornamento del firmware, rimozione.

Un dispositivo condiviso mostra solo **Live** e **Aree**, più *Rinuncia alla condivisione*.

## Amici e condivisione

- Ognuno ha un codice personale (`ABCDE-FGHJK`, anche QR code): chi lo inserisce invia una
  **richiesta di amicizia**, che l'altro accetta o rifiuta. Al massimo 20 richieste in
  sospeso; il codice si può rigenerare; rimuovere un amico chiude le condivisioni tra i due.
- Il proprietario condivide un dispositivo in sola visione con un amico, per sempre o fino a
  una data e ora (scelte rapide da 1 ora a 7 giorni). Chi riceve vede nome, posizione, stato,
  velocità, ultimo contatto e scadenza: niente IMEI, segnale, batteria, allarmi, storico
  precedente o comandi.

## Aree di arrivo e avvisi

- **Aree**: ogni utente imposta aree circolari (50 m - 50 km) e riceve una notifica quando il
  dispositivo entra (e, se vuole, esce). Le aree sono personali. Un'area può avvisare **solo
  in certi orari** (giorni e fascia oraria; se la fine è prima dell'inizio passa la
  mezzanotte, es. 23:00-6:00).
- **Sosta prolungata**: avviso se il dispositivo resta fermo più di 1-48 ore fuori dalle aree
  dell'utente.
- **Batteria bassa** di un telefono condiviso: soglia 10-50%.
- **Salute della batteria dell'auto** (tracker): tensione a riposo media degli ultimi 7
  giorni; < 12,2 V debole (avviso al massimo ogni 14 giorni).

## Viaggi, registro e costi

- **Registro viaggi**: ogni viaggio si segna come *lavoro* o *personale* con una nota;
  *Registro viaggi del mese* scarica un CSV (italiano con `;` e virgola decimale, per Excel)
  con data, orari, partenza, arrivo, km, durata, tipo, note e costi, e i totali.
- **Costi dei viaggi** (tracker, veicoli e telefoni): modello e **carburante** del veicolo
  (benzina, gasolio, GPL), unità del consumo (*l/100 km* o *km/l*) e tre **storici**: prezzo
  del carburante, **consumo** e **usura** in €/km. Ogni valore vale dalla sua data fino al
  successivo; ogni viaggio usa i valori del giorno in cui è partito. *Cerca il costo
  chilometrico ACI* apre la ricerca per il modello (non esiste un'API pubblica delle tabelle
  ACI).
- **Prezzo medio nazionale**: il backend scarica la rilevazione settimanale del Ministero
  dell'Ambiente (MASE, open data, ogni lunedì) di benzina, gasolio e GPL; con *Prezzo dalla
  media nazionale* ogni nuova settimana entra da sola nello storico del veicolo (un prezzo
  inserito a mano lo stesso giorno ha la precedenza).
- **Statistiche nel tempo**: per 12 mesi o 26 settimane km (lavoro e personali), ore di guida
  e viaggi; per i tracker anche salute della batteria, MB sulla SIM e allarmi. Riepilogo
  giornaliero conservato 3 anni per tracker e veicoli, 400 giorni per i telefoni.

## Scadenze e manutenzione

Per i tracker e i [veicoli senza tracker](phone-vehicles.md): contachilometri (si inserisce
la lettura del cruscotto, poi segue i km dei viaggi; si corregge quando serve), scadenze
standard (tagliando e gomme a km, revisione, assicurazione e bollo a data) o personalizzate
(bollino blu, estintore...), ricorrenti o una tantum, con lo stato (ok / vicina / scaduta),
*Fatto* (le ricorrenti si spostano in avanti) e lo storico degli interventi. Avviso quando
mancano i giorni o i km scelti e alla scadenza.

## Dati aggiuntivi (tracker)

Campi letti dal tracker da un'altra scheda del veicolo (frame `EXTRA`, vedi il
[protocollo](../reference/protocol.md#dati-aggiuntivi-extra)), mostrati come arrivano: ultimo
valore di ogni campo e letture con data e ora, senza grafici.

## I tuoi dati

*Esporta i miei dati* scarica un JSON con profilo, accessi, amici, dispositivi con posizioni,
aree, notifiche, costi e dati aggiuntivi. *Elimina account* elimina telefoni, veicoli,
posizioni, condivisioni, amici, aree e notifiche; i tracker tornano liberi e si riabbinano con
il codice dell'etichetta.
