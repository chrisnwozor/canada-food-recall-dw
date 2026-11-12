/*
  05_issue_views.sql
  Splits recall reasons ("Egg - Soy") into one row per reason, in ONE place,
  so both SSIS loads (dim_issue and the bridge) use exactly the same rule.

    staging.v_recall_issue   one row per recall per reason   -> feeds bridge_recall_issue
    staging.v_issue_list     one row per distinct reason      -> feeds dim_issue
                             + issue_group (Allergen, Microbial, ...)

  The trap from profiling:
    "Egg - Soy"                 = TWO reasons  -> split on " - "
    "E. Coli - non-pathogenic"  = ONE reason   -> must NOT be split
  So we first rename the two E. Coli values to a form without " - ",
  then split everything else on " - ".

  Expected results (checked against the source file):
    v_issue_list    35 rows
    v_recall_issue  5,573 rows (184 recalls have more than one reason)
*/

USE CanadaFoodDW;
GO

CREATE OR ALTER VIEW staging.v_recall_issue
AS
WITH protected AS (
    -- Step 1: protect the single reasons that contain " - "
    SELECT
        recall_id,
        REPLACE(
            REPLACE(issue,
                'E. Coli - non-pathogenic',   'E. Coli (non-pathogenic)'),
                'E. Coli - other pathogenic', 'E. Coli (other pathogenic)') AS issue
    FROM staging.food_recalls
)
-- Step 2: turn " - " into "|" (STRING_SPLIT needs a one-character separator), then split
SELECT DISTINCT
    p.recall_id,
    TRIM(s.value) AS issue
FROM protected AS p
CROSS APPLY STRING_SPLIT(REPLACE(p.issue, ' - ', '|'), '|') AS s
WHERE TRIM(s.value) <> '';
GO

CREATE OR ALTER VIEW staging.v_issue_list
AS
SELECT DISTINCT
    issue,
    CASE
        WHEN issue IN ('Milk', 'Egg', 'Soy', 'Wheat', 'Gluten', 'Peanut', 'Tree nut',
                       'Sesame seeds', 'Mustard', 'Sulphites', 'Fish',
                       'Crustacean and shellfish')
            THEN 'Allergen'
        WHEN issue IN ('Salmonella', 'Listeria', 'E. Coli O157:H7', 'E. Coli (non-pathogenic)',
                       'E. Coli (other pathogenic)', 'Norovirus', 'Microbial contamination',
                       'Vibrio parahaemolyticus', 'Clostridium botulinum',
                       'Staphylococcus aureus', 'Cyclospora', 'Hepatitis A')
            THEN 'Microbial'
        WHEN issue IN ('Extraneous Material', 'Tampering')
            THEN 'Physical'
        WHEN issue IN ('Chemical', 'Marine biotoxin')
            THEN 'Chemical'
        WHEN issue IN ('Non harmful (quality or spoilage)', 'Labelling and packaging', 'Nutrition')
            THEN 'Quality and labelling'
        WHEN issue = 'Unknown'
            THEN 'Unknown'
        ELSE 'Other'
    END AS issue_group
FROM staging.v_recall_issue;
GO

-- Check the results
SELECT COUNT(*) AS issue_list_rows FROM staging.v_issue_list;      -- expect 35
SELECT COUNT(*) AS recall_issue_rows FROM staging.v_recall_issue;  -- expect 5573
SELECT issue_group, COUNT(*) AS issues
FROM staging.v_issue_list
GROUP BY issue_group
ORDER BY issues DESC;
