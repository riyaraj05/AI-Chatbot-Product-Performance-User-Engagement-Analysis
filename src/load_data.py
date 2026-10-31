"""Load the generated CSVs into a local SQLite database (data/chatbot.db)."""
import argparse
import sqlite3
from pathlib import Path

import pandas as pd

TABLES = {"users.csv": "users", "conversations.csv": "conversations", "feedback.csv": "feedback"}


def main(raw_dir: Path, db_path: Path) -> None:
    if db_path.exists():
        db_path.unlink()
    con = sqlite3.connect(db_path)
    for csv_name, table in TABLES.items():
        path = raw_dir / csv_name
        if not path.exists():
            raise FileNotFoundError(f"Missing {path}. Run: python src/generate_data.py")
        df = pd.read_csv(path)
        df.to_sql(table, con, index=False)
        print(f"loaded {table:<14}{len(df):>8,} rows")
    cur = con.cursor()
    cur.execute("CREATE INDEX idx_conv_user ON conversations(user_id)")
    cur.execute("CREATE INDEX idx_conv_start ON conversations(started_at)")
    cur.execute("CREATE INDEX idx_fb_conv ON feedback(conversation_id)")
    con.commit()
    con.close()
    print(f"\nDatabase written to {db_path}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", default="data/raw", type=Path)
    ap.add_argument("--db", default="data/chatbot.db", type=Path)
    a = ap.parse_args()
    main(a.raw, a.db)
