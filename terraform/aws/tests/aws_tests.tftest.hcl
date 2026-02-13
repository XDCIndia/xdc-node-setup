terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Test EC2 instance creation
run "validate_ec2_instance" {
  command = plan

  variables {
    instance_name = "xdc-test-node"
    instance_type = "t3.xlarge"
    key_name      = "test-key"
    vpc_id        = "vpc-12345678"
    subnet_id     = "subnet-12345678"
  }

  assert {
    condition     = aws_instance.xdc_node.instance_type == "t3.xlarge"
    error_message = "Instance type should be t3.xlarge"
  }

  assert {
    condition     = length(aws_instance.xdc_node.root_block_device) > 0
    error_message = "Root block device should be configured"
  }
}

# Test security group rules
run "validate_security_group" {
  command = plan

  assert {
    condition     = length(aws_security_group.xdc_node.ingress) >= 3
    error_message = "Security group should have at least 3 ingress rules"
  }
}

# Test EBS volume
run "validate_ebs_volume" {
  command = plan

  variables {
    data_volume_size = 1000
  }

  assert {
    condition     = aws_ebs_volume.xdc_data.size == 1000
    error_message = "Data volume size should be 1000 GB"
  }
}