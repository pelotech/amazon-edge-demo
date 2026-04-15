##### DEMO

data "aws_caller_identity" "current" {}


module "demo_vpc" {
  source = "terraform-aws-modules/vpc/aws"
  providers = {
    aws = aws.us-west-2
  }
  version                                = "6.6.1"
  name                                   = "demo"
  create_vpc                             = true
  enable_dns_hostnames                   = "true"
  enable_dns_support                     = "true"
  enable_nat_gateway                     = true
  single_nat_gateway                     = true
  cidr                                   = "172.16.0.0/16"
  azs                                    = ["us-west-2a", "us-west-2b", "us-west-2c"]
  private_subnets                        = ["172.16.0.0/24", "172.16.1.0/24", "172.16.2.0/24"]
  public_subnets                         = ["172.16.100.0/24", "172.16.101.0/24", "172.16.102.0/24"]
  create_database_subnet_group           = false
  create_database_subnet_route_table     = false
  create_database_internet_gateway_route = false

  map_public_ip_on_launch = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
}

# DEMO EKS

module "demo_eks" {
  providers = {
    aws = aws.us-west-2
  }
  source  = "terraform-aws-modules/eks/aws"
  version = "21.18.0"

  name               = "demo"
  kubernetes_version = "1.35"

  vpc_id     = module.demo_vpc.vpc_id
  subnet_ids = module.demo_vpc.public_subnets

  endpoint_public_access  = true
  endpoint_private_access = true

  kms_key_administrators = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/gh-main", "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-reserved/sso.amazonaws.com/us-west-2/AWSReservedSSO_AdministratorAccess_50a18f7501752694"]
  access_entries = {
    admin_github = {
      principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/gh-main"
      policy_associations = {
        cluster_admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    },
    admin_admins = {
      principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-reserved/sso.amazonaws.com/us-west-2/AWSReservedSSO_AdministratorAccess_50a18f7501752694"
      policy_associations = {
        cluster_admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    },
    demo_readonly = {
      principal_arn = aws_iam_user.demo_readonly.arn
      policy_associations = {
        view = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  node_security_group_additional_rules = {
    allow_all_inbound = {
      description = "Allow all inbound traffic"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  addons = {
    coredns = {
      most_recent                 = true
      resolve_conflicts_on_update = "OVERWRITE"
    }
    kube-proxy = {
      most_recent                 = true
      resolve_conflicts_on_update = "OVERWRITE"
      before_compute              = true
    }
    vpc-cni = {
      most_recent                 = true
      resolve_conflicts_on_update = "OVERWRITE"
      before_compute              = true
    }
    eks-pod-identity-agent = {
      most_recent                 = true
      resolve_conflicts_on_update = "OVERWRITE"
    }
  }

  eks_managed_node_groups = {
    general = {
      instance_types = ["t3a.small"]
      ami_type       = "AL2023_x86_64_STANDARD"
      capacity_type  = "ON_DEMAND"

      min_size     = 1
      max_size     = 3
      desired_size = 3

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size = 20
            volume_type = "gp3"
            encrypted   = true
          }
        }
      }


    }
  }

  fargate_profiles = {
    fargate = {
      selectors = [{
        namespace = "fargate"
      }]
      subnet_ids = module.demo_vpc.private_subnets
    }
  }
}


# DEMO ECS

data "aws_ssm_parameter" "ecs_ami" {
  provider = aws.us-west-2
  name     = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

module "demo_ecs_asg_sg" {
  providers = {
    aws = aws.us-west-2
  }
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.3.1"

  name   = "demo-ecs-asg"
  vpc_id = module.demo_vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
  egress_rules = ["all-all"]
}

module "demo_ecs_asg" {
  providers = {
    aws = aws.us-west-2
  }
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "~> 9.2.0"

  name = "demo-ecs"

  image_id      = data.aws_ssm_parameter.ecs_ami.value
  instance_type = "t3a.small"

  security_groups = [module.demo_ecs_asg_sg.security_group_id]
  user_data = base64encode(<<-EOT
    #!/bin/bash
    echo "ECS_CLUSTER=demo" >> /etc/ecs/ecs.config
  EOT
  )

  ignore_desired_capacity_changes = true

  create_iam_instance_profile = true
  iam_role_name               = "demo-ecs-asg"
  iam_role_policies = {
    AmazonEC2ContainerServiceforEC2Role = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
    AmazonSSMManagedInstanceCore        = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  vpc_zone_identifier = module.demo_vpc.public_subnets
  health_check_type   = "EC2"
  min_size            = 3
  max_size            = 3
  desired_capacity    = 3

  protect_from_scale_in = false
}

module "ecs_cluster" {
  providers = {
    aws = aws.us-west-2
  }
  source  = "terraform-aws-modules/ecs/aws"
  version = "~> 7.5.0"

  cluster_name                = "demo"
  create_cloudwatch_log_group = false

  cluster_capacity_providers = ["FARGATE", "demo"]

  capacity_providers = {
    demo = {
      auto_scaling_group_provider = {
        auto_scaling_group_arn         = module.demo_ecs_asg.autoscaling_group_arn
        managed_termination_protection = "DISABLED"

        managed_scaling = {
          maximum_scaling_step_size = 1
          minimum_scaling_step_size = 1
          status                    = "ENABLED"
          target_capacity           = 100
        }
      }
    }
  }

  services = {
    pictures = {
      cpu    = 256
      memory = 512

      desired_count                      = 3
      enable_autoscaling                 = false
      network_mode                       = "bridge"
      requires_compatibilities           = ["EC2"]
      create_security_group              = false
      deployment_minimum_healthy_percent = 0

      capacity_provider_strategy = {
        demo = {
          capacity_provider = "demo"
          base              = 3
          weight            = 100
        }
      }

      ordered_placement_strategy = [
        {
          type  = "spread"
          field = "attribute:ecs.availability-zone"
        },
        {
          type  = "spread"
          field = "instanceId"
        }
      ]

      container_definitions = {
        pictures = {
          cpu                    = 256
          memory                 = 512
          essential              = true
          readonlyRootFilesystem = false
          image                  = "ghcr.io/pelotech/amazon-edge-demo-images:latest" #should have latest sha built
          portMappings = [
            {
              name          = "http"
              containerPort = 80
              hostPort      = 80
              protocol      = "tcp"
            }
          ]
          enable_cloudwatch_logging   = false
          create_cloudwatch_log_group = false
          memoryReservation           = 100
        }
      }
    }

    videos = {
      cpu    = 256
      memory = 512

      subnet_ids       = module.demo_vpc.public_subnets
      assign_public_ip = true

      create_security_group = true
      security_group_ingress_rules = {
        http = {
          from_port   = 80
          to_port     = 80
          ip_protocol = "tcp"
          cidr_ipv4   = "0.0.0.0/0"
        }
      }
      security_group_egress_rules = {
        all = {
          ip_protocol = "-1"
          cidr_ipv4   = "0.0.0.0/0"
        }
      }

      container_definitions = {
        videos = {
          cpu                    = 256
          memory                 = 512
          essential              = true
          readonlyRootFilesystem = false
          image                  = "ghcr.io/pelotech/amazon-edge-demo-videos:latest" #should have latest sha built
          portMappings = [
            {
              name          = "http"
              containerPort = 80
              protocol      = "tcp"
            }
          ]
          enable_cloudwatch_logging   = false
          create_cloudwatch_log_group = false
          memoryReservation           = 100
        }
      }
    }
  }
}
