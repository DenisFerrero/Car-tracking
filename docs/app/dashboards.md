# Dashboard personalizzate

Oltre alle schermate di ogni veicolo, ogni utente può comporre le proprie **dashboard**:
widget scelti da un catalogo di dati, su una griglia che si adatta allo schermo (2 colonne
sul telefono, fino a 8 sul desktop). Le dashboard sono personali; agli amici si può inviare
il solo layout, che useranno con i propri veicoli.

## Creare una dashboard

*Dashboard* nella barra di navigazione. La prima volta si parte da un modello:

- **Panoramica dei veicoli**: km, tempo di guida, viaggi e costo del periodo, km per giorno e
  per veicolo, mappa con posizione e stato, scadenze;
- **Diagnostica dei tracker**: tensione, segnale, satelliti, dati sulla SIM, batteria a riposo
  degli ultimi 90 giorni, allarmi;
- **Vuota**.

Con **+** si aggiungono altre dashboard (al massimo 20), con il menu si rinominano o si
eliminano; il nome in alto sceglie quella da mostrare. L'icona del calendario cambia il
**periodo** della dashboard (oggi, 7 / 30 / 90 giorni, 12 mesi, da inizio anno o date scelte).

## Dashboard corrente

Dal menu **⋮ › Imposta come corrente** una dashboard diventa quella **corrente** (★ accanto al
nome; una sola per utente):

- si apre per prima nella voce *Dashboard*;
- prende il posto dell'analisi standard nella tab **Analisi** di ogni veicolo: i suoi widget
  mostrano solo quel veicolo, nel periodo scelto in alto nella scheda (i widget con un
  periodo proprio lo mantengono). I widget di dati che il veicolo non ha (es. segnale LTE su
  un'auto senza tracker) non compaiono.

Nella tab, **Analisi standard** torna alla vista classica (viaggi, grafici, copertura) e
l'icona accanto apre la dashboard per modificarla. *⋮ › Non più corrente* ripristina
l'analisi standard per tutti i veicoli.

## Condividere con gli amici

**⋮ › Condividi con un amico** invia a uno degli [amici](features.md#amici-e-condivisione) il **solo layout**:
widget, visualizzazioni e periodi, mai i tuoi veicoli né i loro dati (nella copia inviata
ogni widget è su «tutti i veicoli»). Inviarla di nuovo sostituisce la copia precedente;
eliminare la dashboard o togliere l'amicizia ritira le copie non ancora usate.

L'amico la trova in cima alle sue dashboard (e riceve un avviso nell'app):

- **Usa** chiede il nome e su quali **dei propri veicoli** mostrarla: *tutti i miei veicoli
  attivi* oppure quelli scelti. Un widget di dati che nessuno dei veicoli scelti ha (es.
  dati del tracker scegliendo solo un'auto senza tracker) resta sui veicoli scelti e li
  segnala come non disponibili;
- **Rifiuta** la scarta, senza avvisare chi l'ha inviata.

La dashboard creata è del tutto sua: modificarla non cambia quella dell'amico.

## Modificare i widget

**Modifica** apre l'elenco dei widget: si aggiungono, si toccano per cambiarli, si duplicano
o si rimuovono dal menu e si trascinano dalla maniglia per cambiare l'ordine. *Salva* conferma
tutto insieme; uscendo senza salvare l'app chiede conferma.

Per ogni widget si sceglie:

| Opzione | Valori |
| :--- | :--- |
| **Dato** | dal catalogo qui sotto |
| **Visualizzazione** | numero, linea nel tempo, barre nel tempo, barre per veicolo, tabella per veicolo; elenco o mappa per lo stato attuale |
| **Valore** (dati del tracker) | media, minimo, massimo o ultimo valore |
| **Raggruppamento** | automatico, ore (dati del tracker), giorni, settimane, mesi |
| **Periodo** | come la dashboard, oppure uno proprio |
| **Veicoli** | *tutti i miei veicoli attivi* (anche quelli aggiunti dopo, non gli archiviati) oppure quelli scelti |
| **Titolo, larghezza, altezza** | titolo facoltativo, 1-4 colonne, 1-2 righe |

L'**anteprima** in fondo mostra subito i valori veri.

## Catalogo dei dati

| Gruppo | Dati | Dispositivi | Periodo massimo |
| :--- | :--- | :--- | :--- |
| Viaggi | km percorsi, km di lavoro e personali, tempo di guida, numero di viaggi, velocità massima | tutti | 3 anni |
| Viaggi | allarmi, dati sulla SIM, batteria a riposo | tracker | 3 anni |
| Costi | costo stimato, spesa carburante, usura, litri (dai consumi, prezzi e usura inseriti) | tutti | 3 anni |
| Costi | spesa dei rifornimenti, litri riforniti, prezzo pagato al litro, consumo reale (dai [rifornimenti](features.md#viaggi-registro-e-costi)) | tracker e veicoli | 3 anni |
| Dati del tracker | velocità in movimento, altitudine | tutti | 93 giorni |
| Dati del tracker | segnale LTE, satelliti, tensione, temperatura, pressione | tracker | 93 giorni |
| Dati del tracker | un campo numerico dei **dati aggiuntivi** (es. `rpm`) | tracker | 93 giorni |
| Stato attuale | contachilometri, scadenze | veicoli | — |
| Stato attuale | posizione e stato | tutti, anche condivisi | — |

I totali di viaggi e costi vengono dai riepiloghi giornalieri (veloci anche su anni); i dati
del tracker sono letti dai punti, quindi il periodo è limitato a 93 giorni: con un periodo
più lungo il widget lo segnala. I giorni seguono il fuso orario della piattaforma
(`TIMEZONE`).

## Veicoli non più disponibili

Un widget conserva i veicoli scelti. Se un veicolo viene eliminato o una condivisione scade o
viene revocata, il widget resta e mostra «N veicoli non più disponibili» al posto dei loro
dati. Dei veicoli **condivisi con te** si vede solo *Posizione e stato*: gli altri dati
restano del proprietario.

## API

| Metodo | Percorso | |
| :--- | :--- | :--- |
| `GET` | `/api/dashboards` | dashboard dell'utente |
| `POST` | `/api/dashboards` | `{ name, layout }` |
| `PUT` / `DELETE` | `/api/dashboards/:id` | modifica, eliminazione |
| `PUT` | `/api/dashboards/:id/current` | `{ current }`: dashboard corrente (una sola) |
| `POST` | `/api/dashboards/:id/share` | `{ friendId }`: invia il layout a un amico |
| `GET` | `/api/dashboards/shares` | layout ricevuti in attesa (al massimo 20) |
| `POST` | `/api/dashboards/shares/:id/accept` | `{ name, devices: "all" \| [id…] }` → nuova dashboard |
| `DELETE` | `/api/dashboards/shares/:id` | rifiuta un layout ricevuto |
| `POST` | `/api/dashboards/data` | `{ period, widgets }` → `{ results: { <id del widget>: … } }` |

Il `layout` è `{ version: 1, period, widgets }`, validato dal backend (al massimo 30 widget,
20 veicoli per widget). I widget di dati tolti in futuro dal catalogo vengono scartati alla
lettura. Il catalogo è in `backend/src/services/metrics.ts` e
`app/lib/screens/dashboards/catalog.dart`.
