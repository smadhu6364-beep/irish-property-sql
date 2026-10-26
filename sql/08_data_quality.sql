-- Business question: how far can we trust this data? Where are the gaps, odd
-- values and inconsistencies an analyst should know about before quoting numbers?
--
-- Each check is one small SELECT; UNION ALL stacks them into a single report.

WITH quartiles AS (
    SELECT quantile_cont(price_incl_vat, 0.25) AS q1,
           quantile_cont(price_incl_vat, 0.75) AS q3
    FROM market_sales
),
address_county AS (
    -- Pull the word after "Co." out of the address, e.g. "Co.Dublin" -> DUBLIN.
    SELECT county,
           regexp_extract(upper(address), 'CO\.? ?([A-Z]+)', 1) AS county_in_address
    FROM sales
),
checks AS (
    SELECT 1 AS check_no, 'Rows in clean sales table' AS check_name,
           CAST(count(*) AS DOUBLE) AS value, 'all valid sales after cleaning' AS note
    FROM sales
    UNION ALL
    SELECT 2, 'Missing address', count(*) FILTER (WHERE address IS NULL OR address = ''), ''
    FROM sales
    UNION ALL
    SELECT 3, 'Missing county', count(*) FILTER (WHERE county IS NULL OR county = ''), ''
    FROM sales
    UNION ALL
    SELECT 4, 'Missing Eircode, all years (%)',
           round(100.0 * count(*) FILTER (WHERE eircode IS NULL) / count(*), 1),
           'Eircodes only appear on the register in volume from 2021'
    FROM sales
    UNION ALL
    SELECT 5, 'Missing Eircode, sales from 2022 on (%)',
           round(100.0 * count(*) FILTER (WHERE eircode IS NULL) / count(*), 1), ''
    FROM sales WHERE sale_year >= 2022
    UNION ALL
    SELECT 6, 'Property size band filled in (%)',
           round(100.0 * count(*) FILTER (WHERE size_description IS NOT NULL) / count(*), 1),
           'size is rarely given, so price per square metre is not possible'
    FROM sales
    UNION ALL
    SELECT 7, 'Not full market price sales (%)',
           round(100.0 * count(*) FILTER (WHERE not_full_market_price) / count(*), 1),
           'left out of price analysis'
    FROM sales
    UNION ALL
    SELECT 8, 'Full market sales under €10,000', count(*), 'left out: likely errors or part shares'
    FROM sales WHERE NOT not_full_market_price AND price_incl_vat < 10000
    UNION ALL
    SELECT 9, 'Full market sales over €10m', count(*), 'left out: mostly bulk apartment deals'
    FROM sales WHERE NOT not_full_market_price AND price_incl_vat > 10000000
    UNION ALL
    SELECT 10, 'Prices above Q3 + 3 x IQR (%)',
           round(100.0 * count(*) FILTER (WHERE price_incl_vat > q3 + 3 * (q3 - q1)) / count(*), 1),
           'kept: dear homes are real, which is why we report medians'
    FROM market_sales, quartiles
    UNION ALL
    SELECT 11, 'Address + date pairs with more than one price', count(*),
           'often one deal split across units, or a later correction'
    FROM (SELECT address, sale_date FROM sales
          GROUP BY address, sale_date HAVING count(DISTINCT price_eur) > 1)
    UNION ALL
    SELECT 12, 'Address says "Co. X" but county column differs', count(*),
           'address text and county field disagree'
    FROM address_county
    WHERE county_in_address IN ('CARLOW','CAVAN','CLARE','CORK','DONEGAL','DUBLIN','GALWAY',
          'KERRY','KILDARE','KILKENNY','LAOIS','LEITRIM','LIMERICK','LONGFORD','LOUTH','MAYO',
          'MEATH','MONAGHAN','OFFALY','ROSCOMMON','SLIGO','TIPPERARY','WATERFORD',
          'WESTMEATH','WEXFORD','WICKLOW')
      AND county_in_address <> upper(county)
    UNION ALL
    SELECT 13, 'New dwellings recorded VAT inclusive (%)',
           round(100.0 * count(*) FILTER (WHERE NOT vat_exclusive) / count(*), 1),
           'VAT already included, so we do not add it again'
    FROM sales WHERE is_new_dwelling
    UNION ALL
    SELECT 14, 'Second-hand dwellings flagged VAT exclusive',
           count(*) FILTER (WHERE vat_exclusive),
           'should be zero: second-hand homes carry no VAT'
    FROM sales WHERE NOT is_new_dwelling
    UNION ALL
    SELECT 15, 'Sales dated in the future', count(*) FILTER (WHERE sale_date > current_date),
           'should be zero'
    FROM sales
)
SELECT * FROM checks
ORDER BY check_no;
