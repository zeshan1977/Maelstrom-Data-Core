# 1. Fix the requirement to support Pandas SQL inserts
sed -i 's/asyncpg/psycopg2-binary/' requirements.txt

# 2. Write the optimized ETL pipeline (app/etl.py)
cat << 'EOF' > app/etl.py
import os
import requests
import pandas as pd
from sqlalchemy import create_engine

# Pull DB URL from environment or fallback to docker-compose settings
DB_URL = os.getenv("DATABASE_URL", "postgresql://maelstrom:wickedpassword@db:5432/maelstrom_db")

def run_pipeline():
    """Fetches real-time weather data, transforms it with Pandas, and loads it into PostgreSQL."""
    # 1. EXTRACT: Fetch data from a free, public API (Open-Meteo)
    url = "https://api.open-meteo.com/v1/forecast?latitude=51.5085&longitude=-0.1257&current_weather=true"
    response = requests.get(url)
    response.raise_for_status()
    data = response.json()

    # 2. TRANSFORM: Flatten JSON and clean data using Pandas
    df = pd.json_normalize(data['current_weather'])
    df['latitude'] = data['latitude']
    df['longitude'] = data['longitude']
    
    # Convert string time to datetime object
    df['timestamp'] = pd.to_datetime(df['time'])
    df.drop(columns=['time'], inplace=True)

    # 3. LOAD: Push to PostgreSQL
    engine = create_engine(DB_URL)
    # Optimized load: appends data, omits pandas index
    df.to_sql('weather_telemetry', engine, if_exists='append', index=False)
    
    return {"status": "success", "rows_inserted": len(df), "latest_temp": df['temperature'].iloc[0]}
EOF

# 3. Write the optimized FastAPI endpoints (app/main.py)
cat << 'EOF' > app/main.py
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
EOF

# 4. Commit the new code
git add .
git commit -m "feat: added actual Pandas ETL logic and FastAPI endpoints"
