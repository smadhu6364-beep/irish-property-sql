-- Business question: are there busy and quiet months for property sales, and is
-- the pattern the same every year?
--
-- Note: the register records the date the sale closed (when stamp duty was filed),
-- not the day the offer was agreed. Closings lag agreements by a few months.
-- We count all valid sales here, including non-market ones, because the question
-- is about activity, not price.

WITH monthly AS (
    -- Sales per calendar month, full years only (we skip the current part-year).
    SELECT sale_year, sale_month, count(*) AS sales
    FROM sales
    WHERE sale_year < (SELECT max(sale_year) FROM sales)
    GROUP BY sale_year, sale_month
),
with_share AS (
    -- Each month's share of its own year, so busy and quiet years compare fairly.
    -- sum(sales) OVER (PARTITION BY sale_year) is the total for that year, repeated
    -- on every row of the year. RANK orders the months within each year.
    SELECT
        *,
        100.0 * sales / sum(sales) OVER (PARTITION BY sale_year)     AS share_of_year_pct,
        RANK() OVER (PARTITION BY sale_year ORDER BY sales DESC)      AS rank_in_year
    FROM monthly
)
SELECT
    sale_month,
    monthname(make_date(2000, sale_month, 1)) AS month_name,
    round(avg(sales))                         AS avg_sales,
    min(sales)                                AS min_sales,
    max(sales)                                AS max_sales,
    round(avg(share_of_year_pct), 1)          AS avg_share_of_year_pct,
    count(*) FILTER (WHERE rank_in_year = 1)  AS years_as_busiest_month,
    count(*)                                  AS years_counted
FROM with_share
GROUP BY sale_month
ORDER BY sale_month;
