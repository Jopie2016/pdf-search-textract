#####################################################
# outputs.tf – With Lambda Resource Info
#####################################################

output "HOW_TO_USE" {
  description = "Instructions after deploy"
  value = <<EOT
Deployment finished! Next steps:

1) **Lambda code layout**
   barry_allen_demo/
     lambda/
       ingest/
         ingest.py
       search/
         search.py
     terraform/
       main.tf, outputs.tf, variables.tf
       build/   (Terraform auto-creates .zip files here)

   Terraform zips your Lambda source directories into:
     terraform/build/ingest.zip
     terraform/build/search.zip

2) **Upload your PDFs**
   aws s3 cp ./search_demo_files/ s3://${aws_s3_bucket.pdfs.bucket} --recursive

3) **Build & deploy the React frontend**
   cd frontend
   npm run build
   aws s3 sync ./build/ s3://${aws_s3_bucket.frontend.bucket} --delete

4) **Open your CloudFront URL**
   https://${aws_cloudfront_distribution.cdn.domain_name}

5) **Test the API directly**
   curl "https://${aws_cloudfront_distribution.cdn.domain_name}/search?q=test"

6) **(Debug only) Access Elasticsearch directly**
   ${local.es_endpoint}

EOT
}

output "api_invoke_url" {
  value = aws_api_gateway_stage.prod.invoke_url
}

output "cloudfront_domain" {
  value = aws_cloudfront_distribution.cdn.domain_name
}

output "elasticsearch_http" {
  value = local.es_endpoint
}

output "frontend_bucket" {
  value = aws_s3_bucket.frontend.bucket
}

output "pdf_bucket" {
  value = aws_s3_bucket.pdfs.bucket
}

# Lambda packaging sizes
output "ingest_lambda_size" {
  value = aws_lambda_function.ingest.source_code_size
}

output "search_lambda_size" {
  value = aws_lambda_function.search.source_code_size
}

# Lambda resource info (memory + timeout)
output "ingest_lambda_memory" {
  value = aws_lambda_function.ingest.memory_size
}

output "ingest_lambda_timeout" {
  value = aws_lambda_function.ingest.timeout
}

output "search_lambda_memory" {
  value = aws_lambda_function.search.memory_size
}

output "search_lambda_timeout" {
  value = aws_lambda_function.search.timeout
}


output "ingest_metrics_query_id" {
  description = "CloudWatch Logs Insights query for ingest Lambda performance"
  value       = aws_cloudwatch_query_definition.ingest_metrics.id
}

output "search_lambda_env" {
  description = "Environment variables for the search Lambda"
  value = aws_lambda_function.search.environment[0].variables
}
