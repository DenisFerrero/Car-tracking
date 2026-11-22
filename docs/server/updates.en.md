# Server updates

At every release published on GitHub the pipeline (`.github/workflows/release.yml`) builds the
backend image, web app included, for **amd64 and arm64** and publishes it on the GitHub
Container Registry:

```text
ghcr.io/<owner>/<repository>:2.5.0   exact version
ghcr.io/<owner>/<repository>:2.5     latest patch of 2.5
ghcr.io/<owner>/<repository>:2       latest 2.x version
ghcr.io/<owner>/<repository>:latest  latest release
```

## Using the release image

In the `.env` of the server:

```sh
BACKEND_IMAGE=ghcr.io/<owner>/<repository>:2
```

```sh
docker compose pull backend
docker compose --profile traefik up -d      # without --build
```

Pin the **major version** (`:2`), not `latest`: minor versions and patches stay compatible, a
new major version (e.g. a TimescaleDB upgrade or a configuration change) has to be read in the
release notes and applied by hand.

!!! warning "Package visibility"
    At the first push GitHub creates the package `ghcr.io/<owner>/<repository>` as private. To
    pull it without credentials make it public once from **Packages → the package → Package
    settings → Change visibility**. Otherwise `docker login ghcr.io` on the server with a token
    that has only the `read:packages` permission.

## Automatic updates with Watchtower

The `autoupdate` profile adds [Watchtower](https://github.com/nicholas-fedor/watchtower) (the
maintained fork: the original `containrrr/watchtower` project is archived since December
2025):

```sh
docker compose --profile traefik --profile autoupdate up -d
```

- Every night at 4:00 (`WATCHTOWER_SCHEDULE`, cron format with seconds) it checks the tag of
  `BACKEND_IMAGE`; when it changed it pulls the new image, recreates **only the backend** (the
  only container with the `com.centurylinklabs.watchtower.enable` label) and removes the old
  one.
- The time comes after the daily backup at 3:30 (`BACKUP_TIME`): there's always a dump of the
  database taken before the update.
- The database migrations run when the new container starts.
- `WATCHTOWER_NOTIFICATION_URL` ([shoutrrr](https://shoutrrr.nickfedor.com/) format:
  `telegram://`, `ntfy://`, `smtp://`...) sends a report of every update.

### Assessment

| Aspect | Assessment |
| :--- | :--- |
| Reliability | Good for a personal instance: it compares the digest of the tag and recreates the container with the same Compose configuration |
| Risks | Access to the Docker socket (root on the server: use the official image with a pinned version); no automatic rollback if the new backend doesn't start |
| Mitigations | Major version tag, backup before the update, notifications, releases published only after the tests of the pipeline |
| GitHub Free limits | None for public repositories: public GHCR packages have no storage or transfer limits, Linux runners (arm64 too) are free. With a private repository GHCR counts storage and transfer against the free quota (500 MB) |

### Back to the previous version

```sh
# .env: BACKEND_IMAGE=ghcr.io/<owner>/<repository>:2.4.1
docker compose up -d backend
```

If the new version applied migrations the old one can't handle, restore the backup of the
night too (see [Backups](backup.md#restore)).

## Firmware and app

Updates of the trackers and of the Android app don't go through here: the backend reads the
releases of `GITHUB_REPO` (see [Firmware](../firmware/index.md#remote-updates-ota) and
[App](../app/index.md#updates)).
