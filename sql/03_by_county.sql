-- Business question: in the latest full calendar year, how do prices and sales
-- volumes differ across the 26 counties, and how much has each county's median
-- price moved compared with five years earlier?

WITH latest AS (
    -- The latest full year is the most recent year that has December sales in it.
    -- That way a part-year (such as the current year) is never treated as full.
    SELECT max(sale_year) AS latest_year
    FROM market_sales
    WHERE sale_month = 12
),
county_year AS (
    SELECT county, sale_year,
           count(*)               AS sales,
           median(price_incl_vat) AS median_price
    FROM market_sales
    GROUP BY county, sale_year
)
SELECT
    cur.county,
    cur.sale_year                         AS latest_year,
    cur.sales                             AS sales_latest_year,
    round(cur.median_price)               AS median_price_latest_year,
    prev.sale_year                        AS comparison_year,
    round(prev.median_price)              AS median_price_comparison_year,
    round(100.0 * (cur.median_price / prev.median_price - 1), 1) AS median_change_pct,
    RANK() OVER (ORDER BY cur.median_price DESC)                 AS price_rank
FROM county_year AS cur
JOIN latest
  ON cur.sale_year = latest.latest_year
JOIN county_year AS prev
  ON prev.county = cur.county
 AND prev.sale_year = latest.latest_year - 5
ORDER BY price_rank;
