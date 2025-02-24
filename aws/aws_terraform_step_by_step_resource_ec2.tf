# devopsadmin@learnersepoint:~$ terraform -v
# Terraform v1.2.4
# on linux_amd64
# devopsadmin@learnersepoint:~$ 

# Providers
terraform {
  required_providers {
    aws = {
        source = "hashicorp/aws"
        version = "~> 5.0"
    }
  }
}

# Authentication and Configuration
provider "aws" {
  region     = "ap-south-1"
}


#----------------------------------------------------------------------------------------#
# 1. Create vpc
resource "aws_vpc" "prod-vpc" {
   cidr_block = "10.0.0.0/16"

   tags = {
     Name = "production"
   }  
 }


# 2. Create Internet Gateway
resource "aws_internet_gateway" "gw" {
   vpc_id = aws_vpc.prod-vpc.id

   tags = {
     Name = "prod-gw"
   }  
 }


# 3. Create Custom Route Table
resource "aws_route_table" "prod-route-table" {
  vpc_id = aws_vpc.prod-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block        = "::/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "Prod"
  }
}


# 4. Create a Subnet
resource "aws_subnet" "subnet-1" {
  vpc_id     = aws_vpc.prod-vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "ap-south-1a"

  tags = {
    Name = "prod-subnet"
  }
}


# 5. Associate Subnet with Route Table
 resource "aws_route_table_association" "a" {
   subnet_id      = aws_subnet.subnet-1.id
   route_table_id = aws_route_table.prod-route-table.id
 }


# 6. Create Security Group to allow port 22,80,443
resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow Web inbound traffic"
  vpc_id      = aws_vpc.prod-vpc.id

  ingress {
    description      = "HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  tags = {  
    Name = "allow_web"
  }
}


# 7. Create a network interface with an ip in the subnet that was created in step 4
resource "aws_network_interface" "web-server-nic" {
  subnet_id       = aws_subnet.subnet-1.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow_web.id]

  tags = {  
    Name = "prod_network_interface"
  }
}


# 8. Assign an elastic IP to the Network interface created in step 7
resource "aws_eip" "one" {
  domain = "vpc"
}

resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.ubuntu-web-server-instance.id
  allocation_id = aws_eip.one.id
}

output "server_public_ip" {
  value = aws_eip.one.public_ip
}

output "server_public_dns" {
  value = aws_eip.one.public_dns  
}


# 9. Create Ubuntu server and install/enable apache2 - Ubuntu 24.04
resource "aws_instance" "ubuntu-web-server-instance" {
  ami               = "ami-00bb6a80f01f03502"
  instance_type     = "t2.micro"
  availability_zone = "ap-south-1a"
  key_name          = "main-key"

  network_interface {
    device_index          = 0
    network_interface_id  = aws_network_interface.web-server-nic.id
  }

  user_data = <<-EOF
              #!/bin/bash
              exec > /var/log/user-data.log 2>&1
              set -x

              sudo apt update -y
              sudo apt install apache2 -y
              sudo systemctl start apache2
              sudo systemctl enable apache2
              echo "your very first web server managed by terraform" | sudo tee /var/www/html/index.html
              EOF

  tags = {
    Name = "prod-ubuntu-web-server"
  }

  depends_on = [aws_network_interface.web-server-nic]
}

output "ubuntu-server_private_ip" {
  value = aws_instance.ubuntu-web-server-instance.private_ip
}

output "ubuntu-server_id" {
  value = aws_instance.ubuntu-web-server-instance.id
}


# # # 10. Create Amazon server and install/enable apache2
# # resource "aws_instance" "amazon-web-server-instance" {
# #   ami = "ami-08df646e18b182346"
# #   instance_type = "t2.micro"
# #   availability_zone = "ap-south-1a"
# #   key_name = "main-key"

# #   network_interface {
# #     device_index = 0
# #     network_interface_id = aws_network_interface.web-server-nic.id
# #   }

# #   user_data = <<-EOF
# #               #!/bin/bash
# #               sudo yum update -y
# #               sudo yum install httpd -y
# #               sudo systemctl start httpd
# #               sudo systemctl enable httpd
# #               sudo touch /root/terraform-instance
# #               sudo bash -c 'echo your very first web server managed by terraform > /var/www/html/index.html'
# #               EOF
# #   tags = {
# #     Name = "amazon-web-server"
# #   }
# # }

# # output "amazon-server_private_ip" {
# #   value = aws_instance.amazon-web-server-instance.private_ip
# # }

# # output "amazon-server_id" {
# #   value = aws_instance.amazon-web-server-instance.id
# # }


# ################################################
# # terraform apply --auto-approve
# # Once all done: Verify
# # devopsadmin@learnersepoint:~$ curl http://<public-ip>
# # your very first web server managed by terraform
# # devopsadmin@learnersepoint:~$ 

# ################################################