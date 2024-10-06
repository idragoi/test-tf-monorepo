variable "environment" {
  description = "Module environment type."
  type = string

  validation {
        condition     = contains(["prod", "dev"], var.environment)
        error_message = "Valid values for environment are (prod or dev)."
  } 
}

variable "description" {
  description = "Module instance description"
  type = string
}

variable "module_name" {
  description = "Name of the module. Will be used as prefix for module resources."
  type = string
}

variable "source_bucket_name" {
  description = "Name of the source S3 bucket"
  type = string
}
variable "source_bucket_log_prefix" {
  description = "S3 prefix from the source bucket where logs are stored"
  type = string
}
variable "copy_logs_role_arn" {
  description = "ARN of the IAM role with permissions to copy logs from source bucket"
  type = string
}

variable "encryption_config" {
    description = "Map containing server-side encryption configuration."
    type = map(any)
    default = {
        rule = {
            apply_server_side_encryption_by_default = {
                kms_master_key_id = "aws/s3"
                sse_algorithm     = "aws:kms"
            }
            bucket_key_enabled = true
        }
    }
}
variable "versioning_config" {
  description = "Map containing versioning configuration."
  type = map(any)
  default = {
    status     = false
    mfa_delete = false
  }
}

variable "file_name_zip" {
  default     = "../code/lambda_function.zip"
  description = "File Name in Zip"
  type        = string
}
variable "lambda_function_vpc_subnet_list" {
  description = "List of subnet ids when Lambda Function should run in the VPC. Usually private or intra subnets."
  type = list(string)
}
variable "lambda_function_security_group_list" {
  description = "List of security group ids when Lambda Function should run in the VPC."
  type = list(string)
}
variable "lambda_function_memory_size" {
  description = "Amount of memory in MB your Lambda Function can use at runtime. Valid value between 128 MB to 10,240 MB (10 GB), in 64 MB increments."
  type = number
  default = 128
}
variable "lambda_function_storage_size" {
  description = "Amount of ephemeral storage (/tmp) in MB your Lambda Function can use at runtime. Valid value between 512 MB to 10,240 MB (10 GB)."
  type = number
  default = 512
}
variable "lambda_logging_level" {
  description = "Lambda logging level. Defaults to INFO"
  type = string
  default = "INFO"
}
variable "copy_schedule" {
  description = "Trigger for Lambda function to copy logs. Defaults to 3AM daily."
  type = string
  default = "cron(0 3 * * ? *)"
}

variable "copy_objects_start_date" {
  description = "The date from which we start to copy S3 objects."
  type = string
  validation {
    condition = can(regex("^\\d{4}/(0[1-9]|1[0,1,2])/(0[1-9]|[12][0-9]|3[01])$", var.copy_objects_start_date))
    error_message = "Date format must be YYYY/MM/DD"
  }
}



