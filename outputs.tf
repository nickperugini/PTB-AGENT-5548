output "api1_url" {
  value = aws_apigatewayv2_api.api1.api_endpoint
}
output "api2_url" {
  value = aws_apigatewayv2_api.api2.api_endpoint
}
output "bucket_name" {
  value = aws_s3_bucket.shared.bucket
}
