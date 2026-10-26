"""Run every SQL file in sql/ in order, save each result to results/ and draw charts.

Usage:
    python scripts/run_all.py                 # uses data/raw/PPR-ALL.csv
    python scripts/run_all.py path/to/file.csv

Each SQL file may hold several statements. The result of the last statement in
each file is what gets saved, as results/<file name>.csv.
"""

import sys
from pathlib import Path

import duckdb
import matplotlib

matplotlib.use("Agg")  # draw to files, no window needed
import matplotlib.pyplot as plt  # noqa: E402
import matplotlib.ticker as mtick  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SQL_DIR = ROOT / "sql"
RESULTS_DIR = ROOT / "results"
CHARTS_DIR = ROOT / "charts"
DEFAULT_CSV = ROOT / "data" / "raw" / "PPR-ALL.csv"

# One small palette used on every chart so they look like a set.
INK = "#1f2933"
MUTED = "#7b8794"
GRID = "#e4e7eb"
BLUE = "#2563eb"
ORANGE = "#d97706"
GREEN = "#15803d"


def connect(raw_csv: Path) -> duckdb.DuckDBPyConnection:
    """Open an in-memory DuckDB database and tell it where the raw CSV lives."""
    con = duckdb.connect()
    con.execute("SET VARIABLE raw_csv = ?", [str(raw_csv)])
    return con


def run_sql_file(con: duckdb.DuckDBPyConnection, path: Path):
    """Run one SQL file and return the result of its last statement as a DataFrame."""
    relation = con.sql(path.read_text(encoding="utf-8"))
    return relation.df() if relation is not None else None


def run_all_sql(raw_csv: Path) -> dict:
    con = connect(raw_csv)
    RESULTS_DIR.mkdir(exist_ok=True)
    results = {}
    for path in sorted(SQL_DIR.glob("*.sql")):
        print(f"Running {path.name}")
        df = run_sql_file(con, path)
        results[path.stem] = df
        df.to_csv(RESULTS_DIR / f"{path.stem}.csv", index=False)
    con.close()
    return results


# ---------------------------------------------------------------- charts

def style(ax, title, subtitle=None):
    ax.set_title(title, loc="left", fontsize=13, color=INK, pad=22 if subtitle else 10)
    if subtitle:
        ax.text(0, 1.02, subtitle, transform=ax.transAxes, fontsize=9.5, color=MUTED)
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    for side in ("left", "bottom"):
        ax.spines[side].set_color(GRID)
    ax.tick_params(colors=MUTED, labelsize=9)
    ax.grid(axis="y", color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)


def euro_k(ax, axis="y"):
    fmt = mtick.FuncFormatter(lambda v, _: f"€{v / 1000:,.0f}k")
    (ax.yaxis if axis == "y" else ax.xaxis).set_major_formatter(fmt)


def save(fig, name):
    CHARTS_DIR.mkdir(exist_ok=True)
    fig.savefig(CHARTS_DIR / name, dpi=150, bbox_inches="tight", facecolor="white")
    plt.close(fig)


