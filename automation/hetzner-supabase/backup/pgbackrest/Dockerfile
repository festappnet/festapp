# Keep the exact production PostgreSQL/extensions image; add packaged pgBackRest.
FROM supabase/postgres:17.6.1.136@sha256:a9946f08d31e8eb1149229c94e5c26603a9233116807cbbd93d75179cbac516a
USER root
RUN apk add --no-cache pgbackrest=2.57.0-r0 \
    && pgbackrest version \
    && mkdir -p /etc/pgbackrest /var/lib/pgbackrest/lock /var/lib/pgbackrest/spool /var/lib/pgbackrest/log \
    && chown -R postgres:postgres /var/lib/pgbackrest
