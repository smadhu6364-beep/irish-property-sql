-- Business question: do new homes sell for more than second-hand homes, and how
-- big a share of the market are they?
--
-- VAT: new homes carry VAT at 13.5% and most new-home rows are recorded VAT
-- exclusive (the "VAT Exclusive" flag is Yes). Second-hand homes have no VAT.
-- Comparing raw register prices would understate new homes by about 13.5%.
-- In 01_load_and_clean.sql we built price_incl_vat, which adds the 13.5% back
-- only when the flag is Yes. Below we show both so the effect is visible.
--
-- FILTER (WHERE ...) applies an aggregate to a subset of the group's rows. It does
-- the same job as wrapping the value in CASE WHEN ... END, but reads more clearly.

SELECT
    sale_year,
    count(*) FILTER (WHERE is_new_dwelling)                              AS new_sales,
    count(*) FILTER (WHERE NOT is_new_dwelling)                          AS second_hand_sales,
    round(100.0 * count(*) FILTER (WHERE is_new_dwelling) / count(*), 1) AS new_share_pct,
    round(median(price_eur)      FILTER (WHERE is_new_dwelling))         AS new_median_as_recorded,
    round(median(price_incl_vat) FILTER (WHERE is_new_dwelling))         AS new_median_incl_vat,
    round(median(price_incl_vat) FILTER (WHERE NOT is_new_dwelling))     AS second_hand_median,
    round(100.0 * (median(price_incl_vat) FILTER (WHERE is_new_dwelling)
                 / median(price_incl_vat) FILTER (WHERE NOT is_new_dwelling) - 1), 1)
                                                                         AS new_premium_pct
FROM market_sales
GROUP BY sale_year
ORDER BY sale_year;
