Ecco il testo sistemato e ristrutturato in modo chiaro:

---

# Script di background per Mac – Organizzatore automatico di file

## Obiettivo generale

Voglio creare uno script che giri in background sul Mac, accessibile tramite un'icona nella **menu bar** (barra in alto). Da lì deve essere possibile accenderlo, spegnerlo e metterlo in pausa, oltre che modificare le configurazioni direttamente dal menu.

---

## Struttura del progetto

Il progetto deve essere impostato in modo modulare e scalabile, poiché i compiti potrebbero aumentare nel tempo. Le configurazioni (metadati ricercati, soglie di durata, ranking dei formati, ecc.) devono risiedere in un **file di configurazione** esterno, modificabile anche tramite la menu bar.

---

## Compito 1 – Gestione file audio dalla cartella Download

### 1.1 – Scansione e filtraggio

Lo script monitora la cartella **Downloads** e identifica i file audio. Per ciascun file audio trovato, verifica:

- La presenza di **metadati** (titolo, artista, album). I campi da controllare devono essere definiti nel file di configurazione, così da poterli modificare facilmente.
- La **durata**: i file con durata inferiore a **60 secondi** vengono ignorati. Anche questa soglia deve essere configurabile (sia dal file di config che dalla menu bar, dove sarà possibile aumentarla o abbassarla al volo).

### 1.2 – Spostamento

I file audio che superano entrambi i controlli (metadati presenti + durata sufficiente) vengono spostati nella cartella **~/Music**.

### 1.3 – Conversione in AIFF

Una volta spostato il file in `~/Music`, lo script valuta se convertirlo in **formato AIFF a 16 bit** tramite `ffmpeg` (la conversione dovrà essere di più file contemporaneamente).

Non tutti i file vengono convertiti: ha senso farlo solo per i formati che hanno una qualità sufficientemente alta. Per questo motivo esiste un **ranking dei formati audio**, che include anche i dettagli di encoding (es. bitrate). Nel file di configurazione è possibile impostare un **limite di posizione** nel ranking: tutti i formati con posizione uguale o superiore al limite vengono convertiti, gli altri no.

*Esempio: se il limite è impostato a posizione 3, solo i formati dalla posizione 3 in su vengono convertiti.*

### 1.4 – Gestione dei file a bassa qualità

I file il cui formato non supera il limite del ranking **non vengono convertiti**, ma:

- Vengono spostati in una cartella chiamata **`low_quality`**.
- I loro metadati (titolo, album, artista) vengono scritti in un file **CSV** presente nella stessa cartella `low_quality`.

---

## Compito 2 – Gestione PDF dalla cartella Download

Lo script monitora la cartella **Downloads** anche alla ricerca di file PDF. Per ciascun PDF trovato, deve determinare se si tratta di un **paper scientifico**.

Poiché questa valutazione non può essere fatta in modo deterministico, viene utilizzato un **LLM locale** (per ora tramite **LM Studio**, con un modello da scaricare localmente) per analizzare il documento e classificarlo.

- Se il PDF è un paper scientifico → viene spostato in **~/Documents/Papers**.
- Se il PDF non è un paper scientifico → viene lasciato dov'è, senza alcuna azione.

---

Fammi sapere se vuoi che approfondisca uno dei compiti o che inizi a strutturare il codice.