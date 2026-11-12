/*
  04_create_mart.sql
  Creates the FOOD RECALL DATA MART (star schema) in schema "mart"
  and fills the two fixed dimensions (date and recall class).

    mart.dim_date             one row per calendar day, 1990-2030   (filled here)
    mart.dim_recall_class     Class 1 / 2 / 3 / Unknown            (filled here)
    mart.dim_category         food categories                       (filled by SSIS)
    mart.dim_issue            recall reasons (Milk, Listeria...)    (filled by SSIS)
    mart.dim_recall           details of each recall (title, ...)   (filled by SSIS)
    mart.fact_recall          one row per food recall: keys + count (filled by SSIS)
    mart.bridge_recall_issue  recall <-> reason links               (filled by SSIS)

  Run once in SSMS (F5). Running again rebuilds everything empty.
*/

USE CanadaFoodDW;
GO

IF SCHEMA_ID('mart') IS NULL EXEC('CREATE SCHEMA mart');
GO

-- Drop in the right order (fact and bridge first, because they point at the dimensions)
DROP TABLE IF EXISTS mart.bridge_recall_issue;
DROP TABLE IF EXISTS mart.fact_recall;
DROP TABLE IF EXISTS mart.dim_recall;
DROP TABLE IF EXISTS mart.dim_issue;
DROP TABLE IF EXISTS mart.dim_category;
DROP TABLE IF EXISTS mart.dim_recall_class;
DROP TABLE IF EXISTS mart.dim_date;
GO

/* ---------------- DIMENSIONS ---------------- */

CREATE TABLE mart.dim_date (
    date_key     INT          NOT NULL PRIMARY KEY,   -- e.g. 20261110
    full_date    DATE         NOT NULL,
    [year]       INT          NOT NULL,
    [quarter]    INT          NOT NULL,
    [month]      INT          NOT NULL,
    month_name   NVARCHAR(10) NOT NULL,
    year_month   CHAR(7)      NOT NULL                -- e.g. '2026-11'
);

CREATE TABLE mart.dim_recall_class (
    recall_class_key  INT           NOT NULL PRIMARY KEY,
    recall_class      NVARCHAR(20)  NOT NULL UNIQUE,
    risk_level        NVARCHAR(20)  NOT NULL,
    [description]     NVARCHAR(200) NOT NULL
);

CREATE TABLE mart.dim_category (
    category_key  INT IDENTITY(1,1) NOT NULL PRIMARY KEY,   -- surrogate key
    category      NVARCHAR(500)     NOT NULL UNIQUE
);

CREATE TABLE mart.dim_issue (
    issue_key    INT IDENTITY(1,1) NOT NULL PRIMARY KEY,    -- surrogate key
    issue        NVARCHAR(200)     NOT NULL UNIQUE,
    issue_group  NVARCHAR(50)      NULL                     -- Allergen / Microbial / ... (later)
);

CREATE TABLE mart.dim_recall (
    recall_id         INT           NOT NULL PRIMARY KEY,   -- NID from the source
    title             NVARCHAR(500) NULL,
    product           NVARCHAR(500) NULL,
    url               NVARCHAR(500) NULL,
    is_archived       BIT           NULL,
    product_missing   BIT           NULL,                   -- 1 = we filled in 'Unknown'
    issue_missing     BIT           NULL                    -- 1 = we filled in 'Unknown'
);

/* ---------------- FACT ----------------
   Grain: one row per food recall.
   Only keys and the measure; descriptive text lives in dim_recall. */

CREATE TABLE mart.fact_recall (
    recall_id         INT NOT NULL PRIMARY KEY REFERENCES mart.dim_recall (recall_id),
    date_key          INT NOT NULL REFERENCES mart.dim_date (date_key),
    category_key      INT NOT NULL REFERENCES mart.dim_category (category_key),
    recall_class_key  INT NOT NULL REFERENCES mart.dim_recall_class (recall_class_key),
    recall_count      INT NOT NULL DEFAULT 1                -- the measure: SUM it
);

/* ---------------- BRIDGE ---------------- */

CREATE TABLE mart.bridge_recall_issue (
    recall_id  INT NOT NULL REFERENCES mart.dim_recall (recall_id),
    issue_key  INT NOT NULL REFERENCES mart.dim_issue (issue_key),
    PRIMARY KEY (recall_id, issue_key)
);
GO

/* ---------------- FILL dim_date (1990-01-01 to 2030-12-31) ---------------- */

WITH numbers AS (
    SELECT TOP (DATEDIFF(DAY, '1990-01-01', '2030-12-31') + 1)
           ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n
    FROM sys.all_objects AS a
    CROSS JOIN sys.all_objects AS b
),
days AS (
    SELECT DATEADD(DAY, n, CAST('1990-01-01' AS DATE)) AS d
    FROM numbers
)
INSERT INTO mart.dim_date (date_key, full_date, [year], [quarter], [month], month_name, year_month)
SELECT
    YEAR(d) * 10000 + MONTH(d) * 100 + DAY(d),
    d,
    YEAR(d),
    DATEPART(QUARTER, d),
    MONTH(d),
    DATENAME(MONTH, d),
    CONVERT(CHAR(7), d, 126)
FROM days;

/* ---------------- FILL dim_recall_class ---------------- */

INSERT INTO mart.dim_recall_class (recall_class_key, recall_class, risk_level, [description]) VALUES
    (1,  'Class 1', 'High',     'Reasonable chance of serious health effects or death'),
    (2,  'Class 2', 'Moderate', 'Could cause temporary health problems; serious effects unlikely'),
    (3,  'Class 3', 'Low',      'Unlikely to cause any health problem'),
    (-1, 'Unknown', 'Unknown',  'Class not given or not recognised in the source');
GO

SELECT 'dim_date' AS table_name, COUNT(*) AS row_count FROM mart.dim_date
UNION ALL
SELECT 'dim_recall_class', COUNT(*) FROM mart.dim_recall_class;
