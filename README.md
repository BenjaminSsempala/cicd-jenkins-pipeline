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

## Deploy server (Terraform)

`infra/` creates the EC2 instance the pipeline deploys to: an RSA key pair, a security group (HTTP 80 from anywhere, SSH 22 from the Jenkins machine's IP) and an Amazon Linux 2 `t2.micro` that installs Docker on first boot.

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # set ssh_allowed_cidr to your public IP /32
terraform init
terraform apply
terraform output                               # public IP, SSH command, private key path
```

The private key is written to `infra/keys/` (gitignored) and goes into the Jenkins `ec2_ssh` credential. Run `terraform destroy` when the lab is finished.

## Project layout

```
src/app.js          Express app (exported so tests can use it without a server)
src/server.js       Starts the server on PORT (default 3000)
tests/app.test.js   Unit tests (Jest + Supertest)
Dockerfile          Multi-stage build: deps, test (--target test), runtime
infra/              Terraform for the EC2 deploy server and key pair
```
