/*
  02_staging_food_recalls.sql
  Builds the STAGING layer for food recalls: typed, trimmed, standardised.

  Flow:   raw.recalls  ->  staging.food_recalls              (good rows)
                       ->  staging.food_recalls_quarantine   (rows that break a critical rule)

  Rules (from our data profiling):
    LEVEL 1 - critical -> quarantine the row
      * NID is missing or not a number
      * Last_updated is missing or not a valid date
      * the same NID appears more than once (keep the newest, quarantine the rest)

    LEVEL 2 - optional -> keep the row, fill a default, set a flag
      * Product missing       -> 'Unknown', product_missing = 1
      * Issue missing         -> 'Unknown', issue_missing = 1
      * Recall class '--'/NULL -> 'Unknown'

    Scope: only Organization = 'CFIA' (food). Other agencies are out of scope.

  The load procedure is IDEMPOTENT: it empties staging and rebuilds it from raw
  inside one transaction. Run it as often as you like; the result is the same.
*/

USE CanadaFoodDW;
GO

/* ---------- 1. Tables ---------- */

DROP TABLE IF EXISTS staging.food_recalls;
CREATE TABLE staging.food_recalls (
    recall_id        INT            NOT NULL PRIMARY KEY,   -- from NID (business key)
    title            NVARCHAR(500)  NOT NULL,
    url              NVARCHAR(500)  NULL,
    product          NVARCHAR(500)  NOT NULL,
    issue            NVARCHAR(500)  NOT NULL,                -- may hold several reasons; split later
    category         NVARCHAR(500)  NOT NULL,
    recall_class     NVARCHAR(20)   NOT NULL,                -- Class 1 / Class 2 / Class 3 / Unknown
    recall_date      DATE           NOT NULL,
    is_archived      BIT            NULL,
    product_missing  BIT            NOT NULL,
    issue_missing    BIT            NOT NULL,
    loaded_at        DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);

DROP TABLE IF EXISTS staging.food_recalls_quarantine;
CREATE TABLE staging.food_recalls_quarantine (
    NID                 NVARCHAR(MAX),
    Title               NVARCHAR(MAX),
    Product             NVARCHAR(MAX),
    Issue               NVARCHAR(MAX),
    Recall_class        NVARCHAR(MAX),
    Last_updated        NVARCHAR(MAX),
    quarantine_reason   NVARCHAR(200)  NOT NULL,
    quarantined_at      DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

/* ---------- 2. Load procedure ---------- */

CREATE OR ALTER PROCEDURE staging.usp_load_food_recalls
AS
BEGIN
    SET NOCOUNT ON;

    -- Step A: check every food row once, and work out the problem (if any)
    DROP TABLE IF EXISTS #checked;

    WITH food AS (
        SELECT
            r.*,
            TRY_CAST(TRIM(r.NID) AS INT)                AS nid_int,
            TRY_CONVERT(DATE, TRIM(r.Last_updated), 23) AS date_clean   -- 23 = yyyy-mm-dd
        FROM raw.recalls AS r
        WHERE TRIM(r.Organization) = 'CFIA'
    ),
    numbered AS (
        SELECT
            f.*,
            -- 1 = newest copy of this NID, 2+ = older copies
            ROW_NUMBER() OVER (PARTITION BY f.nid_int ORDER BY f.date_clean DESC) AS copy_number
        FROM food AS f
    )
    SELECT
        n.*,
        CASE
            WHEN n.nid_int IS NULL    THEN 'NID missing or not a number'
            WHEN n.date_clean IS NULL THEN 'Last_updated missing or not a valid date'
            WHEN n.copy_number > 1    THEN 'Duplicate NID (older copy)'
        END AS quarantine_reason   -- NULL = the row passed every critical rule
    INTO #checked
    FROM numbered AS n;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Step B: empty both tables (this is what makes reruns safe)
        TRUNCATE TABLE staging.food_recalls;
        TRUNCATE TABLE staging.food_recalls_quarantine;

        -- Step C: bad rows go to quarantine, untouched, with the reason
        INSERT INTO staging.food_recalls_quarantine
            (NID, Title, Product, Issue, Recall_class, Last_updated, quarantine_reason)
        SELECT NID, Title, Product, Issue, Recall_class, Last_updated, quarantine_reason
        FROM #checked
        WHERE quarantine_reason IS NOT NULL;

        -- Step D: good rows are cleaned and typed
        INSERT INTO staging.food_recalls
            (recall_id, title, url, product, issue, category, recall_class,
             recall_date, is_archived, product_missing, issue_missing)
        SELECT
            nid_int,
            TRIM(Title),
            NULLIF(TRIM(URL), ''),
            COALESCE(NULLIF(TRIM(Product), ''), 'Unknown'),
            COALESCE(NULLIF(TRIM(Issue), ''), 'Unknown'),
            COALESCE(NULLIF(TRIM(Category), ''), 'Unknown'),
            CASE
                -- standard values
                WHEN TRIM(Recall_class) IN ('Class 1', 'Type I')   THEN 'Class 1'
                WHEN TRIM(Recall_class) IN ('Class 2', 'Type II')  THEN 'Class 2'
                WHEN TRIM(Recall_class) IN ('Class 3', 'Type III') THEN 'Class 3'
                -- combined values like 'Class 1 - Class 2': keep the MOST serious (safest choice)
                WHEN TRIM(Recall_class) LIKE 'Class 1 -%' OR TRIM(Recall_class) LIKE '%- Class 1' THEN 'Class 1'
                WHEN TRIM(Recall_class) LIKE 'Class 2 -%' OR TRIM(Recall_class) LIKE '%- Class 2' THEN 'Class 2'
                -- '--', NULL, anything else
                ELSE 'Unknown'
            END,
            date_clean,
            TRY_CAST(TRIM(Archived) AS BIT),
            CASE WHEN NULLIF(TRIM(Product), '') IS NULL THEN 1 ELSE 0 END,
            CASE WHEN NULLIF(TRIM(Issue), '')   IS NULL THEN 1 ELSE 0 END
        FROM #checked
        WHERE quarantine_reason IS NULL;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;   -- any error: undo everything
        THROW;
    END CATCH;

    -- Step E: a short report
    SELECT
        (SELECT COUNT(*) FROM #checked)                          AS food_rows_in_raw,
        (SELECT COUNT(*) FROM staging.food_recalls)              AS loaded_to_staging,
        (SELECT COUNT(*) FROM staging.food_recalls_quarantine)   AS sent_to_quarantine;
END;
GO

/* ---------- 3. Run it ---------- */
EXEC staging.usp_load_food_recalls;
