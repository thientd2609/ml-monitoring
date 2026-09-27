"""Scheduled Evidently drift analysis for the ML monitoring stack."""

import json
import os
from datetime import datetime, timedelta
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from airflow import DAG
from airflow.operators.python import PythonOperator


EVIDENTLY_URL = os.getenv("EVIDENTLY_URL", "http://evidently:8001")


def trigger_drift_analysis() -> None:
    payload = json.dumps({"window_size": 100, "threshold": 0.1}).encode("utf-8")
    request = Request(
        f"{EVIDENTLY_URL}/analyze",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urlopen(request, timeout=60) as response:
            if response.status < 200 or response.status >= 300:
                raise RuntimeError(f"Evidently returned HTTP {response.status}")
    except (HTTPError, URLError) as exc:
        raise RuntimeError(f"Drift analysis request failed: {exc}") from exc


with DAG(
    dag_id="ml_monitoring_drift_analysis",
    description="Run Evidently drift analysis on recent production predictions",
    schedule="0 * * * *",
    start_date=datetime(2024, 1, 1),
    catchup=False,
    default_args={
        "owner": "ml-platform",
        "retries": 2,
        "retry_delay": timedelta(minutes=5),
    },
    tags=["ml-monitoring", "evidently"],
) as dag:
    analyze_drift = PythonOperator(
        task_id="analyze_drift",
        python_callable=trigger_drift_analysis,
    )
