# Runbook: CI/CD Pipeline (Jenkins → Docker Hub → EC2)

How to set up, run, roll back, troubleshoot and tear down the pipeline for the `cicd-node-app` Express service.

## 1. Architecture

```
 Developer PC (Ubuntu 24.04)                                     AWS eu-west-1
 ┌────────────────────────────────────┐
 │ Jenkins LTS 2.580.2 (:8080)        │ ── git clone ───────►  GitHub (public repo)
 │  Checkout → Install/Build → Test   │
 │  → Docker Build → Scan Image       │ ── docker push ─────►  Docker Hub
 │  → Push Image → Deploy             │                        benjaminssempala/cicd-node-app
 │  → Smoke Test → cleanup            │
 │                                    │ ── ssh (port 22) ───►  EC2 t2.micro, Amazon Linux 2
 └────────────────────────────────────┘                          docker pull + docker run -p 80:3000
                                                                    ▲
                                       browser ── http (port 80) ───┘
```

| Component     | Details                                                                                                                                                    |
| ------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| App           | Node.js 22 / Express, port 3000. Routes `/`, `/health`, `/add/:a/:b`                                                                                 |
| Image         | Multi-stage Dockerfile (`base`, `deps`, `test`, `runtime`). Runtime runs as user `node`, holds production dependencies only, and has npm removed |
| CI server     | Jenkins LTS installed with apt on the developer PC, builds on the built-in node                                                                            |
| Registry      | Docker Hub, tagged with the Jenkins build number plus `latest`                                                                                           |
| Deploy server | EC2 created with Terraform in `infra/`. Destroyed after the evidence was captured; see section 9 to recreate it                                          |

## 2. Prerequisites

| Tool           | Version used                   | Check                            |
| -------------- | ------------------------------ | -------------------------------- |
| Java (OpenJDK) | 21                             | `java -version`                |
| Jenkins LTS    | 2.580.2                        | bottom-right of any Jenkins page |
| Docker         | 29.6.1                         | `docker --version`             |
| Terraform      | 1.17.2                         | `terraform version`            |
| AWS CLI        | 2.x, credentials for eu-west-1 | `aws sts get-caller-identity`  |
| Accounts       | GitHub, Docker Hub             |                                  |

## 3. One-time setup

### 3.1 Install Jenkins (Ubuntu)

```bash
sudo apt update && sudo apt install -y fontconfig openjdk-21-jre
sudo wget -O /etc/apt/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt update && sudo apt install -y jenkins
sudo usermod -aG docker jenkins && sudo systemctl restart jenkins   # lets pipeline steps run docker
sudo cat /var/lib/jenkins/secrets/initialAdminPassword               # unlock password
```

Open **http://127.0.0.1:8080**, unlock Jenkins, choose **Install suggested plugins**, and create the admin user.

### 3.2 Plugins

The suggested plugins include **Pipeline**, **Git**, **Credentials Binding**, Timestamper and Workspace Cleanup. Then add **Docker Pipeline** and **SSH Agent** from *Manage Jenkins → Plugins → Available plugins*.

### 3.3 Deploy server (Terraform)

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars    # ssh_allowed_cidr = "<your public IP>/32"
terraform init && terraform apply
terraform output                                # public_ip, ssh_command, private_key_path
```

This creates an RSA key pair, a security group (port 22 from the Jenkins machine only, port 80 from anywhere) and an Amazon Linux 2 `t2.micro` that installs Docker on first boot. The private key is written to `infra/keys/cicd-deploy-key.pem` (gitignored, mode 0400).

### 3.4 Credentials

*Manage Jenkins → Credentials → System → Global credentials → Add Credentials.* The IDs must match exactly, and an ID can't be changed after creation.

| ID                  | Kind                          | Values                                                                                |
| ------------------- | ----------------------------- | ------------------------------------------------------------------------------------- |
| `registry_creds`  | Username with password        | Docker Hub username + **access token** (Read & Write), not the account password |
| `ec2_ssh`         | SSH Username with private key | Username `ec2-user`, private key = contents of `infra/keys/cicd-deploy-key.pem`   |
| `git_credentials` | Not needed                    | The repository is public                                                              |

### 3.5 Pipeline job

*New Item → Pipeline*, then under **Pipeline**:

- Definition: **Pipeline script from SCM**
- SCM: **Git**, URL `https://github.com/BenjaminSsempala/cicd-jenkins-pipeline.git`, no credentials
- Branch: `*/main`
- Script path: `Jenkinsfile`

## 4. Running the pipeline

Open the job and click **Build with Parameters** (**Build Now** on the very first build). `EC2_HOST` defaults to the current server. Override it if the server has been recreated.

