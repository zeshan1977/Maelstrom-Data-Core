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
