import os
from fastapi import FastAPI, HTTPException
from sqlalchemy import create_engine, text
from app.etl import run_pipeline

app = FastAPI(title="Maelstrom Data Core API")

DB_URL = os.getenv("DATABASE_URL", "postgresql://maelstrom:wickedpassword@db:5432/maelstrom_db")
engine = create_engine(DB_URL)

@app.post("/api/v1/trigger-etl", tags=["Pipeline"])
def trigger_etl():
    """Manually trigger the ETL pipeline."""
    try:
        result = run_pipeline()
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/v1/telemetry", tags=["Data"])
def get_telemetry(limit: int = 10):
    """Fetch the latest processed data from PostgreSQL."""
    try:
        with engine.connect() as conn:
            # Safely fetch latest records
            query = text("SELECT * FROM weather_telemetry ORDER BY timestamp DESC LIMIT :limit")
            result = conn.execute(query, {"limit": limit})
            # Convert SQLAlchemy rows to list of dicts for JSON serialization
            rows = [dict(row._mapping) for row in result]
            
        if not rows:
            return {"message": "No data found. Run the /api/v1/trigger-etl endpoint first."}
            
        return {"data": rows}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
