# PostgreSQL 17.12 with pgBackRest from the image's own Alpine 3.23 repositories.
FROM supabase/postgres:17.12.0.000@sha256:6c056e9a0f81d423c1a81fdf4e6587c16efd3f63960897371dab8ae2694a4714
USER root
RUN apk add --no-cache pgbackrest=2.57.0-r0 \
    && pgbackrest version \
    && mkdir -p /etc/pgbackrest /var/lib/pgbackrest/lock /var/lib/pgbackrest/spool /var/lib/pgbackrest/log \
    && chown -R postgres:postgres /var/lib/pgbackrest
