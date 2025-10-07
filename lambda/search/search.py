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
        page = int(params.get("page", 1))  # Default to page 1
    elif "rawQueryString" in event:
        query = event["rawQueryString"].split("=")[-1]
        page = 1
    else:
        query = ""
        page = 1

    if not query:
        return respond(400, {"error": "Missing query parameter q"})

    # Pagination settings
    page_size = 20  # Results per page
    from_index = (page - 1) * page_size  # Skip previous pages

    # Elasticsearch query with highlighting and pagination
    es_query = {
        "from": from_index,
        "size": page_size,
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
        response_data = res.json()
        hits = response_data.get("hits", {}).get("hits", [])
        total_hits = response_data.get("hits", {}).get("total", {}).get("value", 0)
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

    # Calculate pagination info
    total_pages = (total_hits + page_size - 1) // page_size  # Round up

    return respond(200, {
        "results": results,
        "pagination": {
            "current_page": page,
            "page_size": page_size,
            "total_results": total_hits,
            "total_pages": total_pages,
            "has_next": page < total_pages,
            "has_prev": page > 1
        }
    })


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
