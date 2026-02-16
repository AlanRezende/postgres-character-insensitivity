# postgres-character-insensitivity

> **[Leia em Portugues Brasileiro](README.pt-br.md)**

PostgreSQL 18 setup with case-insensitive and accent-insensitive collation using ICU, running on Docker.

## Purpose

Test project to validate that PostgreSQL can match Brazilian Portuguese names ignoring case and diacritics (accents, cedilha). For example, a query for `joao silva` matches `João Silva`, `JOÃO SILVA`, etc.

## How it works

### ICU collation

PostgreSQL supports ICU (International Components for Unicode) collations. We create a custom non-deterministic collation called `ci`:

```sql
CREATE COLLATION ci (provider = icu, locale = 'und-u-ks-level1', deterministic = false);
```

Key parameters:
- **`provider = icu`** — uses the ICU library instead of the OS locale
- **`locale = 'und-u-ks-level1'`** — `und` = language-neutral, `ks-level1` = collation strength at level 1 (base characters only), which ignores both case and accents
- **`deterministic = false`** — required for case/accent insensitive equality. Without this, PostgreSQL adds a byte-level tiebreaker that makes `=` comparisons exact again

### Collation strength levels

| Level | Compares | Ignores |
|-------|----------|---------|
| `ks-level1` | Base characters only | Case + accents |
| `ks-level2` | Base + accents | Case only |
| `ks-level3` | Base + accents + case | Nothing (default) |

### Why `COLLATE ci` on columns?

Setting `ICU_LOCALE` on the database or via `POSTGRES_INITDB_ARGS` only affects **sorting order**. The database's default collation remains deterministic, so `=` still does byte-level comparison. There is no way to set a non-deterministic collation as the database-wide default in PostgreSQL. You must apply `COLLATE ci` explicitly on text columns:

```sql
CREATE TABLE clients (
    name VARCHAR(255) COLLATE ci NOT NULL
);
```

### Why template1 AND the current database?

`POSTGRES_DB` creates the database **before** init scripts run, so it doesn't inherit collations added to `template1` during init. The `ci` collation must be created on both:

- **`template1`** — so any future databases created on this cluster inherit it automatically
- **`test` (current database)** — because it was already created from `template1` before the init script ran

```sql
\c template1
CREATE COLLATION IF NOT EXISTS ci (...);
\c test
CREATE COLLATION IF NOT EXISTS ci (...);
```

## Setup

```bash
docker compose up -d
```

Connection string:
```
postgresql://test:test_dev_password@localhost:5432/test
```

### Clean restart (required when changing initdb settings)

```bash
docker compose down -v
docker compose up -d
```

## Files

| File | Description |
|------|-------------|
| `docker-compose.yml` | PostgreSQL 18 container config |
| `init.sql` | Creates the `ci` collation, extensions, `clients` table with index |
| `seed_clients.data` | ~7800 Brazilian names with accents and cedilhas |

The seed file uses `.data` extension instead of `.sql` because the Docker entrypoint auto-executes all `.sql` files in `/docker-entrypoint-initdb.d/`. Since `init.sql` already runs the seed via `\i`, a `.sql` extension would cause it to run twice.

## Testing queries

Connect to the database:
```bash
docker exec -it test-postgress psql -U test
```

### Case insensitive

```sql
SELECT * FROM clients WHERE name = 'joão silva';
SELECT * FROM clients WHERE name = 'JOÃO SILVA';
SELECT * FROM clients WHERE name = 'João Silva';
-- All three return the same result
```

### Accent insensitive (no diacritics)

```sql
SELECT * FROM clients WHERE name = 'joao silva';
-- Matches "João Silva"

SELECT * FROM clients WHERE name LIKE '%conceicao%';
-- Matches "Conceição"

SELECT * FROM clients WHERE name LIKE '%goncalves%';
-- Matches "Gonçalves"
```

## Testing the index

Use `EXPLAIN ANALYZE` to see if the query planner uses the index:

```sql
EXPLAIN ANALYZE SELECT * FROM clients WHERE name = 'joao silva';
```

Expected output with ~7800 rows — the planner should choose **Index Scan** or **Bitmap Index Scan**:

```
Bitmap Heap Scan on clients  (cost=4.30..11.41 rows=2 width=58)
  ->  Bitmap Index Scan on idx_clients_name  (cost=0.00..4.30 rows=2 width=0)
        Index Cond: ((name)::text = 'joao silva'::text)
```

With very few rows (< 100), PostgreSQL may prefer a **Seq Scan** instead since it's faster for small tables. To force index usage for testing:

```sql
SET enable_seqscan = off;
EXPLAIN ANALYZE SELECT * FROM clients WHERE name = 'joao silva';
```

This confirms the index works with the `ci` collation. Reset with:

```sql
SET enable_seqscan = on;
```

### Quick reference

| Plan node | Meaning |
|-----------|---------|
| `Seq Scan` | Full table scan (no index used) |
| `Index Scan` | Index used directly |
| `Bitmap Index Scan` | Index used via bitmap (common for few matching rows) |
| `Index Only Scan` | Index covers all requested columns |

## Notes on PostgreSQL 18 Docker image

PostgreSQL 18+ changed the data directory structure. The volume must mount at `/var/lib/postgresql` (not `/var/lib/postgresql/data` as in older versions). See [docker-library/postgres#1259](https://github.com/docker-library/postgres/pull/1259).
