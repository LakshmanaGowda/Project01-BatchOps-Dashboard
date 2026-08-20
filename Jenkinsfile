pipeline {

    agent any

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
                sh 'docker build -t batchops app/'
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