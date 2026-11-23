#!/bin/sh
# End-to-end tests of the web app: the image of the backend (backend + Flutter web, the one
# published), a TimescaleDB, the first administrator from create-admin, then Playwright
# (Chromium) in its official image on the same Docker network. Everything is removed at
# the end. From the repository root:
#   sh e2e/run.sh                 builds the image from backend/Dockerfile
#   E2E_IMAGE=<image> sh e2e/run.sh   tests an image already built
#   E2E_WEB=app/build/web ...     the web app of a local flutter build in place of the one of
#                                 the image (quicker while writing the tests)
# Results: e2e/results/ (screenshots and traces of the failed tests), e2e/report/
set -eu

cd "$(dirname "$0")/.."
ROOT=$(pwd)
PLAYWRIGHT=mcr.microsoft.com/playwright:v1.64.1-noble
NET=ct-e2e
DB=ct-e2e-db
APP=ct-e2e-app
URL=http://$APP:4000
IMAGE=${E2E_IMAGE:-ct-e2e:local}

cleanup () {
	docker rm -f "$APP" "$DB" > /dev/null 2>&1 || true
	docker network rm "$NET" > /dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup

[ -n "${E2E_IMAGE:-}" ] || docker build -f backend/Dockerfile -t "$IMAGE" .

docker network create "$NET" > /dev/null
docker run -d --name "$DB" --network "$NET" -e POSTGRES_PASSWORD=e2e -e POSTGRES_DB=car_tracking \
	timescale/timescaledb:2.24.0-pg17 > /dev/null
# On TCP: the temporary server of the first initialization listens only on the socket
i=0
until docker exec "$DB" psql -h 127.0.0.1 -U postgres -d car_tracking -c "SELECT 1" > /dev/null 2>&1; do
	i=$((i + 1)); [ "$i" -lt 60 ] || { echo "TimescaleDB not ready" >&2; exit 1; }; sleep 2
done

MOUNT=$ROOT
command -v cygpath > /dev/null && MOUNT=$(cygpath -w "$ROOT")
WEB=
[ -z "${E2E_WEB:-}" ] || WEB="-v $MOUNT/$E2E_WEB:/app/web:ro"

# Map tiles from the backend itself (404): the public OSM servers stay out of the tests
# shellcheck disable=SC2086
MSYS_NO_PATHCONV=1 docker run -d --name "$APP" --network "$NET" $WEB \
	-e DATABASE_URL="postgres://postgres:e2e@$DB:5432/car_tracking" \
	-e CRYPTO_MASTER_KEY=e2e-master-key-0123456789abcdef0123456789 \
	-e PUBLIC_URL="$URL" -e TIMEZONE=Europe/Rome -e LOG_LEVEL=warn \
	-e MAP_TILE_URL="$URL/tiles/{z}/{x}/{y}.png" -e FUEL_PRICES_URL= -e AUTH_RATE_LIMIT=100 \
	"$IMAGE" > /dev/null
i=0
until docker exec "$APP" node -e "fetch('http://127.0.0.1:4000/healthz').then(r => process.exit(r.ok ? 0 : 1), () => process.exit(1))"; do
	i=$((i + 1)); [ "$i" -lt 60 ] || { docker logs "$APP" >&2; exit 1; }; sleep 2
done

INVITE=$(docker exec "$APP" node scripts/create-admin.ts admin@e2e.invalid "Amministratore" | grep -o "$URL/#/invite/[A-Za-z0-9_-]*")
[ -n "$INVITE" ] || { echo "No invite from create-admin" >&2; exit 1; }

# The repository: texts of the app in app/lib/l10n, results written in e2e/
status=0
MSYS_NO_PATHCONV=1 docker run --rm --network "$NET" --ipc=host --init \
	-v "$MOUNT:/repo" -w /repo/e2e -e CI="${CI:-}" -e BASE_URL="$URL" -e INVITE_URL="$INVITE" \
	"$PLAYWRIGHT" sh -c "npm ci --no-audit --no-fund > /dev/null && npx playwright test" || status=$?
[ "$status" = 0 ] || docker logs --tail 50 "$APP" >&2
exit "$status"
