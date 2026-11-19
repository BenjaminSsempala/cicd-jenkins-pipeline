# Complete CI/CD Pipeline (Jenkins)

A small Flask web service that a Jenkins pipeline builds, tests, containerizes, pushes to a registry and deploys to EC2.

## App

| Route | Response |
|---|---|
| `GET /` | Greeting and app version |
| `GET /health` | `{"status": "ok"}` |
| `GET /add/<a>/<b>` | Sum of two integers |

## Run locally

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
pytest -v
python -m app.main        # http://localhost:5000
```

## Run with Docker

```bash
docker build -t cicd-flask-app .
docker run -d -p 5000:5000 --name cicd-flask-app cicd-flask-app
curl http://localhost:5000/health
```

## Project layout

```
app/main.py         Flask app (create_app factory)
tests/test_app.py   Unit tests (pytest)
Dockerfile          Production image served with gunicorn
```
