import os
import json
import requests
from urllib.parse import quote

ES_HOST = os.environ["ES_HOST"]   # e.g. http://<EC2-IP>:9200
INDEX = os.environ.get("INDEX", "pdfs")
CLOUDFRONT_DOMAIN = os.environ.get("CLOUDFRONT_DOMAIN")  # from Terraform

def lambda_handler(event, context):
    # Support API Gateway v1 & v2 events
    if "queryStringParameters" in event:
        params = event["queryStringParameters"] or {}
        query = params.get("q", "")
    elif "rawQueryString" in event:
        query = event["rawQueryString"].split("=")[-1]
    else:
        query = ""

    if not query:
        return respond(400, {"error": "Missing query parameter q"})

    # Elasticsearch query with highlighting
    es_query = {
        "query": {
            "multi_match": {
                "query": query,
                "fields": ["content"]
            }
        },
        "highlight": {
            "fields": {
                "content": {
                    "fragment_size": 150,
                    "number_of_fragments": 1
                }
            }
        },
        "_source": ["filename"]
    }

    url = f"{ES_HOST}/{INDEX}/_search"
    try:
        res = requests.post(
            url,
            headers={"Content-Type": "application/json"},
            data=json.dumps(es_query),
            timeout=10
        )
        res.raise_for_status()
        hits = res.json().get("hits", {}).get("hits", [])
    except Exception as e:
        return respond(500, {"error": f"Search request failed: {str(e)}"})

    results = []
    for h in hits:
        src = h.get("_source", {})
        snippet = ""
        if "highlight" in h and "content" in h["highlight"]:
            snippet = h["highlight"]["content"][0]

        filename = src.get("filename", "unknown.pdf")

        # Build CloudFront URL to PDF with proper encoding
        pdf_url = None
        if CLOUDFRONT_DOMAIN:
            # URL-encode the filename to handle spaces and special chars
            encoded_filename = quote(filename, safe='')
            pdf_url = f"https://{CLOUDFRONT_DOMAIN}/{encoded_filename}"

        results.append({
            "filename": filename,
            "snippet": snippet,
            "url": pdf_url
        })

    return respond(200, {"results": results})


def respond(status, body):
    """Return API Gateway-compatible response with CORS headers."""
    return {
        "statusCode": status,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type"
        },
        "body": json.dumps(body)
    }
