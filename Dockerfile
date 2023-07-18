FROM debian:12 AS base
ENV DEBIAN_FRONTEND=noninteractive


WORKDIR /app

COPY deploy/init.sh deploy/
RUN sh deploy/init.sh
RUN apt-get install -y curl ca-certificates sqlite3 --no-install-recommends

FROM base as chef

RUN apt-get install -y libgdal-dev build-essential pkg-config cmake libclang-dev libssl-dev --no-install-recommends

COPY deploy/deploy.sh deploy/
RUN sh deploy/deploy.sh
ENV PATH="/root/.cargo/bin:${PATH}"

RUN cargo install cargo-chef

FROM chef as planner

COPY Cargo.toml Cargo.toml
COPY Cargo.lock Cargo.lock
COPY gtfs-structure gtfs-structure
COPY gtfs-structure-2 gtfs-structure-2

COPY src src

RUN cargo chef prepare --recipe-path recipe.json

FROM chef AS builder

COPY --from=planner /app/recipe.json recipe.json

# Build dependencies - this is the caching Docker layer!
RUN cargo chef cook --release --recipe-path recipe.json --features prod
RUN cargo build -p gtfs-structure-2 --release

# Build application
COPY src src
COPY Cargo.toml Cargo.toml
COPY Cargo.lock Cargo.lock
COPY gtfs-structure gtfs-structure
COPY gtfs-structure-2 gtfs-structure-2
RUN cargo build --release --features prod

FROM base AS run
WORKDIR /app
#COPY certificates /app/certificates
#COPY city-gtfs /app/city-gtfs
#COPY web/public /app/web/public
COPY --from=builder /app/target/release/timetoreach /usr/bin/timetoreach

ENV RUST_LOG info,timetoreach=debug,h2=info,hyper=info,warp=info,rustls=info
ENTRYPOINT ["/usr/bin/timetoreach"]