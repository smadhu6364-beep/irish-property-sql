-- Business question: can we turn the raw Property Price Register download into one
-- clean, typed table of residential sales that we trust enough to analyse?
--
-- Input:  data/raw/PPR-ALL.csv, as published (Windows-1252 encoding, prices as text
--         such as "€343,000.00", dates as DD/MM/YYYY, Yes/No flags).
-- Output: table `sales` (every valid sale), view `market_sales` (the rows we use for
--         price analysis) and table `cleaning_log` (rows removed by each rule).
-- The file path is passed in by scripts/run_all.py as the variable raw_csv.

-- Step 0: load the file exactly as text. Every column is read as VARCHAR so nothing
-- gets silently converted, and we give the columns short names (the original
-- headers contain spaces and a euro sign, which are awkward to type in SQL).
CREATE OR REPLACE TABLE raw_sales AS
SELECT *
FROM read_csv(
    getvariable('raw_csv'),
    encoding    = 'windows-1252',   -- the euro sign is byte 0x80 in this encoding
    header      = true,
    all_varchar = true,
    names = ['sale_date_text', 'address', 'county', 'eircode', 'price_text',
             'not_full_market_price_text', 'vat_exclusive_text',
             'description', 'size_description']
);

-- Step 1: convert text to proper types.
--   * Dates: try_strptime reads DD/MM/YYYY. "try_" means a bad value becomes NULL
--     instead of stopping the whole query.
--   * Prices: strip everything that is not a digit or a full stop, so
--     "€343,000.00" becomes "343000.00", then cast to a number.
--   * Yes/No flags become TRUE/FALSE.
--   * Description: the register uses English and Irish labels. "New Dwelling" and
--     "Teach/Árasán Cónaithe Nua" both mean a new home; everything else is second-hand.
CREATE OR REPLACE TABLE typed_sales AS
SELECT
    CAST(try_strptime(sale_date_text, '%d/%m/%Y') AS DATE)                AS sale_date,
    trim(address)                                                         AS address,
    trim(county)                                                          AS county,
    nullif(trim(eircode), '')                                             AS eircode,
    try_cast(regexp_replace(price_text, '[^0-9.]', '', 'g') AS DOUBLE)    AS price_eur,
    coalesce(not_full_market_price_text = 'Yes', FALSE)                   AS not_full_market_price,
    coalesce(vat_exclusive_text = 'Yes', FALSE)                           AS vat_exclusive,
    CASE
        WHEN description ILIKE 'New%' OR description ILIKE '%Nua' THEN TRUE
        ELSE FALSE
    END                                                                   AS is_new_dwelling,
    nullif(trim(size_description), '')                                    AS size_description
FROM raw_sales;

-- Step 2: drop rows where the date or price could not be read, or the price is not
-- a positive number. Without a date or price a row is useless for this analysis.
CREATE OR REPLACE TABLE parsed_sales AS
SELECT *
FROM typed_sales
WHERE sale_date IS NOT NULL
  AND price_eur IS NOT NULL
  AND price_eur > 0;

-- Step 3: remove exact duplicates. If two rows share the same date, address,
-- county, price and flags they are the same sale entered twice, so we keep one.
CREATE OR REPLACE TABLE sales AS
SELECT DISTINCT
    sale_date,
    year(sale_date)                          AS sale_year,
    month(sale_date)                         AS sale_month,
    CAST(date_trunc('month', sale_date) AS DATE) AS sale_month_start,
    address,
    county,
    eircode,
    price_eur,
    not_full_market_price,
    vat_exclusive,
    is_new_dwelling,
    size_description,
    -- New homes are usually listed without VAT. Adding Ireland's 13.5% residential
    -- VAT rate puts them on the same footing as second-hand homes (no VAT), so
    -- this is the price we compare everywhere.
    CASE WHEN vat_exclusive THEN round(price_eur * 1.135, 2) ELSE price_eur END
                                             AS price_incl_vat
FROM parsed_sales;

-- Step 4: the analysis view. We keep only sales the register marks as full market
-- price, and drop prices under €10,000 or over €10 million. Very low "prices" are
-- usually family transfers or part shares; very high ones are mostly bulk deals
-- where a whole block of apartments is recorded with one combined price.
CREATE OR REPLACE VIEW market_sales AS
SELECT *
FROM sales
WHERE NOT not_full_market_price
  AND price_incl_vat BETWEEN 10000 AND 10000000;

-- Cleaning log: how many rows each rule removed. Each count comes from comparing
-- the tables built above, so the numbers always match the data.
CREATE OR REPLACE TABLE cleaning_log AS
WITH counts AS (
    SELECT
        (SELECT count(*) FROM raw_sales)    AS raw_rows,
        (SELECT count(*) FROM parsed_sales) AS parsed_rows,
        (SELECT count(*) FROM sales)        AS deduped_rows,
        (SELECT count(*) FROM sales WHERE NOT not_full_market_price) AS full_market_rows,
        (SELECT count(*) FROM market_sales) AS market_rows
)
SELECT 0 AS step, 'Rows in the raw file' AS rule,
       CAST(NULL AS BIGINT) AS rows_removed, raw_rows AS rows_left FROM counts
UNION ALL
SELECT 1, 'Date or price could not be parsed, or price not above zero',
       raw_rows - parsed_rows, parsed_rows FROM counts
UNION ALL
SELECT 2, 'Exact duplicate rows',
       parsed_rows - deduped_rows, deduped_rows FROM counts
UNION ALL
SELECT 3, 'Marked "not full market price" (kept in sales, left out of price analysis)',
       deduped_rows - full_market_rows, full_market_rows FROM counts
UNION ALL
SELECT 4, 'Price under €10,000 or over €10m (kept in sales, left out of price analysis)',
       full_market_rows - market_rows, market_rows FROM counts
ORDER BY step;

SELECT * FROM cleaning_log;
