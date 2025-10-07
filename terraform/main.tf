#####################################################
# main.tf – End-to-End Infra with Auto-Zip Lambdas
#####################################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 5.50" }
    archive = { source = "hashicorp/archive", version = "~> 2.5" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

provider "aws" {
  region = var.region
}

#####################################################
# RANDOM SUFFIX
#####################################################

resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  pdf_bucket_name      = "pdf-input-${random_id.suffix.hex}"
  frontend_bucket_name = "react-frontend-${random_id.suffix.hex}"
  es_endpoint          = "http://${aws_instance.es.public_dns}:9200"
}

#####################################################
# S3 BUCKETS
#####################################################

resource "aws_s3_bucket" "pdfs" {
  bucket        = local.pdf_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket" "frontend" {
  bucket        = local.frontend_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_website_configuration" "frontend_site" {
  bucket = aws_s3_bucket.frontend.bucket

  index_document { suffix = "index.html" }
  error_document { key    = "index.html" }
}

#####################################################
# NETWORKING
#####################################################

data "aws_vpc" "default" { default = true }

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

#####################################################
# ELASTICSEARCH EC2
#####################################################

data "aws_ami" "al2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_security_group" "es_sg" {
  name        = "es-sg-${random_id.suffix.hex}"
  description = "Elasticsearch + SSH"
  vpc_id      = data.aws_vpc.default.id

  lifecycle { ignore_changes = [description] }

  ingress {
    from_port   = 9200
    to_port     = 9200
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
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

resource "aws_ebs_volume" "es_data" {
  availability_zone = aws_instance.es.availability_zone
  size              = 20  # 20GB for Elasticsearch data
  type              = "gp3"

  tags = {
    Name = "elasticsearch-data-${random_id.suffix.hex}"
  }
}

resource "aws_volume_attachment" "es_data_attach" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.es_data.id
  instance_id = aws_instance.es.id
}

resource "aws_instance" "es" {
  ami                         = data.aws_ami.al2.id
  instance_type               = var.es_instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.es_sg.id]
  associate_public_ip_address = true
  key_name                    = var.ssh_key_name

  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Install Java and Elasticsearch
    yum update -y
    amazon-linux-extras install java-openjdk11 -y
    curl -L -o /tmp/elasticsearch.rpm https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-7.17.9-x86_64.rpm
    rpm -ivh /tmp/elasticsearch.rpm

    # Wait for EBS volume to attach
    while [ ! -e /dev/xvdf ]; do sleep 1; done

    # Format EBS volume if not already formatted
    if ! blkid /dev/xvdf; then
      mkfs -t ext4 /dev/xvdf
    fi

    # Create mount point and mount EBS volume
    mkdir -p /var/lib/elasticsearch
    mount /dev/xvdf /var/lib/elasticsearch

    # Add to fstab for auto-mount on reboot
    echo "/dev/xvdf /var/lib/elasticsearch ext4 defaults,nofail 0 2" >> /etc/fstab

    # Set ownership for Elasticsearch
    chown -R elasticsearch:elasticsearch /var/lib/elasticsearch

    # Configure Elasticsearch
    echo "discovery.type: single-node" >> /etc/elasticsearch/elasticsearch.yml
    echo "network.host: 0.0.0.0" >> /etc/elasticsearch/elasticsearch.yml
    echo "path.data: /var/lib/elasticsearch" >> /etc/elasticsearch/elasticsearch.yml

    # Start Elasticsearch
    systemctl enable elasticsearch
    systemctl start elasticsearch
  EOF
}

#####################################################
# IAM FOR LAMBDA
#####################################################

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "pdf-search-lambda-role-${random_id.suffix.hex}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "lambda_inline" {
  name = "pdf-search-inline-${random_id.suffix.hex}"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["s3:GetObject", "s3:ListBucket"],
        Resource = [
          aws_s3_bucket.pdfs.arn,
          "${aws_s3_bucket.pdfs.arn}/*"
        ]
      },
      {
        Effect   = "Allow",
        Action   = [
          "textract:StartDocumentTextDetection",
          "textract:GetDocumentTextDetection",
          "textract:DetectDocumentText"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_inline_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_inline.arn
}

#####################################################
# LAMBDAS (with archive_file so code updates trigger redeploy)
#####################################################

# Ingest Lambda
data "archive_file" "ingest_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/ingest"
  output_path = "${path.module}/build/ingest.zip"
}

resource "aws_lambda_function" "ingest" {
  function_name    = "pdf-ingest-${random_id.suffix.hex}"
  role             = aws_iam_role.lambda_role.arn
  runtime          = "python3.12"
  handler          = "ingest.lambda_handler"
  filename         = data.archive_file.ingest_zip.output_path
  source_code_hash = data.archive_file.ingest_zip.output_base64sha256

  memory_size = 1024
  timeout     = 300

  environment {
    variables = {
      ES_HOST = local.es_endpoint
      INDEX   = "pdfs"
    }
  }
}

