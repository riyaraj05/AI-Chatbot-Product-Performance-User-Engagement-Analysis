"""Small helpers to run the project's .sql files from Python."""
from __future__ import annotations
import re
import sqlite3
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "data" / "chatbot.db"
SQL_DIR = ROOT / "sql"


def get_connection(db_path: Path = DB_PATH) -> sqlite3.Connection:
    if not Path(db_path).exists():
        raise FileNotFoundError("Database not found. Run: python src/generate_data.py then python src/load_data.py")
    return sqlite3.connect(db_path)


def run_sql_file(filename: str, con: sqlite3.Connection | None = None) -> dict[str, pd.DataFrame]:
    """
    Run every query in a .sql file and return {query_name: DataFrame}.

    Queries are separated by a header comment of the form:   -- Q: query_name
    """
    own_con = con is None
    con = con or get_connection()
    text = (SQL_DIR / filename).read_text()
    parts = re.split(r"^-- Q: *(\S+)\s*$", text, flags=re.MULTILINE)
    # parts = [preamble, name1, body1, name2, body2, ...]
    results = {}
    for name, body in zip(parts[1::2], parts[2::2]):
        results[name] = pd.read_sql_query(body.strip().rstrip(";"), con)
    if own_con:
        con.close()
    return results
