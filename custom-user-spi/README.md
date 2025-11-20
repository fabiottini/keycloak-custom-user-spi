# Custom User Storage SPI per Keycloak

Questo SPI (Service Provider Interface) permette a Keycloak di leggere gli utenti da un database PostgreSQL custom e autenticarli usando password MD5.

## Caratteristiche

- **Lettura utenti**: Legge gli utenti dalla tabella `utenti` del database custom
- **Autenticazione MD5**: Verifica le password usando hash MD5
- **Ricerca utenti**: Supporta ricerca per username, email, nome e cognome
- **Solo lettura**: Non permette modifiche agli utenti (solo lettura)

## Struttura Database

Il database deve avere una tabella `utenti` con la seguente struttura:

```sql
CREATE TABLE utenti (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(50) NOT NULL,
    cognome VARCHAR(50) NOT NULL,
    mail VARCHAR(100) NOT NULL UNIQUE,
    username VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(32) NOT NULL -- MD5 hash (32 caratteri)
);
```

## Configurazione

### 1. Build del JAR

```bash
cd custom-user-spi
mvn clean package
```

### 2. Deploy in Keycloak

Copia il JAR generato in `/opt/keycloak/providers/` del container Keycloak.

### 3. Configurazione in Keycloak Admin Console

1. Vai su **User Federation** nel realm
2. Clicca **Add provider** → **custom-user-storage**
3. Configura i parametri:
   - **Database URL**: `jdbc:postgresql://user-db:5432/user`
   - **Database User**: `user`
   - **Database Password**: `user_password`
   - **Table Name**: `utenti`

### 4. Configurazione Authentication Flow

1. Vai su **Authentication** nel realm
2. Crea un nuovo flow o modifica quello esistente
3. Aggiungi il **Custom Credential Validator** per l'autenticazione MD5

## Test

Gli utenti di test nel database sono:

| Username | Password | Email |
|----------|----------|-------|
| mrossi | mrossi | mario.rossi@email.com |
| lverdi | lverdi | luigi.verdi@email.com |
| abianchi | abianchi | anna.bianchi@email.com |
| gneri | gneri | giulia.neri@email.com |
| mferrari | mferrari | marco.ferrari@email.com |
| sromano | sromano | sara.romano@email.com |
| aricci | aricci | andrea.ricci@email.com |
| emarino | emarino | elena.marino@email.com |
| dgreco | dgreco | davide.greco@email.com |
| fbruno | fbruno | francesca.bruno@email.com |

## Troubleshooting

### Log Keycloak
Controlla i log di Keycloak per errori di connessione:
```bash
docker logs keycloak
```

### Test Connessione Database
```bash
docker exec -it user-postgres psql -U user -d user -c "SELECT * FROM utenti;"
```

### Verifica MD5
Per testare l'hash MD5 di una password:
```bash
echo -n "username1!" | md5sum
``` 