LAB SOVRANO - VAULT README
==========================

Scopo
-----
Questo README riassume cosa e' stato fatto nel lab per avviare HashiCorp Vault in Docker, inizializzarlo, sbloccarlo e prepararlo per l'uso come secret manager e futura PKI interna.

Contesto del lab
----------------
- Ambiente locale/home lab
- Vault avviato in Docker
- Storage persistente su disco host
- Accesso locale su http://localhost:8200
- Nessuna esposizione in LAN / Internet in questa fase
- TLS del listener Vault disabilitato per semplicita' di lab

Struttura usata
---------------
Cartella:
D:\lab-sovrano\vault\

Contenuto atteso:
- docker-compose.yml
- config\vault.hcl
- file\           <-- dati persistenti di Vault
- logs\

Importante:
-----------
La cartella "file" contiene lo storage persistente del Vault.
Se il container viene distrutto e ricreato MA la cartella "file" resta, Vault NON va reinizializzato.
Se la cartella "file" viene cancellata, il Vault viene perso e bisogna rifare init da zero.


Comandi Vault eseguiti nel container
------------------------------------
0) export VAULT_ADDR=http://127.0.0.1:8200
  sennò i comandi non funzionano


1) Inizializzazione (SOLO la prima volta per questo storage backend):
   vault operator init

   Output importante da salvare:
   - Unseal Key 1
   - Unseal Key 2
   - Unseal Key 3
   - Unseal Key 4
   - Unseal Key 5
   - Initial Root Token

2) Unseal (da ripetere 3 volte con 3 chiavi diverse):
   vault operator unseal
   vault operator unseal
   vault operator unseal

3) Verifica stato:
   vault status

   Stato atteso dopo l'unseal:
   - Initialized: true
   - Sealed: false

4) Login con root token:
   vault login

5) Abilitazione KV v2:
   vault secrets enable -path=kv kv-v2

6) Scrittura segreto di test:
   vault kv put kv/test username=admin password=ciao123

7) Lettura segreto di test:
   vault kv get kv/test

Accesso UI
----------
Browser locale:
http://localhost:8200

Usare il root token per entrare.

Cosa significa init / unseal / login
------------------------------------
- init:
  crea il Vault per la prima volta, genera unseal keys e root token.

- unseal:
  sblocca il Vault in memoria usando 3 chiavi su 5.

- login:
  autentica l'operatore per usare Vault.

Regola fondamentale
-------------------
- Container effimero
- Storage persistente

Il "vero" Vault e' nei dati salvati in ./file, non nel container.

Quindi:
- Se ricrei il container e lasci ./file intatta -> niente init, solo unseal
- Se cancelli ./file -> Vault perso, bisogna rifare init

Perche' non e' tutto automatico in questa fase
----------------------------------------------
In questo lab si usa il meccanismo standard con unseal manuale.
Quindi:
- init e' manuale la prima volta
- unseal e' manuale dopo un restart del Vault

In una fase piu' industriale si valutera':
- auto-unseal
- bootstrap idempotente via script/API
- PKI interna con Vault
- storage / deployment piu' robusti

Prossimo passo previsto dopo questo lab base
--------------------------------------------
1) Abilitare PKI in Vault
2) Usare Vault come CA interna
3) Emettere certificati per reverse proxy e servizi interni
4) Fare in modo che i servizi si fidino della CA interna

Note operative
--------------
- Non esporre Vault su Internet
- Non esporre Vault in LAN in questa fase se non necessario
- Conservare con cura root token e unseal keys
- Non cancellare la cartella ./file se si vuole mantenere lo stesso Vault

Comandi rapidi di promemoria
----------------------------
Da host:
- docker compose up -d
- docker compose logs vault
- docker exec -it vault sh

Nel container:
- vault operator init
- vault operator unseal
- vault operator unseal
- vault operator unseal
- vault status
- vault login
- vault secrets enable -path=kv kv-v2
- vault kv put kv/test username=admin password=ciao123
- vault kv get kv/test

Fine README
