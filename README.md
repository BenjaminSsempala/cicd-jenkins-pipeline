# Complete CI/CD Pipeline (Jenkins)

A small Node.js/Express web service that a Jenkins pipeline builds, tests, containerizes, pushes to a registry and deploys to EC2.

## App

| Route | Response |
|---|---|
| `GET /` | Greeting and app version |
| `GET /health` | `{"status": "ok"}` |
| `GET /add/:a/:b` | Sum of two integers (400 if either isn't an integer) |

## Run locally

```bash
npm install
npm test
npm start                 # http://localhost:3000
```

## Run with Docker

```bash
docker build -t cicd-node-app .
docker run -d -p 3000:3000 --name cicd-node-app cicd-node-app
curl http://localhost:3000/health
```

## Project layout

```
src/app.js          Express app (exported so tests can use it without a server)
src/server.js       Starts the server on PORT (default 3000)
tests/app.test.js   Unit tests (Jest + Supertest)
Dockerfile          Production image (node:22-alpine, prod dependencies only)
```
