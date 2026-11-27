# Evidence

## 1. Tools

| Screenshot | Shows |
|---|---|
| [jenkins-plugins-installed.png](01-tools/jenkins-plugins-installed.png) | Jenkins plugins installed (Git, GitHub, Pipeline, ...) |
| [docker-version-local-run.png](01-tools/docker-version-local-run.png) | Docker 29.6.1, and the image running locally on port 3000 |
| [ec2-instance-running.png](01-tools/ec2-instance-running.png) | EC2 deploy server `i-05c1af338bf51e2a9` (t2.micro, eu-west-1a) running, 2/2 status checks |
| [ec2-os-and-docker.txt](01-tools/ec2-os-and-docker.txt) | EC2 OS is Amazon Linux 2 (Karoo), Docker 25.0.18, app container healthy |

## 2. Pipeline

| Screenshot | Shows |
|---|---|
| [jenkins-build-2-all-stages-passed.png](02-pipeline/jenkins-build-2-all-stages-passed.png) | Build #2: Checkout → Install/Build → Test → Docker Build → Push Image → Deploy → Smoke Test → Post Actions (cleanup), all passed. Jenkins 2.580.2 |
| [dockerhub-image-tags.png](02-pipeline/dockerhub-image-tags.png) | Image `benjaminssempala/cicd-node-app` pushed with tags `1`, `2` and `latest` |

## 3. Deployment

| Screenshot | Shows |
|---|---|
| [app-in-browser.png](03-deployment/app-in-browser.png) | App reachable at `http://3.254.176.0`, returning version `2` (the build number) |
| [ec2-docker-ps-and-logs.png](03-deployment/ec2-docker-ps-and-logs.png) | On EC2: container `cicd-node-app:2` healthy, port 80 → 3000, `App listening on port 3000` |
