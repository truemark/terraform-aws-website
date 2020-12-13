locals {
  s3_origin_id = "S3-${var.name}"
  fqdns = [
    for d in var.domain_names:
    format("%s%s%s", d.record_name, d.record_name == "" ? "" : ".", d.zone_name)
  ]
}

data "aws_acm_certificate" "spa" {
  domain = var.certificate_domain
  most_recent = true
}

data "aws_s3_bucket" "spa" {
  bucket = var.s3_bucket
}

#------------------------------------------------------------------------------
# Redirect Lambda
#------------------------------------------------------------------------------
resource "aws_iam_role" "redirect" {
  name = "${var.name}-lambda-redirect"
  assume_role_policy = file("${path.module}/lambda_policy.json")
  tags = {
    Name = "${var.name}-lambda-redirect"
  }
}

data "template_file" "redirect" {
  template = file("${path.module}/redirect/redirect.tpl.js")
  vars = {
    domain = element(local.fqdns, 0)
  }
}

resource "local_file" "redirect" {
  content     = data.template_file.redirect.rendered
  filename    = "${path.module}/redirect/redirect.js"
  depends_on = [data.template_file.redirect]
}

data "archive_file" "redirect" {
  type        = "zip"
  source_dir  = "${path.module}/redirect"
  output_path = "${path.module}/redirect.zip"
  depends_on = [local_file.redirect]
}

resource "aws_lambda_function" "redirect" {
  filename          = data.archive_file.redirect.output_path
  source_code_hash  = data.archive_file.redirect.output_base64sha256
  function_name     = "${var.name}-redirect"
  role              = aws_iam_role.redirect.arn
  handler           = "redirect.handler"
  publish           = true
  runtime           = "nodejs12.x"
}

#------------------------------------------------------------------------------
# Index Lambda
#------------------------------------------------------------------------------
resource "aws_iam_role" "index" {
  name = "${var.name}-lambda-index"
  assume_role_policy = file("${path.module}/lambda_policy.json")
  tags = {
    Name = "${var.name}-lambda-index"
  }
}

data "template_file" "index" {
  template = file("${path.module}/index/index.tpl.js")
  vars = {
    domain = element(local.fqdns, 0)
  }
}

resource "local_file" "index" {
  content     = data.template_file.index.rendered
  filename    = "${path.module}/index/index.js"
  depends_on = [data.template_file.index]
}

data "archive_file" "index" {
  type        = "zip"
  source_dir  = "${path.module}/index"
  output_path = "${path.module}/index.zip"
  depends_on = [local_file.index]
}

resource "aws_lambda_function" "index" {
  filename          = data.archive_file.index.output_path
  source_code_hash  = data.archive_file.index.output_base64sha256
  function_name     = "${var.name}-index"
  role              = aws_iam_role.index.arn
  handler           = "index.handler"
  publish           = true
  runtime           = "nodejs12.x"
}

#------------------------------------------------------------------------------
# CloudFront Distribution
#------------------------------------------------------------------------------
resource "aws_cloudfront_origin_access_identity" "spa" {
  comment = var.name
}

data "aws_iam_policy_document" "spa" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${data.aws_s3_bucket.spa.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.spa.iam_arn]
    }
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = [data.aws_s3_bucket.spa.arn]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.spa.iam_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "spa" {
  bucket = data.aws_s3_bucket.spa.id
  policy = data.aws_iam_policy_document.spa.json
}

resource "aws_cloudfront_distribution" "spa" {

  origin {
    domain_name = data.aws_s3_bucket.spa.bucket_regional_domain_name
    origin_id   = local.s3_origin_id
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.spa.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = var.name
  default_root_object = "index.html"
  aliases             = local.fqdns

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    lambda_function_association {
      event_type = "viewer-request"
      lambda_arn = aws_lambda_function.redirect.qualified_arn
    }

    lambda_function_association {
      event_type = "origin-request"
      lambda_arn = aws_lambda_function.index.qualified_arn
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = var.price_class

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    minimum_protocol_version = var.minimum_protocol_version
    ssl_support_method = "sni-only"
    acm_certificate_arn = data.aws_acm_certificate.spa.arn
  }

  custom_error_response {
    error_code = "403"
    response_page_path = var.error_403_response_page_path
    response_code = var.error_403_response_code
    error_caching_min_ttl = var.error_403_caching_min_ttl
  }

  custom_error_response {
    error_code = "404"
    response_page_path = var.error_404_response_page_path
    response_code = var.error_404_response_code
    error_caching_min_ttl = var.error_404_caching_min_ttl
  }
}

#------------------------------------------------------------------------------
# Route53 Records
#------------------------------------------------------------------------------
data "aws_route53_zone" "spa" {
  count = length(var.domain_names)
  name = var.domain_names[count.index].zone_name
  private_zone = false
}

resource "aws_route53_record" "spa" {
  count = length(var.domain_names)
  zone_id = data.aws_route53_zone.spa[count.index].id
  name    = var.domain_names[count.index].record_name
  type    = "A"
  alias {
    name = aws_cloudfront_distribution.spa.domain_name
    zone_id = aws_cloudfront_distribution.spa.hosted_zone_id
    evaluate_target_health = false
  }
}

#------------------------------------------------------------------------------
# Invalidation Policy
#------------------------------------------------------------------------------
resource "aws_iam_policy" "spa" {
  name = var.name
  path = var.path
  description = "Allows invalidation requests"
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowInvalidate",
            "Effect": "Allow",
            "Action": "cloudfront:CreateInvalidation",
            "Resource": "${aws_cloudfront_distribution.spa.arn}"
        }
    ]
}
EOF
}
