import subprocess


def test_migration_applies_and_creates_schema():
    up = subprocess.run(
        [".venv/bin/alembic", "upgrade", "heads"], cwd=".", capture_output=True, text=True
    )
    assert up.returncode == 0, up.stderr

    import psycopg
    dsn = "postgresql://cmpys:cmpys@localhost:5432/cmpys"
    with psycopg.connect(dsn) as conn, conn.cursor() as cur:
        cur.execute("SELECT extname FROM pg_extension WHERE extname='vector'")
        assert cur.fetchone() is not None, "pgvector extension not found"
        cur.execute("SELECT to_regclass('ingest_jobs')")
        assert cur.fetchone()[0] == "ingest_jobs", "ingest_jobs table not found"
        cur.execute("SELECT to_regclass('review_queue')")
        assert cur.fetchone()[0] == "review_queue", "review_queue view not found"
        cur.execute("SELECT column_name FROM information_schema.columns WHERE table_name='idols' AND column_name='embedding'")
        assert cur.fetchone() is not None, "idols.embedding not found"
