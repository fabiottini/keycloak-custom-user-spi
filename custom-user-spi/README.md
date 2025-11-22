# Custom User Storage SPI for Keycloak

This SPI (Service Provider Interface) allows Keycloak to read users from a custom PostgreSQL database and authenticate them using MD5 passwords.

## Features

- **User Reading**: Reads users from the `utenti` table in the custom database
- **MD5 Authentication**: Verifies passwords using MD5 hashes
- **User Search**: Supports searching by username, email, first name, and last name
- **Read-Only**: Does not allow user modifications (read-only operations)

## Database Structure

The database must have a `utenti` table with the following structure:

```sql
CREATE TABLE utenti (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(50) NOT NULL,
    cognome VARCHAR(50) NOT NULL,
    mail VARCHAR(100) NOT NULL UNIQUE,
    username VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(32) NOT NULL -- MD5 hash (32 characters)
);
```

## Configuration

### 1. Build the JAR

```bash
cd custom-user-spi
mvn clean package
```

### 2. Deploy to Keycloak

Copy the generated JAR to `/opt/keycloak/providers/` in the Keycloak container.

### 3. Configure in Keycloak Admin Console

1. Go to **User Federation** in the realm
2. Click **Add provider** → **fabiottini-custom-user-storage**
3. Configure the parameters:
   - **Database URL**: `jdbc:postgresql://user-db:5432/user`
   - **Database User**: `user`
   - **Database Password**: `user_password`
   - **Table Name**: `utenti`

### 4. Configure Authentication Flow

1. Go to **Authentication** in the realm
2. Create a new flow or modify the existing one
3. Add the **Custom Credential Validator** for MD5 authentication

## Test Users

The test users in the database are:

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

### Keycloak Logs
Check Keycloak logs for connection errors:
```bash
docker logs keycloak
```

### Test Database Connection
```bash
docker exec -it user-postgres psql -U user -d user -c "SELECT * FROM utenti;"
```

### Verify MD5
To test the MD5 hash of a password:
```bash
echo -n "password" | md5sum
``` 