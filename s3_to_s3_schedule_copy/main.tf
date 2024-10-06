module "target_s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "4.1.2"

  bucket_prefix = "${var.module_name}-bucket-"
  attach_policy = true
  policy = data.aws_iam_policy_document.bucket_policy.json

  attach_public_policy = false
  attach_deny_insecure_transport_policy    = true
  attach_require_latest_tls_policy         = true
  attach_deny_incorrect_encryption_headers = true
  attach_deny_unencrypted_object_uploads   = true

  restrict_public_buckets = true
  block_public_acls = true
  block_public_policy = true
  ignore_public_acls = true
  
  server_side_encryption_configuration = var.encryption_config
  versioning = var.versioning_config
}

data "aws_iam_policy_document" "bucket_policy" {
  statement {
    principals {
      type        = "AWS"
      identifiers = [var.copy_logs_role_arn]
    }

    actions = [
      "s3:PutObject"
    ]

    resources = ["${module.target_s3_bucket.s3_bucket_arn}/*"]
  }
}

module "eventbridge_lambda_schedule" {
  source  = "terraform-aws-modules/eventbridge/aws"
  version = "3.11.0"

  create_bus = false
  role_name = "${var.module_name}-eb-role"

  rules = {
    cron_daily = {
      description         = var.description
      schedule_expression = var.copy_schedule
      state = var.environment == "prod" ? "ENABLED" : "DISABLED"
    }
  }

  targets = {
    cron_daily = [
      {
        name  = "copy-logs-lambda"
        arn   = module.lambda_function.lambda_function_arn
        input = jsonencode({ "job" : "daily-copy-engine-alb-logs" })
      }
    ]
  }
}

module "lambda_function" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "7.9.0"

  function_name          = "${var.module_name}-function"
  description            = var.description
  handler                = "lambda_function.lambda_handler"
  runtime                = "python3.12"
  memory_size            = var.lambda_function_memory_size
  ephemeral_storage_size = var.lambda_function_storage_size
  vpc_subnet_ids         = var.lambda_function_vpc_subnet_list
  vpc_security_group_ids = var.lambda_function_security_group_list
  architectures          = ["arm64"]
  publish                = false
  create_lambda_function_url = false
  attach_network_policy  = true
  attach_dead_letter_policy = false

  # package_type = "Zip"
  # local_existing_package = var.file_name_zip
  store_on_s3 = false

  source_path = "${path.module}/lambda_code"


  timeout = 900

  environment_variables = {
    LOGGING_LEVEL      = var.lambda_logging_level
    S3_BASE_PREFIX     = var.source_bucket_log_prefix
    LAST_COPY_PARAM_NAME = module.ssm_parameter.ssm_parameter_name
    SOURCE_BUCKET      = var.source_bucket_name
    TARGET_BUCKET      = module.target_s3_bucket.s3_bucket_id
    COPY_LOGS_ROLE_ARN = var.copy_logs_role_arn
    MODULE_NAME        = var.module_name
  }

  allowed_triggers = {
    CopyLogsRule = {
      principal  = "events.amazonaws.com"
      source_arn = module.eventbridge_lambda_schedule.eventbridge_rule_arns["cron_daily"]
    }
  }
  create_current_version_allowed_triggers = false

  cloudwatch_logs_log_group_class = "STANDARD"
  cloudwatch_logs_retention_in_days = 30

  role_path   = "/tf-managed/"
  policy_path = "/tf-managed/"

  attach_policy_statements = true
  policy_statements = {
    copy_logs_iam = {
      effect    = "Allow",
      actions   = ["sts:AssumeRole"],
      resources = [var.copy_logs_role_arn]
    }
    ssm_param = {
      effect    = "Allow",
      actions   = [
        "ssm:GetParameter",
        "ssm:PutParameter"
        ],
      resources = [module.ssm_parameter.ssm_parameter_arn]
    }
  }
}

module "ssm_parameter" {
  source  = "terraform-aws-modules/ssm-parameter/aws"
  version = "1.1.1"

  name            = "${var.module_name}-param"
  description     = var.description
  data_type       = "text"
  tier            = "Standard"
  value           = var.copy_objects_start_date
  ignore_value_changes = true
}