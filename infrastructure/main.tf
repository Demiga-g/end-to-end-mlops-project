terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}


# configure the aws provider
provider "aws" {
  region  = "eu-north-1"
  profile = "demiga-g"
}


# read the public key file
resource "tls_private_key" "ssh_private_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}


# create a key pair with the public key
resource "aws_key_pair" "deployer" {
  key_name   = "mlops-ete-key-pair"
  public_key = file("~/.ssh/mlops-ete-key-pair.pub")
}


# security group for EC2 SSH and custom TCP
resource "aws_security_group" "ec2_instance_security_group" {
  name        = "instance_security_group"
  description = "Allow SSH and custom TCP traffic"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# ec2 instance configuration
resource "aws_instance" "instance_ete_mlops" {
  ami             = "ami-0d7e17c1a01e6fa40"
  instance_type   = "t3.micro"
  key_name        = aws_key_pair.deployer.key_name
  security_groups = [aws_security_group.ec2_instance_security_group.name]

  root_block_device {
    volume_size = 25
    volume_type = "gp3"
  }

  tags = {
    Name = "mlflow-mlops"
  }
}


# s3 bucket configuration
resource "aws_s3_bucket" "bucket_ete_mlops" {
  bucket        = "midega-mlflow-artifacts"
  force_destroy = true
}


# postgresql security group
resource "aws_security_group" "postgres_security_group" {
  name        = "rds_security_group"
  description = "Allow traffic from the EC2 instance"

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_instance_security_group.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# retrieving the default VPC
data "aws_vpc" "default" {
  filter {
    name   = "isDefault"
    values = ["true"]
  }
}

# retrieving the default security group within the default vpc
data "aws_security_group" "default" {
  vpc_id = data.aws_vpc.default.id
  filter {
    name   = "group-name"
    values = ["default"]
  }
}


# add ingress rule to the default security group that allows postgresql
# to run in the remote machine
resource "aws_security_group_rule" "allow_postgres" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = data.aws_security_group.default.id
  source_security_group_id = aws_security_group.ec2_instance_security_group.id
}


# postgres database configuration
resource "aws_db_instance" "postgresql_db_ete_mlops" {

  db_name                 = "mlflow_ifood_db"
  username                = "postgres"
  identifier              = "ifood-artifacts"
  password                = "password"
  port                    = 5432
  allocated_storage       = 20
  storage_type            = "gp2"
  engine                  = "postgres"
  engine_version          = "16.3"
  instance_class          = "db.t3.micro"
  parameter_group_name    = "default.postgres16" # change according to your engine version
  skip_final_snapshot     = true
  publicly_accessible     = false
  backup_retention_period = 1


  tags = {
    Name = "db-instance"
  }
}

###################### uncomment to create private ECR (charges may apply) ######################

# # configuring ECR resources
# resource "aws_ecr_repository" "ecr_ete_mlops" {
#   name                 = "docker_ecr_image"
#   image_tag_mutability = "MUTABLE"

#   image_scanning_configuration {
#     scan_on_push = false
#   }

#   force_delete = true
# }


# # ensuring that dockerfile exists in ecr before running prediction script
# resource "null_resource" "ecr_image" {
#   triggers = {
#     python_file = md5(file("/home/midega-g/Desktop/Learning/end-to-end-mlops-project/deployment_file_entry/app/main.py"))
#     docker_file = md5(file("/home/midega-g/Desktop/Learning/end-to-end-mlops-project/deployment_file_entry/Dockerfile"))
#   }

#   provisioner "local-exec" {
#     command = <<EOF
#           aws ecr get-login-password --region eu-north-1 | docker login --username AWS --password-stdin ${aws_ecr_repository.ecr_ete_mlops.repository_url}
#           docker build -t ${aws_ecr_repository.ecr_ete_mlops.repository_url} -f deployment_file_entry/Dockerfile deployment_file_entry
#           docker push ${aws_ecr_repository.ecr_ete_mlops.repository_url}:latest
#         EOF

#   }
# }

# ## wait for the image to be uploaded, before script runs
# data "aws_ecr_image" "load_docker_image" {
#   depends_on      = [null_resource.ecr_image]
#   repository_name = aws_ecr_repository.ecr_ete_mlops.name
#   image_tag       = "latest"
# }

# output "image_uri" {
#   value = "${aws_ecr_repository.ecr_ete_mlops.repository_url}:${data.aws_ecr_image.load_docker_image.image_tag}"
# }


###################### uncomment to create custome s3 bucket policy if needed ######################

# # IAM policy
# resource "aws_iam_policy" "s3_bucket_policies" {
#   name        = "S3BucketPolicy"
#   description = "Policy to allow specific S3 bucket action"
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = [
#           "s3:CreateBucket",
#           "s3:ListBucket",
#           "s3:GetObject",
#           "s3:PutObject"
#         ]
#         Effect = "Allow"
#         Resource = [
#           "arn:aws:s3:::${aws_s3_bucket.bucket_ete_mlops.bucket}",
#           "arn:aws:s3:::${aws_s3_bucket.bucket_ete_mlops.bucket}/*"
#         ]
#       }
#     ]
#   })
# }

# # IAM role
# resource "aws_iam_role" "MlopsEteAccess" {
#   name = "mlops-ete-role"
#   assume_role_policy = jsonencode(
#     {
#       Version = "2012-10-17"
#       Statement = [
#         {
#           Effect = "Allow"
#           Action = "sts:AssumeRole"
#           Principal = {
#             Service = "ec2.amazonaws.com"
#           }
#         },
#       ]

#     }
#   )
# }

# # attaching policy to role
# resource "aws_iam_role_policy_attachment" "mlops_role_policy_attach" {
#   role       = aws_iam_role.MlopsEteAccess.name
#   policy_arn = aws_iam_policy.s3_bucket_policies.arn
# }


###################### uncomment to create secret manager for credentials (charges apply) ######################

# KMS key
# resource "aws_kms_key" "my_cmk" {
#   description             = "KMS key for encrypting secrets"
#   deletion_window_in_days = 7
# }


# Secrets Manager secret configuration for Docker Hub credentials
# resource "aws_secretsmanager_secret" "dockerhub_secret" {
#   name         = "dev/DockerHubSecret4"
#   description  = "Docker Hub credentials"
#   kms_key_id   = aws_kms_key.my_cmk.arn
# }


# Secrets Manager secret version for Docker Hub credentials
# resource "aws_secretsmanager_secret_version" "dockerhub_secret_version" {
#   secret_id     = aws_secretsmanager_secret.dockerhub_secret.id
#   secret_string = jsonencode({
#     username = ""
#     password = ""
#   })
# }


###################### uncomment to create ECS resources (charges apply) ######################


# # IAM role configuration for ECS task 
# resource "aws_iam_role" "ecs_task_execution_role" {
#   name = "ecsTaskExecutionRole2"
#   description = "Role for Amazon ECS taks"
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [{
#       Action = "sts:AssumeRole",
#       Effect = "Allow",
#       Principal = {
#         Service = "ecs-tasks.amazonaws.com"
#       }
#     }]
#   })
# }


# # IAM policy configuration for ECS task
# resource "aws_iam_policy" "ecs_task_execution_policy" {
#   name = "ECSTaskExecutionRolePolicy"
#   description = "Provides access to other AWS service resources that are required to run Amazon ECS tasks"
#   policy = jsonencode(
#     {
#     "Version": "2012-10-17",
#     "Statement": [
#         {
#             "Effect": "Allow",
#             "Action": [
#                 "kms:Decrypt",
#                 "secretsmanager:GetSecretValue",
#                 "ecr:GetAuthorizationToken",
#                 "ecr:BatchCheckLayerAvailability",
#                 "ecr:GetDownloadUrlForLayer",
#                 "ecr:BatchGetImage",
#                 "logs:CreateLogStream",
#                 "logs:PutLogEvents"

#             ],
#             "Resource": "*"
#         }
#     ]
# }
#   )
# }


# # IAM role policy attachment for ECS task
# resource "aws_iam_role_policy_attachment" "ecs_role_policy_attach" {
#   role       = aws_iam_role.ecs_task_execution_role.name
#   policy_arn = aws_iam_policy.ecs_task_execution_policy.arn
# }


# resource "aws_cloudwatch_log_group" "ecs_task_logs" {
#   name = "/ecs/ifood-response"
#   retention_in_days = 1
# }

# # ECS task definition configuration
# resource "aws_ecs_task_definition" "ecs_task_ete_mlops" {
#   family                   = "ifood-response-ecs"
#   cpu                      = 512
#   memory                   = 1024
#   network_mode             = "awsvpc"
#   requires_compatibilities = ["FARGATE"]
#   execution_role_arn = aws_iam_role.ecs_task_execution_role.arn

#   container_definitions = jsonencode([
#     {
#       name      = "ifood-response-container"
#       # uncomment for pulling the image from docker hub
#       # image     = "midega/ifood-response-classifier:latest"

#       # uncomment for pulling from aws ecr
#       image     = "public.ecr.aws/z5m0q2k8/docker_ecr_image:latest"
#       cpu       = 512
#       memory    = 1024
#       essential = true
#       portMappings = [
#         {
#           containerPort = 9696
#           hostPort      = 9696
#           protocol      = "tcp"
#         }
#       ]

#       logConfiguration = {
#         logDriver = "awslogs"
#         options = {
#           "awslogs-group" : "${aws_cloudwatch_log_group.ecs_task_logs.name}",
#           "awslogs-stream-prefix" : "ecs-task-logs",
#           "awslogs-datetime-format" : "%Y-%m-%dT%H:%M:%",
#           "awslogs-region": "eu-north-1"
#         }
#       }

#     }
#   ])

#   runtime_platform {
#     operating_system_family = "LINUX"
#     cpu_architecture        = "X86_64"
#   }
# }

# # ECS cluster creation configuration
# resource "aws_ecs_cluster" "ecs_cluster_ete_mlops" {
#   name = "ifood-response-ecs-cluster"
#   setting {
#     name  = "containerInsights"
#     value = "enabled"
#   }
# }


# # ECS service security group
# resource "aws_security_group" "ecs_allow_all" {
#   name = "ecs-all-inbounds-ips"
#   description = "Allows all inbound traffic"
#   vpc_id = data.aws_vpc.default.id

#     ingress {
#     from_port   = 9696
#     to_port     = 9696
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]

#   }

#     ingress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]

#   }

#     egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
# }


# # select all subnet within the vpc
# data "aws_subnet" "all_subnets" {
#   availability_zone = "eu-north-1b"
# }


# # ECS service configuration
# resource "aws_ecs_service" "ifood_response_api" {
#   name = "ifood-response-api"
#   cluster = aws_ecs_cluster.ecs_cluster_ete_mlops.id
#   task_definition = aws_ecs_task_definition.ecs_task_ete_mlops.arn
#   desired_count = 1
#   launch_type = "FARGATE"

#   network_configuration {
#     subnets = [data.aws_subnet.all_subnets.id]
#     assign_public_ip = true
#     security_groups = [aws_security_group.ecs_allow_all.id]
#   }
# }

# resource "aws_vpc_endpoint" "secrets_manager" {
#   vpc_id            = data.aws_vpc.default.id
#   service_name      = "com.amazonaws.eu-north-1.secretsmanager"
#   vpc_endpoint_type = "Interface"
#   subnet_ids        = [data.aws_subnet.all_subnets.id]

#   security_group_ids = [aws_security_group.ecs_allow_all.id]
# }
