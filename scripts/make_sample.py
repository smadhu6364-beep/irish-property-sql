"""Write a 1,000-row sample of the raw register to data/sample/ for the tests.

Rows are picked at an even step through the file so every year is covered.
Bytes are copied as they are, so the sample keeps the original encoding.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "data" / "raw" / "PPR-ALL.csv"
SAMPLE = ROOT / "data" / "sample" / "ppr_sample_1000.csv"
N = 1000


def main() -> None:
    lines = RAW.read_bytes().splitlines(keepends=True)
    header, rows = lines[0], lines[1:]
    step = len(rows) // N
    picked = [rows[i * step] for i in range(N)]
    SAMPLE.parent.mkdir(parents=True, exist_ok=True)
    SAMPLE.write_bytes(header + b"".join(picked))
    print(f"Wrote {len(picked)} rows to {SAMPLE}")


if __name__ == "__main__":
    main()
