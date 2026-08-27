FROM eclipse-temurin:21-jre-jammy

ENV MB_PLUGINS_DIR=/home/metabase/plugins/

RUN groupadd -r metabase && useradd -r -g metabase metabase

RUN apt-get update && apt-get install -y \
    ca-certificates curl jq \
    && rm -rf /var/lib/apt/lists/*

# /home/metabase/plugins will hold the plugins
# /home/metabase/data is not strictly necessary, can be a place to store data files (.duckdb, .parquet, etc)
RUN mkdir -p /home/metabase/plugins /home/metabase/data && \
    chown -R metabase:metabase /home/metabase

WORKDIR /home/metabase

# Build arguments declared here so base layers above are always cached.
# Empty by default: METABASE_VERSION falls back to the newest version listed in
# metabase_versions.json, METABASE_DUCKDB_DRIVER_VERSION to the
# org.duckdb/duckdb_jdbc version in deps.edn (which *is* the driver version),
# so a plain `docker build .` builds the latest supported combination.
ARG METABASE_VERSION
ARG METABASE_DUCKDB_DRIVER_VERSION
# CI overrides this with the repository the build is running in, so a fork's
# images pull the driver from that fork's own releases instead of from upstream.
ARG METABASE_DUCKDB_DRIVER_REPO=motherduckdb/metabase_duckdb_driver

COPY metabase_versions.json deps.edn /tmp/
RUN mb="${METABASE_VERSION:-$(jq -r 'sort_by(split(".") | map(tonumber)) | last' /tmp/metabase_versions.json)}" && \
    drv="${METABASE_DUCKDB_DRIVER_VERSION:-$(sed -n 's/.*duckdb_jdbc {:mvn\/version "\([^"]*\)".*/\1/p' /tmp/deps.edn)}" && \
    curl -fsSL -o metabase.jar "https://downloads.metabase.com/v${mb}/metabase.jar" && \
    curl -fsSL -o plugins/duckdb.metabase-driver.jar "https://github.com/${METABASE_DUCKDB_DRIVER_REPO}/releases/download/${drv}/duckdb.metabase-driver.jar" && \
    chown metabase:metabase metabase.jar plugins/duckdb.metabase-driver.jar && \
    chmod 755 metabase.jar plugins/duckdb.metabase-driver.jar

EXPOSE 3000

USER metabase

CMD ["java", "-jar", "/home/metabase/metabase.jar"]
