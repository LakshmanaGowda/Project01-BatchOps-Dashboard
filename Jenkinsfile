pipeline {

    agent any

    environment {
        DOCKER_IMAGE = 'lakshmanagowda/batchops-dashboard'
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
                sh 'docker build -t $DOCKER_IMAGE:latest -t $DOCKER_IMAGE:build-$BUILD_NUMBER app/'
            }
        }

        stage('Push Docker Image') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'dockerhub-creds',
                        usernameVariable: 'DOCKER_USERNAME',
                        passwordVariable: 'DOCKER_PASSWORD'
                    )
                ]) {
                    sh '''
                        echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin
                        docker push $DOCKER_IMAGE:latest
                        docker push $DOCKER_IMAGE:build-$BUILD_NUMBER
                        docker logout
                    '''
                }
            }
        }

        stage('Remove Existing Container') {
            steps {
                sh 'docker rm -f batchops-container || true'
            }
        }

        stage('Deploy Container') {
            steps {
                sh 'docker run -d -p 5001:5000 --name batchops-container batchops'
            }
        }
    }
}