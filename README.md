# Car tracking

## Production

It's necessary to customize the secrets and password of the services.

### Docker environment

Update the file ``.env`` as you want, the variables are the following

- **DOMAIN**, Cloudlflare domain, for example *car-tracking.mydomain.com*
- **POSTGRES_DB**, database name, you can keep the default value
- **POSTGRES_USERNAME**/**POSTGRES_PASSWORD**, change as you want, the database service will not be reachable from outside of the container network but it's a good practice to change it from the default one
- **MQTT_USERNAME**/**MQTT_PASSWORD**, change as you, mqtt will be accessible from the internet so it's necessary to change these values
- **CLOUDFLARE_TUNNEL_TOKEN**, Cloudlflare tunnel token

### Nginx

Run this command to create your users and their access to the website

```sh
htpasswd -c ./nginx/.htpasswd <your-username>
```

Basic user ``test`` already stored, its password is ``test``

### Mosquitto

Mosquitto has a configuration file where it's necessary to set the hashed password for the container (``./mosquitto/config/passwd``), rather than using the default one generate your credentials on this [website](https://dmelo.eu/blog/mosquitto_passwd_gen/), iteration = 100. Generated the credentials according to *MQTT_USERNAME* and *MQTT_PASSWORD*

### Cloudflare

After adding configuring the connector it's necessary to add the a *Published application route*,
After filling the domain and the sub-domain it's necessary to set other settings:

```
Service => HTTP ://nginx:80
Additional application settings
    |=> TLS
        |=> No TLS Verify = ON
```

Automatically the route will be converted to HTTP without requiring you to generate the necessary certificates
