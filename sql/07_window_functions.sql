-- Business question: smoothing out month-to-month noise, what is the trend in the
-- national median price, and how fast is it rising compared with a year earlier?
--
-- Two ideas are shown here:
--   CTE (WITH name AS (...)): a named, temporary result we can build on step by step.
--   Window function (... OVER (...)): a calculation across a set of rows related to
--   the current row, without collapsing them into one row the way GROUP BY does.

WITH rolling AS (
    -- Step 1: for each sale, the median of every sale in the 12 months up to and
    -- including that sale's month. RANGE works on the date values, so
    -- "INTERVAL 11 MONTH PRECEDING" means this month plus the 11 before it.
    -- This is the median of all sales in the window, not a median of monthly
    -- medians, which would give small months too much weight.
    SELECT
        sale_month_start,
        median(price_incl_vat) OVER (
            ORDER BY sale_month_start
            RANGE BETWEEN INTERVAL 11 MONTH PRECEDING AND CURRENT ROW
        ) AS rolling_12m_median
    FROM market_sales
),
monthly_rolling AS (
    -- Step 2: every sale in the same month has the same rolling value, so we keep
    -- one row per month.
    SELECT sale_month_start, any_value(rolling_12m_median) AS rolling_12m_median
    FROM rolling
    GROUP BY sale_month_start
),
month_stats AS (
    -- Step 3: plain GROUP BY for each month's own count and median.
    SELECT sale_month_start, count(*) AS sales, median(price_incl_vat) AS month_median
    FROM market_sales
    GROUP BY sale_month_start
)
SELECT
    r.sale_month_start                          AS month,
    s.sales,
    round(s.month_median)                       AS month_median_eur,
    round(r.rolling_12m_median)                 AS rolling_12m_median_eur,
    -- Step 4: LAG(x, 12) reads the value from 12 rows back, which is 12 months
    -- earlier because there is one row per month with no gaps.
    round(100.0 * (r.rolling_12m_median
        / lag(r.rolling_12m_median, 12) OVER (ORDER BY r.sale_month_start) - 1), 1)
                                                AS rolling_median_yoy_pct,
    -- A running total, another common window function: market sales since Jan 2010.
    sum(s.sales) OVER (ORDER BY r.sale_month_start
                       ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
                                                AS cumulative_sales
FROM monthly_rolling AS r
JOIN month_stats AS s USING (sale_month_start)
ORDER BY month;