resource "aws_lambda_permission" "s3_invoke_ingest" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.pdfs.arn
}

resource "aws_s3_bucket_notification" "pdf_notify" {
  bucket = aws_s3_bucket.pdfs.id
  lambda_function {
    lambda_function_arn = aws_lambda_function.ingest.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".pdf"
  }
  depends_on = [aws_lambda_permission.s3_invoke_ingest]
}

# Search Lambda
data "archive_file" "search_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/search"
  output_path = "${path.module}/build/search.zip"
}

resource "aws_lambda_function" "search" {
  function_name    = "pdf-search-${random_id.suffix.hex}"
  role             = aws_iam_role.lambda_role.arn
  runtime          = "python3.12"
  handler          = "search.lambda_handler"
  filename         = data.archive_file.search_zip.output_path
  source_code_hash = data.archive_file.search_zip.output_base64sha256

  memory_size = 512
  timeout     = 15

  environment {
    variables = {
      ES_HOST           = local.es_endpoint
      INDEX             = "pdfs"
      CLOUDFRONT_DOMAIN = "dborha5b60sv8.cloudfront.net"
    }
  }
}

#####################################################
# API GATEWAY
#####################################################

resource "aws_api_gateway_rest_api" "api" {
  name        = "pdf-search-api-${random_id.suffix.hex}"
  description = "Search PDFs"
}

resource "aws_api_gateway_resource" "search_res" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "search"
}

resource "aws_api_gateway_method" "get_search" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.search_res.id
  http_method   = "GET"
  authorization = "NONE"
  request_parameters = {
    "method.request.querystring.q" = false
  }
}

resource "aws_api_gateway_integration" "search_integ" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.search_res.id
  http_method             = aws_api_gateway_method.get_search.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.search.invoke_arn
}

resource "aws_lambda_permission" "allow_api_invoke" {
  statement_id  = "AllowAPIGInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.search.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "deploy" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  depends_on  = [aws_api_gateway_integration.search_integ]
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.deploy.id
  stage_name    = "prod"
}

#####################################################
# CLOUDFRONT
#####################################################

resource "aws_cloudfront_origin_access_control" "frontend_oac" {
  name                              = "frontend-oac"
  description                       = "OAC for CloudFront to access S3 frontend bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_s3_bucket_policy" "frontend_oac" {
  bucket = aws_s3_bucket.frontend.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "cloudfront.amazonaws.com"
        },
        Action = "s3:GetObject",
        Resource = "${aws_s3_bucket.frontend.arn}/*",
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.cdn.arn
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_policy" "pdfs_oac" {
  bucket = aws_s3_bucket.pdfs.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "cloudfront.amazonaws.com"
        },
        Action = "s3:GetObject",
        Resource = "${aws_s3_bucket.pdfs.arn}/*",
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.cdn.arn
          }
        }
      }
    ]
  })
}

resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "s3-frontend"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend_oac.id
  }

  origin {
    domain_name = replace(
      replace(aws_api_gateway_stage.prod.invoke_url, "https://", ""),
      "/prod", ""
    )
    origin_id   = "api-gw"
    origin_path = "/prod"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  origin {
    domain_name              = aws_s3_bucket.pdfs.bucket_regional_domain_name
    origin_id                = "s3-pdfs"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend_oac.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-frontend"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
  }

  ordered_cache_behavior {
    path_pattern           = "/search*"
    target_origin_id       = "api-gw"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    forwarded_values {
      query_string = true
      cookies { forward = "none" }
    }
    min_ttl     = 0
    default_ttl = 300
    max_ttl     = 3600
  }

  ordered_cache_behavior {
    path_pattern           = "*.pdf"
    target_origin_id       = "s3-pdfs"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
    min_ttl     = 0
    default_ttl = 86400
    max_ttl     = 31536000
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

#####################################################
# CLOUDWATCH METRICS
#####################################################

resource "aws_cloudwatch_query_definition" "ingest_metrics" {
  name = "IngestLambdaMetrics-${random_id.suffix.hex}"

  log_group_names = ["/aws/lambda/${aws_lambda_function.ingest.function_name}"]

  query_string = <<-EOF
    fields @timestamp, @requestId, @duration, @maxMemoryUsed, @initDuration
    | stats avg(@duration) as avg_duration,
            max(@duration) as max_duration,
            avg(@maxMemoryUsed) as avg_mem_used,
            max(@initDuration) as max_cold_start
    by bin(5m)
    | sort @timestamp desc
    | limit 20
  EOF
}
