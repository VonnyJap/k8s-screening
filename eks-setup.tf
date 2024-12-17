provider "aws" {
  region = local.region
}

locals {
  name   = "ascode-cluster"
  region = "us-east-1"

  vpc_cidr = "10.123.0.0/16"
  azs      = ["us-east-1a", "us-east-1b"]

  public_subnets  = ["10.123.1.0/24", "10.123.2.0/24"]
  private_subnets = ["10.123.3.0/24", "10.123.4.0/24"]
  intra_subnets   = ["10.123.5.0/24", "10.123.6.0/24"]

  tags = {
    Example = local.name
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 4.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets
  intra_subnets   = local.intra_subnets

  enable_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
    "map_public_ip_on_launch" = true
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.15.1"

  cluster_name                   = local.name
  cluster_endpoint_public_access = true

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets

  # EKS Managed Node Group(s)
  eks_managed_node_group_defaults = {
    ami_type       = "AL2_x86_64"
    instance_types = ["t2.micro"]

    attach_cluster_primary_security_group = true
  }

  eks_managed_node_groups = {
    ascode-cluster-wg = {
      min_size     = 3
      max_size     = 6
      desired_size = 3

      instance_types = ["t2.micro"]
      capacity_type  = "SPOT"

      tags = {
        ExtraTag = "helloworld"
      }
    }
  }

  tags = local.tags
}

resource "null_resource" "create_key_pair" {
  provisioner "local-exec" {
    command = "${path.module}/create_key_pair.sh"
  }
}

resource "aws_instance" "instance" {
  subnet_id     = "${module.vpc.public_subnets[0]}"
  ami           = "ami-0515f3963c203d061"   # Specify the AMI ID of the instance you want to launch
  instance_type = "t2.micro"                # Specify the instance type
  key_name      = "my-key-pair"             # key pair name

  associate_public_ip_address = true  # Ensure that the instance gets a public IP address

  tags = {
    Name = "ExampleInstance"  # Tag for the instance
  }

  user_data = <<-EOF
              #!/bin/bash
              # Update package index
              sudo yum update -y
              
              # Install AWS CLI v2
              sudo yum install -y unzip curl
              curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
              unzip awscliv2.zip
              sudo ./aws/install
              
              # Install kubectl
              curl -o kubectl https://amazon-eks.s3.us-west-2.amazonaws.com/1.21.14/2023-01-30/bin/linux/amd64/kubectl
              chmod +x ./kubectl
              sudo mv ./kubectl /usr/local/bin

              # Verify installations
              aws --version
              kubectl version --client
              EOF
              
  depends_on = [null_resource.create_key_pair]
}
