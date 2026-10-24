#!/usr/bin/env python3
"""Synthetic SQL-only benchmark in a private disposable local database.

No production data, HTTP, email, schema migration or application writes.
The reduced schema models the relations read by the RPC, not full app tests.
"""
import hashlib
import json
from pathlib import Path
import statistics
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[2]
CONTAINER = 'supabase_db_festapp-db-tests-pg15'
DATABASE = 'ticket_perf_' + uuid.uuid4().hex[:12]


def command(*args, sql=None):
    return subprocess.run(list(args), input=sql, text=True, capture_output=True, check=True)


def psql(sql):
    return command('docker', 'exec', '-i', CONTAINER, 'psql', '-X', '-U',
                   'postgres', '-d', DATABASE, '-v', 'ON_ERROR_STOP=1', '-At', sql=sql)


def fixture(n, products, seats, halls):
    # Other orders/seats approximate the production table sizes observed on Oct 15.
    return f"""
    TRUNCATE eshop.orders,eshop.tickets,eshop.order_product_ticket,eshop.spots,eshop.blueprints,public.occasions;
    INSERT INTO public.occasions VALUES(1),(2);
    INSERT INTO eshop.orders VALUES(2,2,'{{}}');
    INSERT INTO eshop.tickets SELECT i,2,'background-'||i,NULL,'paid' FROM generate_series(1,10000) i;
    INSERT INTO eshop.order_product_ticket SELECT i,2,1,i FROM generate_series(1,10000) i;
    INSERT INTO eshop.spots SELECT i,2,i%10000+1,'background' FROM generate_series(1,18569) i;
    INSERT INTO eshop.blueprints SELECT i,2,'background','[]','[]' FROM generate_series(2,49) i;
    INSERT INTO eshop.tickets SELECT 10000+i,1,'ticket-'||i,NULL,'paid' FROM generate_series(1,{n}) i;
    INSERT INTO eshop.order_product_ticket
      SELECT 10000+(i-1)*{products}+p,1,p,10000+i
      FROM generate_series(1,{n}) i CROSS JOIN generate_series(1,{products}) p;
    INSERT INTO eshop.orders
    SELECT 1,1,jsonb_build_object('tickets',jsonb_agg(jsonb_build_object(
      'id',10000+i,'products',(SELECT jsonb_agg(jsonb_build_object('price',100+p,'currency_code','CZK')) FROM generate_series(1,{products}) p))))
    FROM generate_series(1,{n}) i;
    INSERT INTO eshop.blueprints SELECT 1,1,'hall',
      coalesce((SELECT jsonb_agg(jsonb_build_object('id',20000+i,'type','spot','group',1)) FROM generate_series(1,{max(n, seats) if seats else 0}) i),'[]'),
      '[{{"id":1,"title":"group"}}]';
    INSERT INTO eshop.blueprints SELECT 49+i,1,'hall-extra-'||i,'[]','[]'
      FROM generate_series(1,{halls-1}) i;
    INSERT INTO eshop.spots SELECT 20000+i,1,10000+(i-1)*{products}+1,'seat-'||i
      FROM generate_series(1,{n if seats else 0}) i;
    ANALYZE;
    """


def measure():
    result = psql("""
      SET statement_timeout='15s';
      DO $bench$
      DECLARE started timestamptz; output jsonb; normalized jsonb; elapsed numeric; i int;
      BEGIN
        FOR i IN 1..4 LOOP
          started:=clock_timestamp(); output:=public.get_tickets_with_details(1);
          elapsed:=extract(epoch FROM clock_timestamp()-started)*1000;
          SELECT jsonb_agg(jsonb_set(t,'{order_product_ticket}',
            (SELECT jsonb_agg(p ORDER BY (p->>'id')::bigint)
             FROM jsonb_array_elements(t->'order_product_ticket') p)) ORDER BY (t->>'id')::bigint)
          INTO normalized FROM jsonb_array_elements(output) t;
          RAISE NOTICE 'RESULT:%',jsonb_build_object('iteration',i,
            'ms',elapsed,'tickets',jsonb_array_length(output),
            'digest',md5(output::text),'normalized_digest',md5(normalized::text));
        END LOOP;
      END $bench$;
    """)
    rows = [json.loads(line.split('RESULT:', 1)[1]) for line in result.stderr.splitlines() if 'RESULT:' in line]
    assert len(rows) == 4
    return rows


