import os
import json
import boto3
import time
import urllib.parse
import requests
from requests.exceptions import RequestException

# AWS clients
s3 = boto3.client("s3")
textract = boto3.client("textract")

# Elasticsearch connection (Terraform passes ES_HOST via env var)
ES_HOST = os.environ["ES_HOST"]               # e.g., http://<EC2-IP>:9200
INDEX = os.environ.get("INDEX", "pdfs")       # default index = "pdfs"


def lambda_handler(event, context):
    """
    Lambda entrypoint.
    Triggered by S3 -> new PDF uploaded.
    - Start Textract job
    - Poll until completion
    - Extract text per page
    - Index results into Elasticsearch with _bulk
    """
    print(f"Event received: {json.dumps(event)}")

    for record in event["Records"]:
        bucket = record["s3"]["bucket"]["name"]
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])
        print(f"Processing PDF: s3://{bucket}/{key}")

        # 1. Start Textract async job
        job_id = start_textract_job(bucket, key)
        if not job_id:
            print(f"❌ Could not start Textract for {key}")
            continue

        # 2. Poll for results
        pages = get_textract_results(job_id)
        print(f"✅ Textract completed: {len(pages)} pages extracted from {key}")

        if not pages:
            print(f"⚠️ No text extracted from {key}")
            continue

        # 3. Prepare bulk payload for Elasticsearch
        actions = []
        for page_num, text in enumerate(pages, start=1):
            doc_id = f"{key}__{page_num}"
            meta = {"index": {"_index": INDEX, "_id": doc_id}}
            doc = {
                "filename": key,
                "page": page_num,
                "content": text,
            }
            actions.append(json.dumps(meta))
            actions.append(json.dumps(doc))

        bulk_payload = "\n".join(actions) + "\n"

        # 4. Send bulk request
        bulk_index(bulk_payload, key, len(pages))

    return {"status": "done"}


def start_textract_job(bucket, key):
    """Start async Textract job, return JobId."""
    try:
        response = textract.start_document_text_detection(
            DocumentLocation={"S3Object": {"Bucket": bucket, "Name": key}}
        )
        return response["JobId"]
    except Exception as e:
        print(f"❌ Textract start failed for {key}: {e}")
        return None


def get_textract_results(job_id):
    """
    Poll Textract until job finishes.
    Returns list of text (one per page).
    """
    pages = []

    while True:
        response = textract.get_document_text_detection(JobId=job_id)
        status = response["JobStatus"]

        if status == "SUCCEEDED":
            pages.extend(extract_text(response))

            # Handle pagination with NextToken
            next_token = response.get("NextToken")
            while next_token:
                response = textract.get_document_text_detection(
                    JobId=job_id, NextToken=next_token
                )
                pages.extend(extract_text(response))
                next_token = response.get("NextToken")
            break

        elif status in ["FAILED", "PARTIAL_SUCCESS"]:
            print(f"❌ Textract job {job_id} ended with status: {status}")
            break

        else:
            print(f"⏳ Textract job {job_id} still running...")
            time.sleep(5)

    return pages


def extract_text(response):
    """
    Extract lines grouped by Page.
    Returns list of strings, one per page.
    """
    texts = {}
    for item in response["Blocks"]:
        if item["BlockType"] == "LINE":
            page = item.get("Page", 1)
            texts.setdefault(page, []).append(item["Text"])

    return [" ".join(lines) for _, lines in sorted(texts.items())]


def bulk_index(payload, filename, page_count, retries=3, delay=2):
    """
    Send documents to Elasticsearch using _bulk API.
    Retries on failure.
    """
    url = f"{ES_HOST}/_bulk"

    for attempt in range(1, retries + 1):
        try:
            res = requests.post(
                url,
                data=payload,
                headers={"Content-Type": "application/x-ndjson"},
                timeout=30,
            )

            if res.status_code == 200:
                result = res.json()
                if result.get("errors"):
                    print(f"⚠️ Bulk indexing for {filename} had errors: {result}")
                else:
                    print(f"✅ Bulk indexed {page_count} pages from {filename}")
                return
            else:
                print(f"⚠️ Attempt {attempt}: ES returned {res.status_code} {res.text}")

        except RequestException as e:
            print(f"⚠️ Attempt {attempt}: Request failed: {e}")

        time.sleep(delay)

    print(f"❌ Bulk indexing failed for {filename} after {retries} retries")
