-- Business question: how big is the price gap between Dublin and the rest of the
-- country, and has it grown or shrunk since 2010?

WITH labelled AS (
    SELECT
        sale_year,
        CASE WHEN county = 'Dublin' THEN 'Dublin' ELSE 'Rest of Ireland' END AS region,
        price_incl_vat
    FROM market_sales
),
by_region AS (
    SELECT sale_year, region, count(*) AS sales, median(price_incl_vat) AS median_price
    FROM labelled
    GROUP BY sale_year, region
),
side_by_side AS (
    -- Conditional aggregation: max(CASE ...) picks out the Dublin value and the
    -- rest-of-Ireland value for each year, turning two rows into two columns.
    SELECT
        sale_year,
        max(CASE WHEN region = 'Dublin'          THEN median_price END) AS dublin_median,
        max(CASE WHEN region = 'Rest of Ireland' THEN median_price END) AS rest_median,
        max(CASE WHEN region = 'Dublin'          THEN sales END)        AS dublin_sales,
        max(CASE WHEN region = 'Rest of Ireland' THEN sales END)        AS rest_sales
    FROM by_region
    GROUP BY sale_year
)
SELECT
    sale_year,
    round(dublin_median)                  AS dublin_median_eur,
    round(rest_median)                    AS rest_median_eur,
    round(dublin_median - rest_median)    AS gap_eur,
    round(dublin_median / rest_median, 2) AS dublin_to_rest_ratio,
    dublin_sales,
    rest_sales
FROM side_by_side
ORDER BY sale_year;
