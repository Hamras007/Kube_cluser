pipeline {
    agent {
        docker {
            image 'hashicorp/terraform:latest'
            args '--privileged -v /var/run/docker.sock:/var/run/docker.sock --entrypoint="" -u root'
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
                script {
                    def userInput = input(
                        message: 'Do you want to run Build - Terraform Init and Plan?',
                        parameters: [choice(name: 'Response', choices: ['Yes', 'No'], description: 'Select Yes or No')]
                    )
                    if (userInput == 'Yes') {
                        sh '''
                            terraform init
                            ls -al
                            terraform validate
                            terraform plan
                        '''
                    } else {
                        echo 'Skipping Build - Terraform Init and Plan as per user input.'
                    }
                }
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
                    def userInput = input(
                        message: 'Do you want to run Deploy - Terraform Apply?',
                        parameters: [choice(name: 'Response', choices: ['Yes', 'No'], description: 'Select Yes or No')]
                    )
                    if (userInput == 'Yes') {
                        sh '''
                            apk update
                            apk add python3
                            apk add ansible
                            apk add aws-cli
                            terraform apply -auto-approve
                            cat admin.conf
                            aws s3 ls
                            aws s3 cp admin.conf s3://testing-s3-bucket-007/
                            aws s3 ls s3://testing-s3-bucket-007/
                        '''
                    } else {
                        echo 'Skipping Deploy - Terraform Apply as per user input.'
                    }
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: '.terraform, .terraform.lock.hcl, terraform.tfstate', allowEmptyArchive: true
                }
            }
        }

        stage('Post - Terraform Destroy') {
            steps {
                script {
                    def userInput = input(
                        message: 'Do you want to destroy the Terraform resources?',
                        parameters: [choice(name: 'Response', choices: ['Yes', 'No'], description: 'Select Yes or No')]
                    )
                    if (userInput == 'Yes') {
                        sh 'terraform destroy -auto-approve'
                    } else {
                        echo 'Skipping Terraform Destroy as per user input.'
                    }
                }
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

