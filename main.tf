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
# Viewer Request Lambda
#------------------------------------------------------------------------------
resource "aws_iam_role" "viewer_request" {
  name = "${var.name}-viewer-request"
  assume_role_policy = file("${path.module}/lambda_policy.json")
  tags = {
    Name = "${var.name}-lambda"
  }
}

data "template_file" "viewer_request" {
  template = file("${path.module}/viewer_request/index.tpl.js")
  vars = {
    domain = element(local.fqdns, 0)
  }
}

resource "local_file" "viewer_request" {
  content     = data.template_file.viewer_request.rendered
  filename    = "${path.module}/viewer_request/index.js"
  depends_on = [data.template_file.viewer_request]
}

data "archive_file" "viewer_request" {
  type        = "zip"
  source_dir  = "${path.module}/viewer_request"
  output_path = "${path.module}/viewer_request.zip"
}

resource "aws_lambda_function" "viewer_request" {
  filename          = data.archive_file.viewer_request.output_path
  source_code_hash  = data.archive_file.viewer_request.output_base64sha256
  function_name     = "${var.name}-viewer-request"
  role              = aws_iam_role.viewer_request.arn
  handler           = "index.handler"
  publish           = true
  runtime           = "nodejs12.x"
}

//resource "aws_cloudwatch_log_group" "viewer_request" {
//  name              = "/aws/lambda/${aws_lambda_function.viewer_request.function_name}"
//  retention_in_days = 2
//  tags = {}
//}

resource "aws_iam_policy" "viewer_request" {
  name        = "${var.name}-viewer-request"
  path        = "/"
  description = "IAM policy for logging from a lambda"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*",
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "viewer_request" {
  policy_arn = aws_iam_policy.viewer_request.arn
  role = aws_iam_role.viewer_request.name
}

#------------------------------------------------------------------------------
# Origin Request Lambda
#------------------------------------------------------------------------------
resource "aws_iam_role" "origin_request" {
  name = "${var.name}-origin-request"
  assume_role_policy = file("${path.module}/lambda_policy.json")
  tags = {
    Name = "${var.name}-lambda"
  }
}

data "template_file" "origin_request" {
  template = file("${path.module}/origin_request/index.tpl.js")
  vars = {
    domain = element(local.fqdns, 0)
  }
}

resource "local_file" "origin_request" {
  content     = data.template_file.origin_request.rendered
  filename    = "${path.module}/origin_request/index.js"
  depends_on = [data.template_file.origin_request]
}

data "archive_file" "origin_request" {
  type        = "zip"
  source_dir  = "${path.module}/origin_request"
  output_path = "${path.module}/origin_request.zip"
}

resource "aws_lambda_function" "origin_request" {
  filename          = data.archive_file.origin_request.output_path
  source_code_hash  = data.archive_file.origin_request.output_base64sha256
  function_name     = "${var.name}-origin-request"
  role              = aws_iam_role.origin_request.arn
  handler           = "index.handler"
  publish           = true
  runtime           = "nodejs12.x"
}

//resource "aws_cloudwatch_log_group" "origin_request" {
//  name              = "/aws/lambda/${aws_lambda_function.origin_request.function_name}"
//  retention_in_days = 2
//  tags = {}
//}

resource "aws_iam_policy" "origin_request" {
  name        = "${var.name}-origin-request"
  path        = "/"
  description = "IAM policy for logging from a lambda"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*",
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "origin_request" {
  policy_arn = aws_iam_policy.origin_request.arn
  role = aws_iam_role.origin_request.name
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
      lambda_arn = aws_lambda_function.viewer_request.qualified_arn
    }

    lambda_function_association {
      event_type = "origin-request"
      lambda_arn = aws_lambda_function.origin_request.qualified_arn
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
