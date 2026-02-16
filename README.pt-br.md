# postgres-character-insensitivity

Setup do PostgreSQL 18 com collation case-insensitive e accent-insensitive usando ICU, rodando em Docker.

## Objetivo

Projeto de teste para validar que o PostgreSQL consegue buscar nomes em portugues brasileiro ignorando maiusculas/minusculas e diacriticos (acentos, cedilha). Por exemplo, uma query por `joao silva` encontra `João Silva`, `JOÃO SILVA`, etc.

## Como funciona

### Collation ICU

O PostgreSQL suporta collations ICU (International Components for Unicode). Criamos uma collation customizada nao-deterministica chamada `ci`:

```sql
CREATE COLLATION ci (provider = icu, locale = 'und-u-ks-level1', deterministic = false);
```

Parametros principais:
- **`provider = icu`** — usa a biblioteca ICU em vez do locale do SO
- **`locale = 'und-u-ks-level1'`** — `und` = neutro em relacao ao idioma, `ks-level1` = forca de comparacao nivel 1 (apenas caracteres base), ignorando maiusculas/minusculas e acentos
- **`deterministic = false`** — obrigatorio para igualdade case/accent insensitive. Sem isso, o PostgreSQL adiciona um desempate byte a byte que torna comparacoes com `=` exatas novamente

### Niveis de forca da collation

| Nivel | Compara | Ignora |
|-------|---------|--------|
| `ks-level1` | Apenas caracteres base | Maiusc/minusc + acentos |
| `ks-level2` | Base + acentos | Apenas maiusc/minusc |
| `ks-level3` | Base + acentos + maiusc/minusc | Nada (padrao) |

### Por que `COLLATE ci` nas colunas?

Definir `ICU_LOCALE` no banco ou via `POSTGRES_INITDB_ARGS` afeta apenas a **ordem de classificacao**. A collation padrao do banco permanece deterministica, entao `=` ainda faz comparacao byte a byte. Nao ha como definir uma collation nao-deterministica como padrao do banco inteiro no PostgreSQL. Voce precisa aplicar `COLLATE ci` explicitamente nas colunas de texto:

```sql
CREATE TABLE clients (
    name VARCHAR(255) COLLATE ci NOT NULL
);
```

### Por que template1 E o banco atual?

`POSTGRES_DB` cria o banco **antes** dos scripts de init rodarem, entao ele nao herda collations adicionadas ao `template1` durante o init. A collation `ci` precisa ser criada em ambos:

- **`template1`** — para que futuros bancos criados neste cluster herdem automaticamente
- **`test` (banco atual)** — porque ele ja foi criado a partir do `template1` antes do script de init rodar

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

String de conexao:
```
postgresql://test:test_dev_password@localhost:5432/test
```

### Restart limpo (necessario ao alterar configuracoes de initdb)

```bash
docker compose down -v
docker compose up -d
```

## Arquivos

| Arquivo | Descricao |
|---------|-----------|
| `docker-compose.yml` | Configuracao do container PostgreSQL 18 |
| `init.sql` | Cria a collation `ci`, extensoes, tabela `clients` com indice |
| `seed_clients.data` | ~7800 nomes brasileiros com acentos e cedilhas |

O arquivo de seed usa extensao `.data` em vez de `.sql` porque o entrypoint do Docker executa automaticamente todos os arquivos `.sql` em `/docker-entrypoint-initdb.d/`. Como o `init.sql` ja roda o seed via `\i`, uma extensao `.sql` faria ele rodar duas vezes.

## Queries de teste

Conecte ao banco:
```bash
docker exec -it test-postgress psql -U test
```

### Case insensitive

```sql
SELECT * FROM clients WHERE name = 'joão silva';
SELECT * FROM clients WHERE name = 'JOÃO SILVA';
SELECT * FROM clients WHERE name = 'João Silva';
-- Todas as tres retornam o mesmo resultado
```

### Accent insensitive (sem diacriticos)

```sql
SELECT * FROM clients WHERE name = 'joao silva';
-- Encontra "João Silva"

SELECT * FROM clients WHERE name LIKE '%conceicao%';
-- Encontra "Conceição"

SELECT * FROM clients WHERE name LIKE '%goncalves%';
-- Encontra "Gonçalves"
```

## Testando o indice

Use `EXPLAIN ANALYZE` para ver se o planner usa o indice:

```sql
EXPLAIN ANALYZE SELECT * FROM clients WHERE name = 'joao silva';
```

Saida esperada com ~7800 linhas — o planner deve escolher **Index Scan** ou **Bitmap Index Scan**:

```
Bitmap Heap Scan on clients  (cost=4.30..11.41 rows=2 width=58)
  ->  Bitmap Index Scan on idx_clients_name  (cost=0.00..4.30 rows=2 width=0)
        Index Cond: ((name)::text = 'joao silva'::text)
```

Com poucas linhas (< 100), o PostgreSQL pode preferir um **Seq Scan** ja que e mais rapido para tabelas pequenas. Para forcar o uso do indice em testes:

```sql
SET enable_seqscan = off;
EXPLAIN ANALYZE SELECT * FROM clients WHERE name = 'joao silva';
```

Isso confirma que o indice funciona com a collation `ci`. Resete com:

```sql
SET enable_seqscan = on;
```

### Referencia rapida

| No do plano | Significado |
|-------------|-------------|
| `Seq Scan` | Scan completo da tabela (sem indice) |
| `Index Scan` | Indice usado diretamente |
| `Bitmap Index Scan` | Indice usado via bitmap (comum para poucas linhas) |
| `Index Only Scan` | Indice cobre todas as colunas requisitadas |

## Notas sobre a imagem Docker do PostgreSQL 18

O PostgreSQL 18+ mudou a estrutura do diretorio de dados. O volume deve ser montado em `/var/lib/postgresql` (nao em `/var/lib/postgresql/data` como em versoes anteriores). Veja [docker-library/postgres#1259](https://github.com/docker-library/postgres/pull/1259).
