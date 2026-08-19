FROM eclipse-temurin:21-jre-jammy

ENV MB_PLUGINS_DIR=/home/metabase/plugins/

RUN groupadd -r metabase && useradd -r -g metabase metabase

RUN apt-get update && apt-get install -y \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# /home/metabase/plugins will hold the plugins
# /home/metabase/data is not strictly necessary, can be a place to store data files (.duckdb, .parquet, etc)
RUN mkdir -p /home/metabase/plugins /home/metabase/data && \
    chown -R metabase:metabase /home/metabase

WORKDIR /home/metabase

# Build arguments declared here so base layers above are always cached
#
# METABASE_VERSION is the primary pin: `docker build .` with no args reproduces
# the :latest image, and add_release_assets.yaml reads this exact line to decide
# which of the versions in metabase_versions.json also gets tagged :latest. It
# must be one of them -- ci/read_compat_versions.sh fails the release otherwise.
# Bump it in the same PR as the deps.edn driver bump.
ARG METABASE_VERSION=0.63.10
ARG METABASE_DUCKDB_DRIVER_VERSION=1.5.5.0
# CI overrides this with the repository the build is running in, so a fork's
# images pull the driver from that fork's own releases instead of from upstream.
ARG METABASE_DUCKDB_DRIVER_REPO=motherduckdb/metabase_duckdb_driver

ADD --chown=metabase:metabase https://downloads.metabase.com/v${METABASE_VERSION}/metabase.jar /home/metabase/
ADD --chown=metabase:metabase https://github.com/${METABASE_DUCKDB_DRIVER_REPO}/releases/download/${METABASE_DUCKDB_DRIVER_VERSION}/duckdb.metabase-driver.jar /home/metabase/plugins/

# Ensure proper file permissions
RUN chmod 755 /home/metabase/metabase.jar && \
    chmod 755 /home/metabase/plugins/duckdb.metabase-driver.jar

EXPOSE 3000

USER metabase

CMD ["java", "-jar", "/home/metabase/metabase.jar"]
