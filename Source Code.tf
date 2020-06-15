provider "aws" {
 region = "ap-south-1"
 profile = "satyam"
}

resource "tls_private_key" "key" {
  algorithm = "RSA"
}

  module "key_pair" {
   source = "terraform-aws-modules/key-pair/aws"

    key_name   = "key123"
    public_key = tls_private_key.key.public_key_openssh
}


 resource "aws_security_group" "mysg" {
  vpc_id      = "vpc-758f921d"
      ingress {
    description = "Creating SSH security group"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
 ingress {
    description = "Creating HTTP security group"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
tags = {
 Name = "mysg"
}
}



resource "aws_instance" "TeraOS" {
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  availability_zone = "ap-south-1b"
  vpc_security_group_ids = ["${aws_security_group.mysg.id}"]
    key_name = "key123" 
  tags = {
    Name = "Amazon OS"
         }
connection {
           type     = "ssh"
           user     = "ec2-user"
           private_key = tls_private_key.key.private_key_pem
           host     = aws_instance.TeraOS.public_ip
                   }
        provisioner "remote-exec" {
           inline = [
             "sudo yum install httpd php git -y ",
             
                    ]
                                   }
}

resource "aws_ebs_volume" "EbsVol" {
  availability_zone = "ap-south-1b"
  size              = 1

  tags = {
    Name = "EbsVol"
  }
}

resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdd"
  volume_id   = aws_ebs_volume.EbsVol.id
  instance_id = aws_instance.TeraOS.id
  force_detach = true
}


resource "null_resource" "null2" {
depends_on = [
    aws_volume_attachment.ebs_att,
  ]

 connection {
           type     = "ssh"
           user     = "ec2-user"
           private_key = tls_private_key.key.private_key_pem
           host     = aws_instance.TeraOS.public_ip
                   }
      
provisioner "remote-exec" {
           inline = [
             "sudo mkfs.ext4   /dev/xvdd",
             "sudo mount /dev/xvdd  /var/www/html",
             "sudo rm -rf /var/www/html/*",
             "sudo git clone https://github.com/satyamskic/terraform-repo.git  /var/www/html"
                    ]
                           }
}



resource "aws_s3_bucket" "mybucket" {
depends_on = [
    null_resource.null2,
  ]

    bucket  = "satyam9625318589"
    acl = "private"
    force_destroy = true
provisioner "local-exec" {
        command     = "git clone https://github.com/satyamskic/terra-image.git   terra-image"
}
     provisioner "local-exec" {
        when        =   destroy
        command     =   "echo Y | rmdir /s terra-image"
    }
}

resource "aws_s3_bucket_object" "image-upload" {
    bucket  = aws_s3_bucket.mybucket.bucket
    key     = "nature.jpg"
    source  = "terra-image/nature.jpg"
    acl = "public-read"
}



locals {
  s3_origin_id = "aws_s3_bucket.mybucket.id"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.mybucket.bucket_regional_domain_name
    origin_id   = local.s3_origin_id
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "This is nature image"
  default_root_object = "nature.jpg"

  logging_config {
    include_cookies = false
    bucket          = aws_s3_bucket.mybucket.bucket_domain_name
  
  }

   default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  ordered_cache_behavior {
    path_pattern     = "/content/immutable/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  ordered_cache_behavior {
    path_pattern     = "/content/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = "PriceClass_200"

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["IN"]
    }
  }

  tags = {
    Environment = "production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}





resource "null_resource" "null3" {
depends_on = [
    aws_cloudfront_distribution.s3_distribution,
  ]

 connection {
           type     = "ssh"
           user     = "ec2-user"
           private_key = tls_private_key.key.private_key_pem
           host     = aws_instance.TeraOS.public_ip
                   }
      
provisioner "remote-exec" {
           inline = [
    "echo \"<img src='https://${aws_cloudfront_distribution.s3_distribution.domain_name}/nature.jpg' width='300' lenght='400' >\"  | sudo tee -a /var/www/html/index.html",
 
    "sudo systemctl start httpd"
                    ]
                           }
}

output "out1" {
value = aws_cloudfront_distribution.s3_distribution.domain_name
}

output  "out2" {
value = aws_instance.TeraOS.public_ip
}
