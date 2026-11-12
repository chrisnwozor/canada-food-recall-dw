/*
  03_ssis_staging_tables.sql
  Creates the two tables the SSIS package writes into:

    staging.food_recalls             clean, typed food recalls  (blue arrow)
    staging.food_recalls_quarantine  rows that failed conversion (red arrow)

  Run once in SSMS (F5). Running again empties and recreates both tables.
*/

USE CanadaFoodDW;
GO

IF SCHEMA_ID('staging') IS NULL EXEC('CREATE SCHEMA staging');
GO

DROP TABLE IF EXISTS staging.food_recalls;
CREATE TABLE staging.food_recalls (
    recall_id        INT            NOT NULL PRIMARY KEY,  -- from NID (business key)
    title            NVARCHAR(500)  NULL,
    url              NVARCHAR(500)  NULL,
    product          NVARCHAR(500)  NULL,
    issue            NVARCHAR(500)  NULL,
    category         NVARCHAR(500)  NULL,
    recall_class     NVARCHAR(20)   NULL,                  -- Class 1/2/3 or Unknown
    recall_date      DATE           NULL,
    is_archived      BIT            NULL,
    product_missing  BIT            NULL,                  -- 1 = we filled in 'Unknown'
    issue_missing    BIT            NULL,                  -- 1 = we filled in 'Unknown'
    loaded_at        DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);

DROP TABLE IF EXISTS staging.food_recalls_quarantine;
CREATE TABLE staging.food_recalls_quarantine (
    NID              NVARCHAR(20)   NULL,
    Title            NVARCHAR(500)  NULL,
    Product          NVARCHAR(500)  NULL,
    Issue            NVARCHAR(500)  NULL,
    Recall_class     NVARCHAR(50)   NULL,
    Last_updated     NVARCHAR(20)   NULL,
    ErrorCode        INT            NULL,   -- filled in by SSIS: what went wrong
    ErrorColumn      INT            NULL,   -- filled in by SSIS: which column failed
    quarantined_at   DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

PRINT 'Staging and quarantine tables are ready.';