def draw_charts(r: dict) -> None:
    full_years = r["02_overview"][r["02_overview"].sale_year < r["02_overview"].sale_year.max()]

    # 1. National median and sales volume by year
    fig, ax = plt.subplots(figsize=(9, 4.5))
    ax.bar(full_years.sale_year, full_years.sales, color=GRID, label="Sales (right axis)")
    ax.set_ylabel("Sales", color=MUTED)
    ax.yaxis.set_major_formatter(mtick.FuncFormatter(lambda v, _: f"{v / 1000:,.0f}k"))
    ax2 = ax.twinx()
    ax2.plot(full_years.sale_year, full_years.median_price_eur, color=BLUE, lw=2.5, marker="o")
    euro_k(ax2)
    ax2.tick_params(colors=MUTED, labelsize=9)
    for side in ("top", "right", "left"):
        ax2.spines[side].set_visible(False)
    style(ax, "Median price (line) and number of sales (bars), Ireland",
          "Full-market sales, new homes VAT-inclusive. Full calendar years only.")
    save(fig, "01_median_price_by_year.png")

    # 2. County medians in the latest full year
    c = r["03_by_county"].sort_values("median_price_latest_year")
    year = int(c.latest_year.iloc[0])
    fig, ax = plt.subplots(figsize=(8, 7.5))
    colours = [BLUE if name == "Dublin" else "#93b4f5" for name in c.county]
    ax.barh(c.county, c.median_price_latest_year, color=colours)
    euro_k(ax, "x")
    style(ax, f"Median sale price by county, {year}",
          f"Change since {year - 5} shown at the end of each bar")
    ax.grid(axis="y", visible=False)
    ax.grid(axis="x", color=GRID)
    for y, (v, pct) in enumerate(zip(c.median_price_latest_year, c.median_change_pct)):
        ax.text(v + 4000, y, f"+{pct:.0f}%" if pct >= 0 else f"{pct:.0f}%",
                va="center", fontsize=8, color=MUTED)
    save(fig, "02_county_medians.png")

    # 3. Dublin vs rest of Ireland
    d = r["04_dublin_vs_rest"]
    d = d[d.sale_year < d.sale_year.max()]
    fig, ax = plt.subplots(figsize=(9, 4.5))
    ax.plot(d.sale_year, d.dublin_median_eur, color=BLUE, lw=2.5, label="Dublin")
    ax.plot(d.sale_year, d.rest_median_eur, color=ORANGE, lw=2.5, label="Rest of Ireland")
    ax.fill_between(d.sale_year, d.rest_median_eur, d.dublin_median_eur, color=BLUE, alpha=0.07)
    euro_k(ax)
    ax.legend(frameon=False, fontsize=9)
    style(ax, "Dublin vs rest of Ireland, median sale price", "Shaded area is the gap")
    save(fig, "03_dublin_vs_rest.png")

    # 4. New vs second-hand
    n = r["05_new_vs_second_hand"]
    n = n[n.sale_year < n.sale_year.max()]
    fig, ax = plt.subplots(figsize=(9, 4.5))
    ax.plot(n.sale_year, n.new_median_incl_vat, color=GREEN, lw=2.5, label="New (VAT added back)")
    ax.plot(n.sale_year, n.new_median_as_recorded, color=GREEN, lw=1.5, ls="--",
            label="New (as recorded, mostly ex-VAT)")
    ax.plot(n.sale_year, n.second_hand_median, color=INK, lw=2.5, label="Second-hand")
    euro_k(ax)
    ax.legend(frameon=False, fontsize=9)
    style(ax, "New vs second-hand homes, median sale price",
          "The dashed line shows how far off a comparison would be without the VAT fix")
    save(fig, "04_new_vs_second_hand.png")

    # 5. Seasonality
    s = r["06_seasonality"]
    fig, ax = plt.subplots(figsize=(9, 4.5))
    ax.bar(s.month_name.str[:3], s.avg_share_of_year_pct, color=BLUE)
    ax.axhline(100 / 12, color=MUTED, ls="--", lw=1)
    ax.text(11.4, 100 / 12 + 0.15, "even spread", color=MUTED, fontsize=8, ha="right")
    ax.yaxis.set_major_formatter(mtick.PercentFormatter(decimals=0))
    style(ax, "Share of each year's sales closing in each month",
          "Average across full years since 2010")
    save(fig, "05_seasonality.png")

    # 6. Rolling 12-month median and year-on-year change
    w = r["07_window_functions"]
    fig, (ax, axb) = plt.subplots(2, 1, figsize=(9, 6), sharex=True,
                                  gridspec_kw={"height_ratios": [2, 1]})
    ax.plot(w.month, w.month_median_eur, color=GRID, lw=1, label="Single month")
    ax.plot(w.month, w.rolling_12m_median_eur, color=BLUE, lw=2.5, label="Rolling 12 months")
    euro_k(ax)
    ax.legend(frameon=False, fontsize=9)
    style(ax, "National median price, rolling 12 months",
          "Built with a window function over a 12-month RANGE frame")
    yoy = w.rolling_median_yoy_pct
    axb.bar(w.month, yoy, width=25, color=[GREEN if v >= 0 else ORANGE for v in yoy.fillna(0)])
    axb.yaxis.set_major_formatter(mtick.PercentFormatter(decimals=0))
    style(axb, "Year-on-year change in the rolling median")
    save(fig, "06_rolling_median.png")

    # Portfolio tile, 1200 x 630 pixels (8 x 4.2 inches at 150 dpi)
    fig = plt.figure(figsize=(8, 4.2), dpi=150)
    fig.patch.set_facecolor("#0f172a")
    ax = fig.add_axes([0.07, 0.13, 0.88, 0.52])
    ax.set_facecolor("#0f172a")
    ax.plot(d.sale_year, d.dublin_median_eur, color="#60a5fa", lw=3)
    ax.plot(d.sale_year, d.rest_median_eur, color="#fbbf24", lw=3)
    last = d.iloc[-1]
    ax.text(last.sale_year + 0.2, last.dublin_median_eur, "Dublin", color="#60a5fa",
            va="center", fontsize=10)
    ax.text(last.sale_year + 0.2, last.rest_median_eur, "Rest of\nIreland", color="#fbbf24",
            va="center", fontsize=10)
    ax.set_xlim(d.sale_year.min() - 0.3, d.sale_year.max() + 1.8)
    euro_k(ax)
    ax.tick_params(colors="#94a3b8", labelsize=9)
    for side in ax.spines.values():
        side.set_visible(False)
    ax.grid(axis="y", color="#1e293b")
    fig.text(0.07, 0.88, "Irish property prices, 2010 to today", color="white",
             fontsize=20, weight="bold")
    fig.text(0.07, 0.79, f"SQL analysis of {int(r['01_load_and_clean'].rows_left.iloc[2]):,} "
             "sales on the Property Price Register  |  DuckDB, CTEs, window functions",
             color="#cbd5e1", fontsize=10)
    fig.text(0.07, 0.72, "Median sale price by year", color="#94a3b8", fontsize=9)
    CHARTS_DIR.mkdir(exist_ok=True)
    fig.savefig(CHARTS_DIR / "portfolio_tile.png", dpi=150, facecolor=fig.get_facecolor())
    plt.close(fig)


def main() -> None:
    raw_csv = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_CSV
    if not raw_csv.exists():
        sys.exit(f"{raw_csv} not found. Run scripts/download.py first.")
    results = run_all_sql(raw_csv)
    print(results["01_load_and_clean"].to_string(index=False))
    draw_charts(results)
    print(f"Saved results to {RESULTS_DIR} and charts to {CHARTS_DIR}")


if __name__ == "__main__":
    main()
