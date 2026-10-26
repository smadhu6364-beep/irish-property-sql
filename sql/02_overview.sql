-- Business question: how many homes sell in Ireland each year, and what does a
-- typical home cost?
--
-- We use the median price, not the mean. The median is the middle sale when all
-- sales are lined up from cheapest to dearest, so a handful of €3m houses cannot
-- drag it upwards the way they drag an average. House prices are heavily skewed to
-- the right, which is why official statistics (CSO, Daft) report medians too.

WITH yearly AS (
    SELECT
        sale_year,
        count(*)               AS sales,
        median(price_incl_vat) AS median_price,
        avg(price_incl_vat)    AS mean_price      -- shown only to compare with the median
    FROM market_sales
    GROUP BY sale_year
)
SELECT
    sale_year,
    sales,
    round(median_price) AS median_price_eur,
    round(mean_price)   AS mean_price_eur,
    -- Year-on-year change in the median. LAG looks at the previous row (last year).
    round(100.0 * (median_price / lag(median_price) OVER (ORDER BY sale_year) - 1), 1)
                        AS median_change_pct
FROM yearly
ORDER BY sale_year;
