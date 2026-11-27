// CI/CD pipeline: Checkout → Install/Build → Test → Docker Build → Push Image → Deploy (SSH to EC2) 
// Default deploy server (terraform output public_ip)
def DEFAULT_EC2_HOST = '3.254.176.0'

pipeline {
    agent any

    parameters {
        string(name: 'EC2_HOST', defaultValue: DEFAULT_EC2_HOST, description: 'Public IP or DNS of the deploy server (terraform output public_ip)')
    }

    environment {
        IMAGE    = 'benjaminssempala/cicd-node-app'
        TAG      = "${env.BUILD_NUMBER}"
        APP_NAME = 'cicd-node-app'
        EC2_USER = 'ec2-user'
        // Parameters are empty on a job's first build, before Jenkins has read the parameters block
        DEPLOY_HOST = "${params.EC2_HOST ?: DEFAULT_EC2_HOST}"
    }

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        // Node runs in a throwaway container, so the Jenkins machine doesn't need Node installed
        stage('Install/Build') {
            agent {
                docker {
                    image 'node:22-alpine'
                    args '-e npm_config_cache=/tmp/.npm'
                    reuseNode true
                }
            }
            steps {
                sh 'npm ci'
            }
        }

        stage('Test') {
            agent {
                docker {
                    image 'node:22-alpine'
                    args '-e npm_config_cache=/tmp/.npm'
                    reuseNode true
                }
            }
            steps {
                sh 'npm test'
            }
        }

        stage('Docker Build') {
            steps {
                sh 'docker build -t "$IMAGE:$TAG" -t "$IMAGE:latest" .'
            }
        }

        // scanning the image
        stage ('Scan Image'){
            steps {
                sh '''
            docker run --rm \
              -v /var/run/docker.sock:/var/run/docker.sock \
              -v trivy-cache:/root/.cache \
              aquasec/trivy:0.76.1 image \
              --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 \
              "$IMAGE:$TAG"
        '''
            }
        }

        stage('Push Image') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'registry_creds', usernameVariable: 'REG_USER', passwordVariable: 'REG_PASS')]) {
                    sh '''
                        echo "$REG_PASS" | docker login -u "$REG_USER" --password-stdin
                        docker push "$IMAGE:$TAG"
                        docker push "$IMAGE:latest"
                    '''
                }
            }
        }

        // Keep the previous container until the new deployment passes its smoke test.
        stage('Deploy') {
            steps {
                sshagent(credentials: ['ec2_ssh']) {
                    sh '''
                        ssh -o StrictHostKeyChecking=accept-new "$EC2_USER@$DEPLOY_HOST" \
                            bash -s -- "$IMAGE:$TAG" "$APP_NAME" "$TAG" <<'EOF'
set -e
image="$1"
app="$2"
version="$3"
previous="${app}-previous"

docker pull "$image"

# If starting the replacement fails, restore the previous container.
restore_on_error() {
    trap - ERR
    echo "Deployment failed; attempting to restore the previous container."
    if docker container inspect "$previous" >/dev/null 2>&1; then
        if docker container inspect "$app" >/dev/null 2>&1; then
            docker rm -f "$app"
        fi
        docker rename "$previous" "$app"
        docker start "$app"
    else
        echo "No previous container exists to restore."
    fi
}
trap restore_on_error ERR

if docker container inspect "$app" >/dev/null 2>&1; then
    docker rename "$app" "$previous"
    docker stop "$previous"
fi

docker run -d --name "$app" --restart unless-stopped -p 80:3000 -e APP_VERSION="$version" "$image"
trap - ERR
EOF
                    '''
                }
            }
        }

        stage('Smoke Test') {
            steps {
                script {
                    try {
                        sh 'curl -fsS --retry 10 --retry-delay 3 --retry-all-errors "http://$DEPLOY_HOST/health"'
                    } catch (smokeError) {
                        echo 'Smoke test failed; attempting rollback.'
                        sshagent(credentials: ['ec2_ssh']) {
                            sh '''
                                ssh -o StrictHostKeyChecking=accept-new "$EC2_USER@$DEPLOY_HOST" \
                                    bash -s -- "$APP_NAME" <<'EOF'
set -e
app="$1"
previous="${app}-previous"

if docker container inspect "$app" >/dev/null 2>&1; then
    docker rm -f "$app"
fi
if docker container inspect "$previous" >/dev/null 2>&1; then
    docker rename "$previous" "$app"
    docker start "$app"
    echo "Previous container restored."
else
    echo "No previous container exists to restore."
fi
EOF
                            '''
                        }
                        throw smokeError
                    }

                    // Remove the backup only after the new container responds.
                    sshagent(credentials: ['ec2_ssh']) {
                        sh '''
                            ssh -o StrictHostKeyChecking=accept-new "$EC2_USER@$DEPLOY_HOST" \
                                bash -s -- "$APP_NAME" <<'EOF'
set -e
previous="${1}-previous"
if docker container inspect "$previous" >/dev/null 2>&1; then
    docker rm -f "$previous"
fi
EOF
                        '''
                    }
                    echo "App is live at http://${env.DEPLOY_HOST}"
                }
            }
        }
    }

    // Clean up on the Jenkins machine whether the build passed or failed
    post {
        always {
            sh '''
                docker logout || true
                docker rmi "$IMAGE:$TAG" "$IMAGE:latest" 2>/dev/null || true
                docker image prune -f
            '''
            cleanWs()
        }
    }
}
