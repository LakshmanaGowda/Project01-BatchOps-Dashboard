pipeline {

    agent any

    stages {

        stage('Clone Repository') {
            steps {
                git branch: 'main',
                    url: 'https://github.com/LakshmanaGowda/Project01-BatchOps-Dashboard.git'
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