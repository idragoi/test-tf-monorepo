output "s3_bucket_id" {
  description = "The name of the bucket."
  value       = module.target_s3_bucket.s3_bucket_id
}
output "s3_bucket_arn" {
  description = "The ARN of the bucket. Will be of format arn:aws:s3:::bucketname."
  value       = module.target_s3_bucket.s3_bucket_arn
}
output "lambda_function_arn" {
  description = "The ARN of the Lambda Function"
  value       = module.lambda_function.lambda_function_arn
}
output "lambda_role_arn" {
  description = "The ARN of the IAM role created for the Lambda Function"
  value       = module.lambda_function.lambda_role_arn
}
output "lambda_cloudwatch_log_group_arn" {
  description = "The ARN of the Cloudwatch Log Group"
  value       = module.lambda_function.lambda_cloudwatch_log_group_arn
}
output "eventbridge_rule_arns" {
  description = "The EventBridge Rule ARNs"
  value       = module.eventbridge_lambda_schedule.eventbridge_rule_arns
}
output "ssm_parameter_arn" {
  description = "The ARN of the parameter"
  value       = module.ssm_parameter.ssm_parameter_arn
}