def main():
    # Use the authoritative function, excluding unrelated working-tree edits.
    function = command('git', '-C', str(ROOT), 'show',
                       'origin/main:database/functions/eshop/get_tickets_with_details.sql').stdout
    report = {'kind': 'synthetic-reduced-schema-sql-only',
              'function_sha256': hashlib.sha256(function.encode()).hexdigest(),
              'background_opt_rows': 10000, 'background_spots': 18569, 'results': []}
    command('docker', 'exec', CONTAINER, 'createdb', '-U', 'postgres', DATABASE)
    try:
        psql("""
          CREATE SCHEMA eshop; CREATE SCHEMA extensions;
          CREATE TABLE public.occasions(id bigint PRIMARY KEY);
          CREATE TABLE eshop.orders(id bigint PRIMARY KEY, occasion bigint, data jsonb);
          CREATE TABLE eshop.tickets(id bigint PRIMARY KEY,occasion bigint,ticket_symbol text,note text,state text);
          CREATE TABLE eshop.order_product_ticket(id bigint PRIMARY KEY,"order" bigint,product bigint,ticket bigint);
          CREATE INDEX order_product_ticket_ticket_id_idx ON eshop.order_product_ticket(ticket,id);
          CREATE TABLE eshop.spots(id bigint PRIMARY KEY,blueprint bigint,order_product_ticket bigint,title text);
          CREATE TABLE eshop.blueprints(id bigint PRIMARY KEY,occasion bigint,title text,objects jsonb,groups jsonb);
        """ + function)
        report['postgres'] = psql('SHOW server_version; SHOW jit; SHOW jit_above_cost;').stdout.strip().splitlines()
        for n, products, seats, halls in [(1,1,0,1),(14,1,0,1),(14,3,0,1),
                (14,3,250,1),(14,3,250,2),(100,1,700,1),(700,1,0,1),(700,1,700,1)]:
            psql(fixture(n, products, seats, halls))
            original = None
            original_raw = None
            for mode in ('current_indexes', 'order_lookup_only', 'spot_lookup_only', 'candidate_lookup_indexes'):
                psql('DROP INDEX IF EXISTS eshop.bench_opt_order; DROP INDEX IF EXISTS eshop.bench_spots_opt;')
                if mode in ('order_lookup_only', 'candidate_lookup_indexes'):
                    psql('CREATE INDEX bench_opt_order ON eshop.order_product_ticket("order");')
                if mode in ('spot_lookup_only', 'candidate_lookup_indexes'):
                    psql('CREATE INDEX bench_spots_opt ON eshop.spots(order_product_ticket);')
                psql('ANALYZE;')
                rows = measure()
                assert all(r['tickets'] == n for r in rows)
                digests = {r['normalized_digest'] for r in rows}
                assert len(digests) == 1
                if original is None:
                    original = digests
                    original_raw = {r['digest'] for r in rows}
                else:
                    assert digests == original, 'Index trial changed JSON field content'
                row = {'tickets': n, 'products_per_ticket': products, 'blueprints_on_event': halls,
                       'blueprint_objects': max(n,seats) if seats else 0,
                       'mode': mode, 'first_ms': round(rows[0]['ms'], 2),
                       'warm_median_ms': round(statistics.median(r['ms'] for r in rows[1:]), 2),
                       'warm_samples_ms': [round(r['ms'], 2) for r in rows[1:]],
                       'identical_field_content': True,
                       'identical_array_order': {r['digest'] for r in rows} == original_raw}
                row['candidate_index_bytes'] = int(psql("SELECT coalesce(sum(pg_relation_size(indexrelid)),0) FROM pg_index WHERE indexrelid::regclass::text IN ('eshop.bench_opt_order','eshop.bench_spots_opt');").stdout.strip())
                report['results'].append(row)
                print(json.dumps(row), flush=True)
            psql('DROP INDEX eshop.bench_opt_order; DROP INDEX eshop.bench_spots_opt;')
        destination = ROOT/'docs/operations/ticket-details-synthetic-2026-10-15.json'
        destination.write_text(json.dumps(report, indent=2)+'\n')
        print('Saved '+str(destination), flush=True)
    finally:
        # Only the UUID-named database created above belongs to this process.
        command('docker', 'exec', CONTAINER, 'dropdb', '-U', 'postgres', DATABASE)


if __name__ == '__main__':
    main()
