FROM node:20.18.0-slim AS base

WORKDIR /src

# Build
FROM base AS build

COPY --link package.json package-lock.json .
RUN npm install

COPY --link . .

RUN npm run build

# Run
FROM base

COPY --from=build /src/.output /src/.output
# Optional, only needed if you rely on unbundled dependencies
# COPY --from=build /src/node_modules /src/node_modules

CMD [ "node", ".output/server/index.mjs" ]