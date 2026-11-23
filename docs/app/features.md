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

## Dashboard

Dashboard personali con i widget scelti da un catalogo di dati (km, costi, dati del tracker,
scadenze, posizione) per uno o più veicoli; quella corrente sostituisce l'analisi di ogni
veicolo e il layout si può inviare agli amici: vedi [Dashboard personalizzate](dashboards.md).

## Amici e condivisione

- Ognuno ha un codice personale (`ABCDE-FGHJK`, anche QR code): chi lo inserisce invia una
  **richiesta di amicizia**, che l'altro accetta o rifiuta. Al massimo 20 richieste in
  sospeso; il codice si può rigenerare; rimuovere un amico chiude le condivisioni tra i due.
- Il proprietario condivide un dispositivo in sola visione con un amico, per sempre o fino a
  una data e ora (scelte rapide da 1 ora a 7 giorni). Chi riceve vede nome, posizione, stato,
  velocità, ultimo contatto e scadenza: niente IMEI, segnale, batteria, allarmi, storico
  precedente o comandi.
- **Link temporanei alla posizione** (*Impostazioni → Link temporanei alla posizione*): per
  chi non ha un account ("sto arrivando"). Il proprietario crea un link valido da 1 a 24 ore,
  con un'etichetta facoltativa; l'indirizzo si vede solo alla creazione (il server ne conserva
  l'hash). Chi lo apre vede nel browser nome, colore e ultima posizione del dispositivo,
  aggiornata ogni 15 secondi, fino alla scadenza: niente storico, dati del tracker o account.
  Al massimo 5 link attivi per dispositivo; la lista mostra quando ciascuno è stato aperto e
  ognuno si revoca quando si vuole. Un link scaduto, revocato o sbagliato dà la stessa pagina
  *Link scaduto o revocato*.

## Aree di arrivo e avvisi

- **Aree**: ogni utente imposta aree **circolari** (50 m - 50 km) o **poligonali** (da 3 a 50
  vertici toccati sulla mappa, fino a 50 km: un quartiere, un parcheggio, un tratto di strada)
  e riceve una notifica quando il dispositivo entra (e, se vuole, esce). Per l'uscita da un
  poligono c'è un margine di 30 m, così un punto GPS impreciso sul bordo non manda avvisi
  doppi. Le aree sono personali. Un'area può avvisare **solo
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
  (benzina, gasolio, GPL, ibrida, elettrica), unità del consumo (*l/100 km* o *km/l*; per le
  elettriche *kWh/100 km* o *km/kWh*) e gli **storici**: prezzo del carburante (o dell'energia
  in €/kWh), **consumo**, **usura** in €/km e **rimborso chilometrico**. Ogni valore vale dalla
  sua data fino al successivo; ogni viaggio usa i valori del giorno in cui è partito. *Cerca il
  costo chilometrico ACI* apre la ricerca per il modello (non esiste un'API pubblica delle
  tabelle ACI).
- **Rimborso chilometrico**: gli euro per km riconosciuti per i viaggi di lavoro (tabelle ACI
  o accordo con l'azienda). Il registro viaggi del mese aggiunge la colonna *Rimborso (€)* ai
  viaggi di lavoro e ai loro totali; il riepilogo del mese e le dashboard mostrano il totale.
- **Prezzo medio nazionale**: il backend scarica la rilevazione settimanale del Ministero
  dell'Ambiente (MASE, open data, ogni lunedì) di benzina, gasolio e GPL; con *Prezzo dalla
  media nazionale* ogni nuova settimana entra da sola nello storico del veicolo (un prezzo
  inserito a mano lo stesso giorno ha la precedenza). Un'ibrida segue la media della benzina;
  per le elettriche non c'è una media pubblica: il prezzo si inserisce a mano o arriva dalle
  ricariche.
- **Rifornimenti** (tracker e veicoli, *Analisi → Rifornimenti*): data, litri, importo,
  contachilometri (proposto quello attuale), pieno o parziale, nota. Tra due pieni il
  **consumo reale** è dato dai litri messi dal pieno precedente (parziali compresi) diviso i
  km percorsi; valori fuori da 1-50 l/100 km non si contano. L'importo dà il prezzo al litro.
  Con *Prezzo e consumo dai rifornimenti* (nei costi, attivo all'inizio) ogni rifornimento con
  importo aggiunge allo storico il prezzo pagato dal suo giorno e ogni pieno misurato il
  consumo dal pieno precedente: sono segnati *dai rifornimenti*, seguono le modifiche dei
  rifornimenti e non si cancellano a mano; un valore inserito a mano lo stesso giorno ha la
  precedenza e la media nazionale si ferma per 14 giorni dopo un rifornimento con importo.
- **Ricariche** (veicoli elettrici): come i rifornimenti, in kWh, con il luogo (*a casa* o
  *colonnina*); tra due cariche complete il consumo reale in kWh/100 km, dall'importo il prezzo
  al kWh. Le metriche delle dashboard in litri non contano le elettriche e quelle in kWh solo
  loro.
- **Statistiche nel tempo**: per 12 mesi o 26 settimane km (lavoro e personali), ore di guida
  e viaggi; per i tracker anche salute della batteria, MB sulla SIM e allarmi. Riepilogo
  giornaliero conservato 3 anni per tracker e veicoli, 400 giorni per i telefoni.

## Riepilogo del mese

Il 1° di ogni mese, dalle 8 (fuso `TIMEZONE`), una notifica con km, viaggi e costi del mese
appena finito arriva a chi ha avuto viaggi o rifornimenti; si spegne in **Account → Notifica
a inizio mese**. La pagina *Riepilogo del mese* (dall'account o toccando la notifica) mostra
i totali con la variazione rispetto al mese prima, ogni veicolo (km, viaggi, tempo di guida,
km di lavoro, costi, rimborso chilometrico, rifornimenti o ricariche e consumo reale, dati
sulla SIM, allarmi) e le scadenze vicine o scadute (con la data prevista per quelle a km); le frecce cambiano mese (fino a 3 anni prima), il mese in corso arriva a
oggi.

## Scadenze e manutenzione

Per i tracker e i [veicoli senza tracker](phone-vehicles.md): contachilometri (si inserisce
la lettura del cruscotto, poi segue i km dei viaggi; si corregge quando serve), scadenze
standard (tagliando e gomme a km, revisione, assicurazione e bollo a data) o personalizzate
(bollino blu, estintore...), ricorrenti o una tantum, con lo stato (ok / vicina / scaduta),
*Fatto* (le ricorrenti si spostano in avanti) e lo storico degli interventi. Avviso quando
mancano i giorni o i km scelti e alla scadenza.

Per le scadenze a km la app mostra la **data prevista**, dai km medi al giorno degli ultimi 60
giorni (servono almeno 14 giorni di dati; oltre 3 anni non si mostra): "tra 900 km (prevista
verso il 4 dicembre)". La data prevista compare anche negli avvisi e nel riepilogo del mese, e
una scadenza diventa *vicina* anche quando la data prevista cade entro i giorni di preavviso.

## Sosta

Per i tracker e i veicoli, dal pannello della mappa in tempo reale (*Parcheggia*):

- il posto è l'ultima posizione del veicolo, segnato sulla mappa con una **P**;
- la **scadenza del biglietto** è facoltativa (fino a 31 giorni): con la scadenza arriva un
  **promemoria** da 0 a 60 minuti prima e un avviso alla scadenza; senza (pagamento a
  consumo, es. Telepass o un'app) resta solo il posto;
- una nota (piano, posto, colore delle strisce);
- la sosta finisce da sola quando il veicolo riparte (in movimento a più di 10 km/h dopo 2
  minuti dall'inizio) o con *Termina la sosta*; le soste finite si cancellano dopo 30 giorni.

Con *Impostazioni → Proponi la sosta allo spegnimento* (tracker) una notifica allo spegnimento
del motore propone di impostarla, al massimo una volta ogni 10 minuti e non se è già in corso.
Se il backend era fermo alla scadenza e sono passati più di 60 minuti, l'avviso non arriva in
ritardo.

## Dati aggiuntivi (tracker)

Campi letti dal tracker da un'altra scheda del veicolo (frame `EXTRA`, vedi il
[protocollo](../reference/protocol.md#dati-aggiuntivi-extra)), mostrati come arrivano: ultimo
valore di ogni campo e letture con data e ora, senza grafici.

## I tuoi dati

*Esporta i miei dati* scarica un JSON con profilo, accessi, amici, dispositivi con posizioni,
aree, notifiche, costi, rifornimenti, soste, link temporanei e dati aggiuntivi. *Elimina account* elimina telefoni, veicoli,
posizioni, condivisioni, amici, aree e notifiche; i tracker tornano liberi e si riabbinano con
il codice dell'etichetta.
