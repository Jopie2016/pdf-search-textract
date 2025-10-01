#!/usr/bin/env python3
import boto3
import json
import time

BUCKET = "pdf-input-04e616"
LAMBDA = "pdf-ingest-04e616"

# Initialize clients
s3 = boto3.client('s3')
lambda_client = boto3.client('lambda')

# List all PDFs
print("Fetching PDF list from S3...")
response = s3.list_objects_v2(Bucket=BUCKET)
pdfs = [obj['Key'] for obj in response.get('Contents', []) if obj['Key'].endswith('.pdf')]

print(f"Found {len(pdfs)} PDFs. Starting processing...")

success = 0
failed = 0

for i, filename in enumerate(pdfs, 1):
    print(f"[{i}/{len(pdfs)}] Processing: {filename}")

    # Create S3 event payload
    payload = {
        "Records": [
            {
                "s3": {
                    "bucket": {
                        "name": BUCKET
                    },
                    "object": {
                        "key": filename
                    }
                }
            }
        ]
    }

    try:
        # Invoke Lambda asynchronously
        lambda_client.invoke(
            FunctionName=LAMBDA,
            InvocationType='Event',
            Payload=json.dumps(payload)
        )
        success += 1
    except Exception as e:
        print(f"  ERROR: {e}")
        failed += 1

    # Rate limit (5 per second)
    time.sleep(0.2)

print(f"\nDone! Processed {success} PDFs successfully, {failed} failed.")
print("Check Elasticsearch count in a few minutes:")
print("curl -s 'http://ec2-44-197-232-195.compute-1.amazonaws.com:9200/pdfs/_count?pretty'")
