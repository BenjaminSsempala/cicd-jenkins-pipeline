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

        // Replace the running container with the new image, then remove images no container uses
        stage('Deploy') {
            steps {
                sshagent(credentials: ['ec2_ssh']) {
                    sh '''
                        ssh -o StrictHostKeyChecking=accept-new "$EC2_USER@$DEPLOY_HOST" bash -s <<EOF
set -e
docker pull "$IMAGE:$TAG"
docker rm -f "$APP_NAME" 2>/dev/null || true
docker run -d --name "$APP_NAME" --restart unless-stopped -p 80:3000 -e APP_VERSION="$TAG" "$IMAGE:$TAG"
docker image prune -af
EOF
                    '''
                }
            }
        }

        stage('Smoke Test') {
            steps {
                sh 'curl -fsS --retry 10 --retry-delay 3 --retry-all-errors "http://$DEPLOY_HOST/health"'
                echo "App is live at http://${env.DEPLOY_HOST}"
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
