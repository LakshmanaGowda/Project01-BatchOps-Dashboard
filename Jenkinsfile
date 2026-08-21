pipeline {

    agent any

    environment {
        DOCKER_IMAGE = 'lakshmanagowda/batchops-dashboard'
        DOCKER_CREDENTIALS = 'dockerhub-creds'
        KUBECONFIG = '/var/lib/jenkins/.kube/config'
    }

    stages {

        stage('Terraform Init') {
            steps {
                dir('terraform') {
                    sh 'terraform init -input=false'
                }
            }
        }

        stage('Terraform Validate') {
            steps {
                dir('terraform') {
                    sh 'terraform validate'
                }
            }
        }

        stage('Terraform Plan') {
            steps {
                dir('terraform') {
                    sh 'terraform plan -input=false'
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                sh '''
                    docker build \
                      -t ${DOCKER_IMAGE}:build-${BUILD_NUMBER} \
                      app/
                '''
            }
        }

        stage('Push Docker Image') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: "${DOCKER_CREDENTIALS}",
                        usernameVariable: 'DOCKER_USERNAME',
                        passwordVariable: 'DOCKER_PASSWORD'
                    )
                ]) {
                    sh '''
                        echo "${DOCKER_PASSWORD}" | docker login \
                          -u "${DOCKER_USERNAME}" \
                          --password-stdin

                        docker push ${DOCKER_IMAGE}:build-${BUILD_NUMBER}

                        docker logout
                    '''
                }
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                sh '''
                    echo "Deploying Docker image:"
                    echo "${DOCKER_IMAGE}:build-${BUILD_NUMBER}"

                    echo "Updating Kubernetes deployment manifest..."

                    sed -i "s|image: .*|image: ${DOCKER_IMAGE}:build-${BUILD_NUMBER}|" \
                        k8s/deployment.yaml

                    echo "Applying Kubernetes deployment..."

                    kubectl apply -f k8s/deployment.yaml

                    echo "Applying Kubernetes service..."

                    kubectl apply -f k8s/service.yaml

                    echo "Waiting for deployment rollout..."

                    kubectl rollout status \
                        deployment/batchops-dashboard \
                        --timeout=120s

                    echo "Deployment successful."

                    echo "Deployment status:"
                    kubectl get deployment batchops-dashboard

                    echo "Pod status:"
                    kubectl get pods -l app=batchops-dashboard -o wide

                    echo "Service status:"
                    kubectl get service batchops-dashboard-service
                '''
            }
        }
    }
}