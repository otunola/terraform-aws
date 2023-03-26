# Configure AWS provider
provider "aws" {
  region = "us-east-1"
}

# Create a VPC with 2 availability zones, a public subnet, and 2 private subnets
resource "aws_vpc" "example" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.example.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.example.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.example.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1b"
}

# Create an internet gateway and attach it to the VPC
resource "aws_internet_gateway" "example" {
  vpc_id = aws_vpc.example.id
}

# Create a route table and associate it with the public subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.example.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.example.id
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Create a NAT gateway in the public subnet
resource "aws_nat_gateway" "example" {
  allocation_id = aws_eip.example.id
  subnet_id     = aws_subnet.public.id
}

resource "aws_eip" "example" {
  vpc = true
}

# Create an application load balancer between availability zones A and B
resource "aws_lb" "example" {
  name               = "example-lb"
  internal           = false
  load_balancer_type = "application"

  subnet_mapping {
    subnet_id = aws_subnet.public.id
  }

  subnet_mapping {
    subnet_id = aws_subnet.private_1.id
  }

  subnet_mapping {
    subnet_id = aws_subnet.private_2.id
  }
}

# Create an autoscaling group for the Nginx proxy server in the public subnet
resource "aws_launch_template" "example" {
  image_id = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  key_name = "example-key"
}

resource "aws_autoscaling_group" "example" {
  name                 = "example-asg"
  launch_template {
    id = aws_launch_template.example.id
  }
  target_group_arns = [aws_lb_target_group.example.arn]
  availability_zones = ["us-east-1a", "us-east-1b"]
  min_size = 1
  max_size = 3
}

# Create a target group for the load balancer to direct traffic to the Nginx proxy server
resource "aws_lb_target_group" "example" {
  name        = "example-target-group"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc
  target_type = "instance"
}
# Configure the proxy server in the public subnet

resource "aws_instance" "example" {
  ami = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  subnet_id = aws_subnet.public.id
  key_name = "example-key"

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y nginx",
      "sudo systemctl enable nginx",
      "sudo systemctl start nginx"
    ]
  }
}

# Create a second load balancer in the private subnet to direct traffic to the Tomcat servers

resource "aws_lb" "private" {
  name = "private-lb"
  internal = true
  load_balancer_type = "application"

  subnet_mapping {
    subnet_id = aws_subnet.private_1.id
  }

  subnet_mapping {
    subnet_id = aws_subnet.private_2.id
  }
}


# Create an autoscaling group for the Tomcat servers in the first private subnet

resource "aws_autoscaling_group" "tomcat" {
  name = "tomcat-asg"
  launch_template {
    id = aws_launch_template.example.id
  }
  target_group_arns = [aws_lb_target_group.private.arn]
  availability_zones = ["us-east-1a", "us-east-1b"]
  min_size = 1
  max_size = 3
}

# Create a multi-availability zone RDS instance in the second private subnet
resource "aws_db_subnet_group" "example" {
  name = "example-db-subnet-group"
  subnet_ids = [aws_subnet.private_1.id, aws_subnet.private_2.id]
}

resource "aws_db_instance" "example" {
  engine = "mysql"
  instance_class = "db.t2.micro"
  allocated_storage = 10
  db_subnet_group_name = aws_db_subnet_group.example.name
}

# Create a bastion host in the public subnet for accessing the private subnets

resource "aws_instance" "bastion" {
  ami = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  subnet_id = aws_subnet.public.id
  key_name = "example-key"

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y awscli",
      "echo 'ProxyCommand ssh -W %h:%p ec2-user@${aws_eip.example.public_ip}' > ~/.ssh/config",
      "chmod 400 ~/.ssh/config"
    ]
  }
}