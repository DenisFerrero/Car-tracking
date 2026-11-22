# Log della piattaforma

Il backend tiene un **log della piattaforma** per analizzare a posteriori gli errori da
risolvere e ciò che è lento da ottimizzare. Non è un log di accesso né di attività degli
utenti: contiene solo errori e lentezze, **senza dati personali**, ed è conservato
**30 giorni** (`LOG_RETENTION_DAYS`).

## Cosa contiene

| Tipo | Quando | Dettagli |
| :--- | :--- | :--- |
| **Errori** | ogni richiesta finita con errore 500; ogni errore dei servizi (job periodici, gateway dei tracker, notifiche push, prezzi dei carburanti, release…) | percorso (`GET /api/devices/:id`), tipo, codice e messaggio dell'errore, stack |
| **Avvisi** | avvisi dei servizi: servizi esterni non raggiungibili, push non consegnate, tracker che non si autenticano, release scartate… | messaggio, servizio, campi utili (es. IMEI del tracker, codice dell'errore) |
| **Richieste lente** | richieste HTTP oltre `LOG_SLOW_REQUEST_MS` (default 1000 ms) | percorso, metodo, stato, durata media e massima |
| **Query lente** | query con durata media oltre `LOG_SLOW_QUERY_MS` (default 100 ms) o massima oltre 10 volte tanto, rilevate ogni ora | testo della query normalizzato (senza valori), esecuzioni, durata media, massima e totale, righe |

Le voci uguali di pochi secondi (stesso tipo, servizio, messaggio ed errore) diventano **una
riga con il conteggio**: un'ondata di errori non riempie il database. Oltre 200 voci
diverse ogni 10 secondi le altre vengono solo contate («Log entries dropped»).

**Non vengono registrati**: corpi delle richieste, query string, URL con i valori (solo lo
schema del percorso), indirizzi IP, email, token, utenti. Le connessioni WebSocket (lunghe per
natura) e i percorsi inesistenti non contano come richieste lente.

Gli stessi errori e avvisi restano anche nell'output del container (`docker compose logs
backend`, livello `LOG_LEVEL`), che però non è conservato né raggruppato.

## Consultarlo nell'app

*Account › Amministrazione › Log della piattaforma* (solo amministratori): errori, avvisi,
richieste lente e query lente delle ultime 24 ore, 7 o 30 giorni, raggruppati per servizio e
messaggio, i più frequenti per primi. Per ogni gruppo: quante volte, prima e ultima volta,
durata media e massima; aprendolo, i dettagli dell'ultima occorrenza (con lo stack degli
errori) e **Copia** per incollarli in una segnalazione.

## Query lente: pg_stat_statements

Le query lente vengono da `pg_stat_statements`, che il database deve caricare all'avvio. Il
`docker-compose.yml` lo fa già:

```yaml
timescaledb:
  command: postgres -c shared_preload_libraries=timescaledb,pg_stat_statements
```

Su un'installazione esistente basta aggiornare il `docker-compose.yml` e riavviare il
database (`docker compose up -d`): il backend crea l'estensione da solo. Senza la libreria
le query lente non vengono raccolte (l'app lo segnala) e il resto del log funziona. Ogni ora
il backend legge le statistiche delle query del proprio database e le azzera.

## Impostazioni

| Variabile | Default | |
| :--- | :--- | :--- |
| `LOG_RETENTION_DAYS` | 30 | Giorni di conservazione (1-365), policy di retention di TimescaleDB |
| `LOG_SLOW_REQUEST_MS` | 1000 | Soglia di una richiesta lenta |
| `LOG_SLOW_QUERY_MS` | 100 | Soglia della durata media di una query lenta |

## Analisi con SQL

Il log è la tabella `platform_log` (hypertable): `time`, `kind` (`error`, `warning`,
`slow_request`, `slow_query`), `source`, `message`, `count`, `duration_ms` (la più lunga),
`details` (JSON). Qualche esempio (`docker compose exec timescaledb psql -U car_tracking`):

```sql
-- Errori più frequenti degli ultimi 7 giorni
SELECT source, message, details ->> 'errorMessage' AS error, sum(count) AS times, max(time) AS last
FROM platform_log WHERE kind = 'error' AND time > now() - interval '7 days'
GROUP BY 1, 2, 3 ORDER BY times DESC LIMIT 20;

-- Percorsi lenti: quante volte, durata media e massima
SELECT message, sum(count) AS times,
	round(sum((details ->> 'avgMs')::float * count) / sum(count)) AS avg_ms, max(duration_ms) AS max_ms
FROM platform_log WHERE kind = 'slow_request' GROUP BY message ORDER BY times DESC;

-- Query lente per tempo totale
SELECT message, sum((details ->> 'calls')::int) AS calls, max((details ->> 'maxMs')::float) AS max_ms,
	sum((details ->> 'totalMs')::float) AS total_ms
FROM platform_log WHERE kind = 'slow_query' GROUP BY message ORDER BY total_ms DESC LIMIT 20;

-- Errori per giorno
SELECT time_bucket('1 day', time) AS day, sum(count) FROM platform_log WHERE kind = 'error' GROUP BY 1 ORDER BY 1;
```

Il log fa parte del database e quindi dei [backup](backup.md).
