terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

resource "random_id" "suffix" {
  byte_length = 4
}

# 1. S3 Bucket (Access logging & KMS CMK intentionally omitted to maintain $0 Free Tier cost; free AES256 enabled below)
#trivy:ignore:AWS-0089
resource "aws_s3_bucket" "site" {
  bucket        = "nejamul-iac-web-${random_id.suffix.hex}"
  force_destroy = true
}

# 2. Free Server-Side Encryption (SSE-S3 AES256 - $0 cost)
#trivy:ignore:AWS-0132
resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 3. Enable Bucket Versioning (Resolves AWS-0090 at $0 cost)
resource "aws_s3_bucket_versioning" "site" {
  bucket = aws_s3_bucket.site.id

  versioning_configuration {
    status = "Enabled"
  }
}

# 4. Enable Static Website Hosting
resource "aws_s3_bucket_website_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  index_document {
    suffix = "index.html"
  }
}

# 5. Public Access Block (Public policy intentionally allowed for static website hosting)
#trivy:ignore:AWS-0087
#trivy:ignore:AWS-0093
resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false
  restrict_public_buckets = false
}

# 6. Least-Privilege Read-Only Bucket Policy (s3:GetObject only)
resource "aws_s3_bucket_policy" "public_read" {
  depends_on = [aws_s3_bucket_public_access_block.site]
  bucket     = aws_s3_bucket.site.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.site.arn}/*"
      }
    ]
  })
}

# 7. Upload index.html
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.site.id
  key          = "index.html"
  source       = "${path.module}/site/index.html"
  content_type = "text/html"
  etag         = filemd5("${path.module}/site/index.html")
}

# 8. Output live URL
output "website_url" {
  value = "http://${aws_s3_bucket_website_configuration.site.website_endpoint}"
}
