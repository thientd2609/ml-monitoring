# Copilot instructions for `ml-monitoring`

## What this repository is

This is a Docker Compose MLOps demonstration stack for a wine-quality model:

- `postgres` is the MLflow backend store.
- `minio` stores MLflow artifacts, and `minio-init` creates the artifact bucket.
- `mlflow` provides experiment tracking and the model registry on port 5000.
- `api` is the FastAPI model-serving service on port 8000. It loads the model configured by
  `MLFLOW_TRACKING_URI`, `MODEL_NAME`, and `MODEL_STAGE` during startup.
- `evidently` is a separate FastAPI drift/data-quality service on port 8001. It receives
  prediction data, compares it with uploaded reference data, writes HTML reports, and exposes
  Prometheus metrics.
- `prometheus` scrapes the API and Evidently `/metrics` endpoints using
  `config/prometheus.yml`.
- `grafana` consumes the provisioned Prometheus datasource and dashboard JSON files under
  `config/grafana/`.
- `alertmanager` is disabled by default behind the `telegram` Compose profile; when
  enabled, it receives Prometheus alerts and forwards them to Telegram.
- `airflow-webserver` and `airflow-scheduler` run the hourly
  `ml_monitoring_drift_analysis` DAG against Evidently using a separate `airflow` database.

All services share the `monitoring` Docker network. Host-facing URLs use `localhost`, while
service-to-service configuration must use Compose service names (for example, `mlflow`,
`minio`, `api`, and `evidently`). Docker volumes persist databases, artifacts, dashboards,
and Evidently reference/report data. Production prediction samples are currently held
in-memory by the Evidently process; reference data and reports are persisted in mounted
directories.

The normal dependency chain is: start PostgreSQL/MinIO/MLflow and monitoring, run
`scripts/training.py` to register and promote `wine_quality_model`, then start `api` and
optionally `evidently`. The simulator sends generated predictions to the API and can also
capture them in Evidently and trigger drift analysis.

## Build, run, and validation commands

Run commands from the repository root unless noted otherwise. The documented commands use
the `docker-compose` executable; use the equivalent `docker compose` form if that is the
installed Compose CLI.

### Local configuration and infrastructure

```bash
cp .env.example .env
docker-compose up -d postgres minio minio-init mlflow prometheus grafana
docker-compose ps
```

Train/register the model after MLflow is available:

```bash
pip install -r scripts/requirements.txt
python scripts/training.py
```

Then start serving and drift services:

```bash
docker-compose up -d api
docker-compose up -d evidently
docker-compose up -d airflow-init airflow-webserver airflow-scheduler
```

Useful lifecycle commands:

```bash
docker-compose build
docker-compose logs -f api
docker-compose logs -f evidently
docker-compose restart api evidently
docker-compose down
```

Use `docker-compose down -v` only when intentionally deleting persisted databases,
artifacts, metrics, dashboards, and Evidently data.

### Simulation and smoke tests

Install simulator dependencies in the `simulations` directory:

```bash
cd simulations
pip install -r requirements.txt
```

Run one small simulator smoke test:

```bash
./quick_test.sh
```

Run the CLI directly for focused scenarios:

```bash
python run_simulation.py -n 20 -r 5 -s normal
python run_simulation.py -n 100 -s moderate_drift --analyze
python run_simulation.py -p burst -s normal
python scenarios.py 2
```

The repository has no pytest suite or configured lint/format command. The supported
integration checks are executable shell scripts:

```bash
./scripts/test_evidently.sh
./scripts/test_dashboard.sh
```

These scripts require the relevant Compose services to be running. To run just one check,
run the corresponding script rather than the full set; the scripts themselves do not expose
test selectors.

Basic service checks:

```bash
curl http://localhost:8000/health
curl http://localhost:8001/health
curl http://localhost:8000/metrics
curl http://localhost:8001/metrics
```

Airflow is available at `http://localhost:8080`. Telegram is intentionally disabled
by default. After configuring credentials in `.env`, run
`.\scripts\configure_alertmanager.ps1`, then enable it explicitly with
`docker-compose --profile telegram up -d alertmanager`; Alertmanager is then available
at `http://localhost:9093`.

## Service/API boundaries

The model API exposes `/predict`, `/health`, and `/metrics`; its request accepts a list of
numeric `features` and an optional `feature_names` list. It instruments request, prediction,
latency, error, model-version, feature, and prediction-distribution metrics.

Evidently exposes `/reference` (GET/POST), `/capture` (POST), `/capture/batch` (POST),
`/analyze` (POST), `/reports`, `/reports/{report_name}`, `/production-data` (DELETE), and
`/metrics`. Drift analysis requires reference data and production samples first. Keep the
feature column names and numeric data shape consistent between reference and production
payloads.

## Repository-specific conventions

- Keep service dependencies pinned in the service-local `requirements.txt` files. The API,
  Evidently service, training script, and simulator intentionally have separate environments.
- Preserve the existing Docker build pattern: dependency files are copied and installed
  before application source so Docker layer caching remains effective.
- Put runtime configuration in `.env`/Compose environment variables or the existing YAML
  configuration; do not add a second configuration mechanism. Do not commit `.env`.
- When changing a Prometheus metric, update both the emitting Python service and any
  references in `config/prometheus/`, Grafana dashboards, or alert rules. Metric names are
  part of the dashboard/alert contract.
- When changing Grafana behavior, update the provisioned datasource/dashboard files under
  `config/grafana/`; dashboards are loaded from the mounted read-only directory rather than
  created manually in the container.
- When changing drift payloads or analysis, update the Pydantic models and the simulator's
  capture/analyze calls together. Reference data is written as
  `/app/reference/reference_data.csv` plus optional `metadata.json`; reports are HTML files
  under `/app/reports`.
- Use `localhost` URLs only for commands/scripts running on the host. Code or environment
  values consumed inside Compose containers should use Compose DNS names and container ports.
- The training script is the source of the demo model contract: it trains a
  `RandomForestClassifier` on scikit-learn's wine dataset, logs metrics/model to MLflow,
  registers `wine_quality_model`, and promotes the newest version to the `Production` stage.
- Simulation behavior is configured in `simulations/config.yaml`. Add or change drift
  scenarios and traffic patterns there, and keep CLI choices/help in
  `simulations/run_simulation.py` aligned with that configuration.
- The active Airflow services are `airflow-init`, `airflow-webserver`, and
  `airflow-scheduler`. The PostgreSQL init script creates the Airflow database only when
  the PostgreSQL volume is initialized for the first time.
- Prometheus routes alerts through Alertmanager when the `telegram` profile is enabled;
  keep alert expressions aligned with metric names emitted by `api` and `evidently`.
  Telegram credentials belong in `.env` or CI/CD secrets, never in tracked configuration.
- GitHub Actions validates Python compilation and Compose interpolation on pull requests,
  then builds and publishes the API and Evidently images to GHCR on pushes to `main`.

## Documentation sources

The main operational guide is `README.md`; simulator-specific usage is in
`simulations/README.md`. Keep those documents and this file aligned when changing startup
commands, ports, endpoints, configuration variables, or dashboard behavior.
