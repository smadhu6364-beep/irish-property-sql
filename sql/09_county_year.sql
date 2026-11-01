-- Business question: for every county and every year, how many homes sold, at
-- what median price, and how did that median move on the year before? This is
-- the table behind the interactive dashboard (filter by county and year range).

WITH county_year AS (
    SELECT county, sale_year,
           count(*)               AS sales,
           median(price_incl_vat) AS median_price
    FROM market_sales
    GROUP BY county, sale_year
),
with_change AS (
    SELECT county, sale_year, sales, median_price,
           -- LAG reads the same county's median from the previous year
           lag(median_price) OVER (PARTITION BY county ORDER BY sale_year) AS prev_median
    FROM county_year
)
SELECT
    county,
    sale_year,
    sales,
    round(median_price)                                   AS median_price_eur,
    round(100.0 * (median_price / prev_median - 1), 1)    AS median_yoy_pct,
    -- each county's place in that year's price league table
    RANK() OVER (PARTITION BY sale_year ORDER BY median_price DESC) AS price_rank
FROM with_change
ORDER BY county, sale_year;
