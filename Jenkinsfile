pipeline {
    agent {
        docker {
            image 'hashicorp/terraform:latest'
            args '--privileged -v /var/run/docker.sock:/var/run/docker.sock --entrypoint=""'
        }
    }
    environment {
        PATH = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
        DOCKER_TLS_CERTDIR = ''
        AWS_ACCESS_KEY_ID     = credentials('aws_access_key_id')
        AWS_SECRET_ACCESS_KEY = credentials('aws_secret_access_key')
        AWS_DEFAULT_REGION    = 'ap-south-1'
    }

    stages {
        
        
        stage('Build - Terraform Init and Plan') {
            steps {
                
                sh '''
                    terraform init
                    ls -al
                    terraform validate
                    terraform plan
                '''
            }
            post {
                always {
                    archiveArtifacts artifacts: '.terraform, .terraform.lock.hcl', allowEmptyArchive: true
                }
            }
        }

        stage('Deploy - Terraform Apply') {
            steps {
                script {
                    // Install Ansible dependencies
                    sh '''
                        apk update
                        apk add python3
                        apk add ansible
                    '''
                }
                sh 'terraform apply -auto-approve'
            }
            post {
                always {
                    archiveArtifacts artifacts: '.terraform, .terraform.lock.hcl, terraform.tfstate', allowEmptyArchive: true
                }
            }
        }

        stage('Post - Terraform Destroy') {
            when {
                expression { return env.DESTROY == 'true' } // Set DESTROY=true in Jenkins parameters to trigger this stage
            }
            steps {
                sh 'terraform destroy -auto-approve'
            }
        }
    }
    post {
        failure {
            echo 'Pipeline failed!'
        }
        success {
            echo 'Pipeline succeeded!'
        }
    }

}