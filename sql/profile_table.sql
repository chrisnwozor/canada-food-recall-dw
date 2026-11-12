/*
  profile_table.sql
  Profiles EVERY column of a table in one go.
  Change the two variables below to profile any table.

  For each column it shows:
    total_rows       how many rows the table has
    null_count       how many are NULL (empty)
    null_pct         the same, as a percentage
    blank_count      how many are just spaces or ''
    distinct_values  how many different values exist
    min_length       shortest value (in characters)
    max_length       longest value (in characters)
    sample_min       the "smallest" value alphabetically
    sample_max       the "largest" value alphabetically

  How to read it:
    distinct_values = total_rows       -> could be a unique ID
    distinct_values small (under ~50)  -> a category; look at its values with GROUP BY
    high null_pct                      -> missing data; find out why
    sample_min / sample_max look odd   -> junk values (e.g. '--')
*/

USE CanadaFoodDW;
GO

DECLARE @schema SYSNAME = N'raw';
DECLARE @table  SYSNAME = N'recalls';

DECLARE @full_name NVARCHAR(300) = QUOTENAME(@schema) + N'.' + QUOTENAME(@table);
DECLARE @sql NVARCHAR(MAX);

SELECT @sql = STRING_AGG(CAST(
    N'SELECT '
    + CAST(c.column_id AS NVARCHAR(10)) + N' AS column_order, '
    + N'N' + QUOTENAME(c.name, '''') + N' AS column_name, '
    + N'COUNT(*) AS total_rows, '
    + N'SUM(CASE WHEN ' + QUOTENAME(c.name) + N' IS NULL THEN 1 ELSE 0 END) AS null_count, '
    + N'CAST(100.0 * SUM(CASE WHEN ' + QUOTENAME(c.name) + N' IS NULL THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,1)) AS null_pct, '
    + N'SUM(CASE WHEN LTRIM(RTRIM(' + QUOTENAME(c.name) + N')) = N'''' THEN 1 ELSE 0 END) AS blank_count, '
    + N'COUNT(DISTINCT ' + QUOTENAME(c.name) + N') AS distinct_values, '
    + N'MIN(LEN(' + QUOTENAME(c.name) + N')) AS min_length, '
    + N'MAX(LEN(' + QUOTENAME(c.name) + N')) AS max_length, '
    + N'LEFT(MIN(' + QUOTENAME(c.name) + N'), 40) AS sample_min, '
    + N'LEFT(MAX(' + QUOTENAME(c.name) + N'), 40) AS sample_max '
    + N'FROM ' + @full_name
  AS NVARCHAR(MAX)), N' UNION ALL ') WITHIN GROUP (ORDER BY c.column_id)
FROM sys.columns AS c
WHERE c.object_id = OBJECT_ID(@full_name);

SET @sql = @sql + N' ORDER BY column_order;';

EXEC sp_executesql @sql;