| Stage         | What happens                                                                                         | Fails when                                                    |
| ------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| Checkout      | Clones the repo at the configured branch                                                             | Repo or branch unreachable                                    |
| Install/Build | `npm ci` in a throwaway `node:22-alpine` container                                               | Lock file out of sync                                         |
| Test          | `npm test` (Jest + Supertest) in the same image                                                    | Any unit test fails                                           |
| Docker Build  | Builds the `runtime` stage, tagged `:<build number>` and `:latest`                             | Dockerfile error                                              |
| Scan Image    | Trivy scans the image for HIGH and CRITICAL vulnerabilities that have a fix                          | Any such vulnerability is found, so the image is never pushed |
| Push Image    | `docker login --password-stdin` with `registry_creds`, then pushes both tags                     | Wrong or expired token                                        |
| Deploy        | SSH with `ec2_ssh`: pull the new tag, replace the `cicd-node-app` container, prune unused images | SSH blocked or Docker not running                             |
| Smoke Test    | `curl --retry 10 http://<host>/health` from Jenkins                                                | App not reachable on port 80                                  |
| Post (always) | `docker logout`, remove local images, wipe the workspace                                           |                                                               |

### Verify a deployment

```bash
curl http://<EC2_HOST>/            # {"message":"Hello from the CI/CD pipeline!","version":"<build number>"}
curl http://<EC2_HOST>/health      # {"status":"ok"}
ssh -i infra/keys/cicd-deploy-key.pem ec2-user@<EC2_HOST> 'docker ps && docker logs cicd-node-app'
```

`version` is the Jenkins build number, so it shows which build is live. `docker ps` should show `(healthy)` from the image's `HEALTHCHECK`.

## 5. Rollback

Every build is pushed under its own build number, so any earlier image can be redeployed. For example, to roll back to build 4:

```bash
ssh -i infra/keys/cicd-deploy-key.pem ec2-user@<EC2_HOST> '
  docker pull benjaminssempala/cicd-node-app:4 &&
  docker rm -f cicd-node-app &&
  docker run -d --name cicd-node-app --restart unless-stopped -p 80:3000 -e APP_VERSION=4 benjaminssempala/cicd-node-app:4'
```

For a lasting fix, revert the bad commit (`git revert <sha> && git push`) and run the pipeline again.

## 6. Security

| Area                   | Control                                                                                                                                                                                                                                                    |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Secrets in code        | None. The Jenkinsfile refers to credential IDs only. `*.pem`, `*.tfstate` and `*.tfvars` are gitignored                                                                                                                                              |
| Secret exposure        | The token is available only inside `withCredentials {}` and the SSH key only inside `sshagent {}`. Values are masked in logs, the token goes through `--password-stdin`, and the `sh` steps use single quotes so Groovy never interpolates secrets |
| Registry login         | Docker Hub access token rather than the password. `docker logout` runs after every build                                                                                                                                                                 |
| Vulnerability scanning | Trivy blocks the push on HIGH or CRITICAL vulnerabilities that have a fix                                                                                                                                                                                  |
| Image                  | Multi-stage build: no test tools, no npm, runs as the non-root `node` user, with a health check                                                                                                                                                          |
| Network                | SSH (22) only from the Jenkins machine's IP. HTTP (80) public                                                                                                                                                                                              |
| EC2                    | IMDSv2 required, encrypted root disk, no IAM role attached                                                                                                                                                                                                 |
| Jenkins                | Login required, CSRF protection on                                                                                                                                                                                                                         |

**Known limitations, acceptable for this lab:**

- HTTP only, no TLS.
- The Docker Hub repository is public.
- The `jenkins` user is in the `docker` group, which is effectively root on the Jenkins machine.
- Builds run on the Jenkins controller rather than separate agents.
- The Terraform-generated SSH private key is also stored in the local `terraform.tfstate`, so the state file must never be committed or shared.
- The EC2 host key is trusted on first connection (`StrictHostKeyChecking=accept-new`).

## 7. Troubleshooting

