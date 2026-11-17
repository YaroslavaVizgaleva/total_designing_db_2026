BEGIN;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'inspector') THEN
        ALTER ROLE inspector WITH LOGIN PASSWORD 'NetoSQL2025';
    ELSE
        CREATE ROLE inspector WITH LOGIN PASSWORD 'NetoSQL2025';
    END IF;
END;
$$;

DO $$
BEGIN
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO inspector', current_database());
END;
$$;

GRANT ALL PRIVILEGES ON SCHEMA vizgaleva_food TO inspector;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA vizgaleva_food TO inspector;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA vizgaleva_food TO inspector;
GRANT ALL PRIVILEGES ON ALL ROUTINES IN SCHEMA vizgaleva_food TO inspector;
DO $$
DECLARE
    t record;
BEGIN
    FOR t IN SELECT typname FROM pg_type
              WHERE typnamespace = 'vizgaleva_food'::regnamespace AND typtype = 'e'
    LOOP
        EXECUTE format('GRANT USAGE ON TYPE vizgaleva_food.%I TO inspector', t.typname);
    END LOOP;
END;
$$;
ALTER DEFAULT PRIVILEGES IN SCHEMA vizgaleva_food GRANT ALL PRIVILEGES ON TABLES    TO inspector;
ALTER DEFAULT PRIVILEGES IN SCHEMA vizgaleva_food GRANT ALL PRIVILEGES ON SEQUENCES TO inspector;
ALTER DEFAULT PRIVILEGES IN SCHEMA vizgaleva_food GRANT ALL PRIVILEGES ON ROUTINES  TO inspector;
GRANT USAGE ON SCHEMA information_schema TO inspector;
GRANT USAGE ON SCHEMA pg_catalog         TO inspector;
GRANT SELECT ON information_schema.tables TO inspector;
GRANT SELECT ON pg_catalog.pg_tables      TO inspector;
GRANT USAGE ON SCHEMA exts TO inspector;
GRANT EXECUTE ON FUNCTION exts.uuid_generate_v4() TO inspector;
DO $$
DECLARE
    v_missing text[] := '{}';
BEGIN
    IF NOT has_database_privilege('inspector', current_database(), 'CONNECT') THEN v_missing := v_missing || 'CONNECT на базу'; END IF;
    IF NOT has_schema_privilege('inspector', 'vizgaleva_food', 'USAGE')        THEN v_missing := v_missing || 'USAGE на vizgaleva_food'; END IF;
    IF NOT has_schema_privilege('inspector', 'vizgaleva_food', 'CREATE')       THEN v_missing := v_missing || 'CREATE на vizgaleva_food'; END IF;
    IF NOT has_schema_privilege('inspector', 'information_schema', 'USAGE')    THEN v_missing := v_missing || 'USAGE на information_schema'; END IF;
    IF NOT has_schema_privilege('inspector', 'pg_catalog', 'USAGE')            THEN v_missing := v_missing || 'USAGE на pg_catalog'; END IF;
    IF NOT has_schema_privilege('inspector', 'exts', 'USAGE')                  THEN v_missing := v_missing || 'USAGE на exts'; END IF;
    IF NOT has_function_privilege('inspector', 'exts.uuid_generate_v4()', 'EXECUTE') THEN v_missing := v_missing || 'EXECUTE на exts.uuid_generate_v4()'; END IF;
    IF NOT has_table_privilege('inspector', 'information_schema.tables', 'SELECT') THEN v_missing := v_missing || 'SELECT на information_schema.tables'; END IF;
    IF NOT has_table_privilege('inspector', 'pg_catalog.pg_tables', 'SELECT')      THEN v_missing := v_missing || 'SELECT на pg_catalog.pg_tables'; END IF;

    IF cardinality(v_missing) > 0 THEN
        RAISE EXCEPTION 'У inspector не хватает прав: %', array_to_string(v_missing, ', ');
    END IF;
    RAISE NOTICE 'Права пользователя inspector выданы и проверены';
END;
$$;

COMMIT;
