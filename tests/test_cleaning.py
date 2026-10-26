"""Checks on the cleaning logic in sql/01_load_and_clean.sql.

The tests run the real SQL file against the committed 1,000-row sample and against
a tiny hand-made CSV with known problems, so no download is needed.
"""

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

from run_all import connect, run_sql_file  # noqa: E402

CLEAN_SQL = ROOT / "sql" / "01_load_and_clean.sql"
SAMPLE = ROOT / "data" / "sample" / "ppr_sample_1000.csv"

HEADER = ("Date of Sale (dd/mm/yyyy),Address,County,Eircode,Price (€),"
          "Not Full Market Price,VAT Exclusive,Description of Property,"
          "Property Size Description\n")


@pytest.fixture(scope="module")
def sample_con():
    con = connect(SAMPLE)
    run_sql_file(con, CLEAN_SQL)
    yield con
    con.close()


@pytest.fixture
def tiny_con(tmp_path):
    """Five rows written in Windows-1252, like the real file."""
    rows = [
        # a normal second-hand sale
        '"01/02/2020","1 Main St, Navan","Meath","","€250,000.00","No","No",'
        '"Second-Hand Dwelling house /Apartment",""',
        # the same row again: an exact duplicate
        '"01/02/2020","1 Main St, Navan","Meath","","€250,000.00","No","No",'
        '"Second-Hand Dwelling house /Apartment",""',
        # a new home, VAT exclusive
        '"15/06/2021","2 New Rd, Cork","Cork","","€300,000.00","No","Yes",'
        '"New Dwelling house /Apartment",""',
        # a family transfer, not full market price
        '"20/07/2021","3 Old Lane, Sligo","Sligo","","€5,000.00","Yes","No",'
        '"Second-Hand Dwelling house /Apartment",""',
        # a broken date
        '"31/13/2021","4 Bad Date, Cavan","Cavan","","€100,000.00","No","No",'
        '"Second-Hand Dwelling house /Apartment",""',
    ]
    path = tmp_path / "tiny.csv"
    path.write_bytes((HEADER + "\n".join(rows) + "\n").encode("cp1252"))
    con = connect(path)
    run_sql_file(con, CLEAN_SQL)
    yield con
    con.close()


def scalar(con, query):
    return con.execute(query).fetchone()[0]


def test_sample_loads_all_rows(sample_con):
    assert scalar(sample_con, "SELECT count(*) FROM raw_sales") == 1000


def test_euro_prices_parse_to_numbers(sample_con):
    # every price in the sample should be read, and none should be zero or negative
    assert scalar(sample_con, "SELECT count(*) FROM typed_sales WHERE price_eur IS NULL") == 0
    assert scalar(sample_con, "SELECT min(price_eur) FROM sales") > 0


def test_dates_are_in_register_range(sample_con):
    first, last = sample_con.execute("SELECT min(sale_date), max(sale_date) FROM sales").fetchone()
    assert first.year == 2010
    assert last.year >= 2025


def test_vat_added_only_when_flagged(sample_con):
    # second-hand and VAT-inclusive rows keep their price; flagged rows get +13.5%
    assert scalar(sample_con, """
        SELECT count(*) FROM sales
        WHERE NOT vat_exclusive AND price_incl_vat <> price_eur""") == 0
    assert scalar(sample_con, """
        SELECT count(*) FROM sales
        WHERE vat_exclusive AND abs(price_incl_vat - price_eur * 1.135) > 0.01""") == 0


def test_market_view_excludes_non_market_sales(sample_con):
    assert scalar(sample_con,
                  "SELECT count(*) FROM market_sales WHERE not_full_market_price") == 0


def test_cleaning_log_adds_up(sample_con):
    log = sample_con.execute("SELECT * FROM cleaning_log ORDER BY step").df()
    for i in range(1, len(log)):
        assert log.rows_left[i - 1] - log.rows_removed[i] == log.rows_left[i]


def test_tiny_file_rules(tiny_con):
    log = tiny_con.execute("SELECT step, rows_removed, rows_left FROM cleaning_log ORDER BY step").fetchall()
    assert log == [
        (0, None, 5),  # five rows in
        (1, 1, 4),     # bad date removed
        (2, 1, 3),     # duplicate removed
        (3, 1, 2),     # family transfer left out of price analysis
        (4, 0, 2),     # nothing outside the price range
    ]


def test_tiny_file_values(tiny_con):
    price, incl, is_new = tiny_con.execute(
        "SELECT price_eur, price_incl_vat, is_new_dwelling FROM sales WHERE county = 'Cork'"
    ).fetchone()
    assert price == 300000
    assert incl == pytest.approx(340500)
    assert is_new is True