| Symptom                                                            | Cause                                                                                                    | Fix                                                                                                                                                                                    |
| ------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `HTTP ERROR 431 Request Header Fields Too Large` opening Jenkins | Cookies from other apps on `localhost` (any port) exceed Jetty's header limit                          | Use `http://127.0.0.1:8080`, or clear the cookies for `localhost`                                                                                                                  |
| Deploy: `ssh: Could not resolve hostname :`                      | On a job's first build, parameters are empty because Jenkins hasn't read the `parameters {}` block yet | Fixed by the `DEPLOY_HOST` fallback in the Jenkinsfile. Otherwise re-run with **Build with Parameters**                                                                        |
| Push: `Credentials 'registry_creds' could not be found`          | Credential ID typo (for example `regirstry_creds`)                                                     | IDs can't be renamed. Delete the credential and recreate it with the exact ID                                                                                                          |
| `permission denied ... /var/run/docker.sock`                     | The `jenkins` user isn't in the `docker` group                                                       | `sudo usermod -aG docker jenkins && sudo systemctl restart jenkins`                                                                                                                  |
| Deploy: `ssh: connect to host ... Connection timed out`          | The Jenkins machine's public IP changed, so the security group blocks SSH                                | Update `ssh_allowed_cidr` in `infra/terraform.tfvars` (`curl -s https://checkip.amazonaws.com`), then `terraform apply`                                                        |
| Deploy: `Permission denied (publickey)`                          | Wrong key or username in `ec2_ssh`                                                                     | Username `ec2-user`. Paste the whole `.pem`, including the BEGIN and END lines                                                                                                     |
| Scan Image fails                                                   | A HIGH or CRITICAL vulnerability with a fix is in the image                                              | Read the Trivy table. Update the affected package or base image, or remove tools not needed at runtime (npm was removed for this reason)                                               |
| Smoke Test fails, Deploy passed                                    | Container crashed or port 80 is blocked                                                                  | `ssh … 'docker ps -a && docker logs cicd-node-app'`. Check that the security group allows port 80                                                                                   |
| Forgotten Jenkins admin password                                   |                                                                                                          | Set `<useSecurity>false</useSecurity>` in `/var/lib/jenkins/config.xml`, restart Jenkins, reset the password under *Users*, then set it back to `true` and restart immediately |

## 8. Cleanup

**After every build (automatic):** the `post { always }` block logs out of Docker Hub, removes the build's images from the Jenkins machine and wipes the workspace. Deploy removes the old container and prunes unused images on EC2.

**End of the lab:**

```bash
cd infra && terraform destroy                  # removes the instance, security group and key pair
sudo systemctl stop jenkins                    # optional: stop Jenkins on the PC
sudo systemctl disable jenkins                 # optional: don't start it on boot
docker volume rm trivy-cache                   # optional: Trivy's vulnerability database cache
```

Delete the Docker Hub access token in *Account settings → Personal access tokens* if it's no longer needed.

## 9. Recreating the environment (for example, for a demo)

**1. Check that Jenkins is running.** Open http://127.0.0.1:8080 and log in.

```bash
systemctl is-active jenkins || sudo systemctl start jenkins
```

**2. Update the allowed SSH IP** if your public IP has changed since `terraform.tfvars` was written.

```bash
curl -s https://checkip.amazonaws.com          # compare with ssh_allowed_cidr in infra/terraform.tfvars
```

**3. Create the server.**

```bash
cd infra
terraform init                                 # only needed on a fresh clone
terraform apply
terraform output public_ip
```

Wait about 2 minutes for the first-boot script to install Docker. To check:

```bash
ssh -i infra/keys/cicd-deploy-key.pem ec2-user@<public_ip> 'docker --version && docker ps'
```

**4. Replace the `ec2_ssh` credential's key.** Terraform generates a new key pair each time it creates the server, so the old key no longer works. In *Manage Jenkins → Credentials → ec2_ssh → Update*, replace the private key with the contents of:

```bash
cat infra/keys/cicd-deploy-key.pem
```

**5. Clear the old host key if the new server reuses an earlier IP.** Otherwise SSH refuses to connect with `REMOTE HOST IDENTIFICATION HAS CHANGED`.

```bash
sudo -u jenkins ssh-keygen -R <public_ip>
```

**6. Run the pipeline** with **Build with Parameters**, setting `EC2_HOST` to the new `public_ip`. The default in the Jenkinsfile (`DEFAULT_EC2_HOST`) is the destroyed server's IP. Either type the new one each time, or update `DEFAULT_EC2_HOST` and push.

**7. Verify:** open `http://<public_ip>/`. `version` shows the new build number.

**8. Tear down afterwards:** `cd infra && terraform destroy`.

**Fallback without AWS:** run the published image locally and show the saved evidence in `screenshots/`.

```bash
docker run -d --rm -p 3000:3000 --name cicd-node-app benjaminssempala/cicd-node-app:latest   # http://127.0.0.1:3000
```

### Demo script (about 5 minutes)

1. Open the live app and point out `version` (the build number).
2. Change the message in `src/app.js` and update the matching test. Commit and push.
3. Run the pipeline and narrate each stage: tests gate everything, Trivy blocks vulnerable images, credentials are masked, SSH is allowed only from the Jenkins machine.
4. Refresh the browser: new message, new `version`. Show the new tag on Docker Hub.
5. Optional: push a commit that breaks a test. The pipeline stops at **Test**, and the live app stays on the previous version.

Run one build an hour or so beforehand, so the Docker layer cache and Trivy's vulnerability database are already downloaded and the live run is quick.
