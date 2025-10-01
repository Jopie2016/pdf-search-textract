# PDF Search System with AWS Textract & Elasticsearch

A full-stack serverless application that automatically extracts text from PDF documents using AWS Textract, indexes them in Elasticsearch, and provides a React-based search interface with highlighted snippets.

![Architecture Diagram](https://via.placeholder.com/800x400?text=PDF+Search+Architecture)

## 🎯 Features

- **Automated PDF Processing**: Upload PDFs to S3 and they're automatically processed via AWS Textract
- **Full-Text Search**: Query across all indexed documents with Elasticsearch
- **Highlighted Snippets**: Search results show matching text with highlights
- **PDF Preview Links**: Direct links to view full PDF documents via CloudFront
- **Serverless Architecture**: Pay only for what you use with Lambda and managed services
- **React Frontend**: Clean, responsive search interface

## 🏗️ Architecture

```
┌─────────────┐      ┌──────────────┐      ┌─────────────┐
│   PDF       │─────▶│ S3 (PDFs)    │─────▶│ Ingest      │
│   Upload    │      │              │      │ Lambda      │
└─────────────┘      └──────────────┘      └──────┬──────┘
                                                   │
                                                   ▼
┌─────────────┐      ┌──────────────┐      ┌─────────────┐
│   React     │◀─────│  CloudFront  │      │  Textract   │
│   Frontend  │      │              │      │             │
└──────┬──────┘      └──────┬───────┘      └──────┬──────┘
       │                    │                     │
       │                    │                     ▼
       │             ┌──────▼───────┐      ┌─────────────┐
       │             │  API Gateway │      │Elasticsearch│
       │             │              │      │   (EC2)     │
       │             └──────┬───────┘      └──────▲──────┘
       │                    │                     │
       │             ┌──────▼───────┐             │
       └────────────▶│    Search    │─────────────┘
                     │    Lambda    │
                     └──────────────┘
```

## 🛠️ Tech Stack

### Backend
- **AWS Lambda**: Serverless compute for PDF ingestion and search
- **AWS Textract**: OCR and text extraction from PDFs
- **Elasticsearch 7.17**: Full-text search and indexing (EC2-hosted)
- **AWS S3**: PDF storage (input bucket + frontend bucket)
- **API Gateway**: RESTful API endpoint
- **CloudFront**: CDN for frontend and PDF delivery
- **Terraform**: Infrastructure as Code

### Frontend
- **React**: UI framework
- **Create React App**: Build tooling

## 📁 Project Structure

```
barry_allen_demo/
├── terraform/
│   ├── main.tf           # Main infrastructure definition
│   ├── variables.tf      # Input variables
│   └── outputs.tf        # Output values
├── lambda/
│   ├── ingest/
│   │   └── ingest.py     # Textract processing & ES indexing
│   └── search/
│       └── search.py     # Elasticsearch query handler
├── frontend/
│   ├── src/
│   │   ├── App.js        # Main React component
│   │   ├── Search.js     # Search interface
│   │   └── index.js
│   ├── public/
│   └── package.json
├── reprocess_pdfs.py     # Utility to reindex existing PDFs
├── .gitignore
└── README.md
```

## 🚀 Quick Start

### Prerequisites

- AWS Account with appropriate permissions
- AWS CLI configured (`aws configure`)
- Terraform >= 1.6.0
- Node.js >= 14.x
- Python 3.12+
- SSH key pair for EC2 access (optional)

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/pdf-search-system.git
cd pdf-search-system
```

### 2. Configure Terraform Variables

Create `terraform/terraform.tfvars`:

```hcl
region          = "us-east-1"
es_instance_type = "t3.medium"
ssh_key_name     = "your-key-name"  # Optional
```

### 3. Deploy Infrastructure

```bash
cd terraform
terraform init
terraform apply
```

**Wait ~5 minutes** for Elasticsearch to start on EC2.

### 4. Install Lambda Dependencies

```bash
cd ../lambda/search
pip install requests -t .
cd ../../terraform
terraform apply  # Redeploy with dependencies
```

### 5. Build and Deploy Frontend

```bash
cd ../frontend
npm install
npm run build

# Get bucket name and sync
BUCKET=$(terraform -chdir=../terraform output -raw frontend_bucket)
aws s3 sync ./build/ s3://$BUCKET --delete
```

### 6. Upload PDFs

```bash
BUCKET=$(terraform -chdir=../terraform output -raw pdf_bucket)
aws s3 cp ./your-pdfs/ s3://$BUCKET/ --recursive
```

For existing PDFs (uploaded before setup), run:

```bash
cd ..
python3 reprocess_pdfs.py
```

### 7. Access the Application

```bash
cd terraform
terraform output cloudfront_domain
# Visit https://<cloudfront-domain>
```

## 📖 How It Works

### PDF Ingestion Flow

1. **PDF uploaded** to S3 input bucket
2. **S3 event triggers** Ingest Lambda
3. **Lambda calls Textract** to extract text (async job)
4. **Lambda polls** Textract until complete
5. **Extracted text indexed** into Elasticsearch:
   ```json
   {
     "filename": "document.pdf",
     "page": 1,
     "content": "Full page text..."
   }
   ```

### Search Flow

1. **User types query** in React frontend
2. **Frontend calls** `/search?q=term` via CloudFront
3. **CloudFront proxies** to API Gateway → Search Lambda
4. **Lambda queries** Elasticsearch with highlights
5. **Returns JSON** with snippets + PDF URLs:
   ```json
   {
     "results": [
       {
         "filename": "document.pdf",
         "snippet": "matched <em>term</em> in context",
         "url": "https://<cloudfront>/document.pdf"
       }
     ]
   }
   ```

## 🔍 API Reference

### `GET /search?q={query}`

Search for documents containing the query term.

**Parameters:**
- `q` (string, required): Search query

**Response:**
```json
{
  "results": [
    {
      "filename": "example.pdf",
      "snippet": "Text with <em>highlighted</em> match",
      "url": "https://cloudfront-domain/example.pdf"
    }
  ]
}
```

## 🧪 Monitoring & Debugging

### Check Elasticsearch Health

```bash
ES_HOST=$(terraform output -raw elasticsearch_http)
curl $ES_HOST/_cluster/health?pretty
```

### View Document Count

```bash
curl $ES_HOST/pdfs/_count?pretty
```

### Lambda Logs

```bash
# Ingest Lambda
aws logs tail /aws/lambda/pdf-ingest-<suffix> --follow

# Search Lambda
aws logs tail /aws/lambda/pdf-search-<suffix> --follow
```

## 💰 Cost Estimate

For processing 256 PDFs (~10 pages each):

- **Textract**: ~$4 (2,560 pages × $1.50/1000 pages)
- **Lambda**: ~$0.50 (compute time)
- **EC2 (t3.medium)**: ~$30/month (continuous)
- **S3 Storage**: ~$0.50/month (2GB PDFs)
- **CloudFront**: ~$0.10/month (light usage)
- **API Gateway**: ~$0.01/month (light usage)

**Monthly total**: ~$35-40

## 🗑️ Cleanup

To destroy all resources:

```bash
cd terraform
terraform destroy
```

**⚠️ Warning**: This deletes all S3 data, Elasticsearch, and indexed documents.

## 🔒 Security Considerations

- Elasticsearch currently open on port 9200 (restrict to Lambda SG in production)
- S3 buckets use CloudFront OAC for secure access
- API Gateway has no authentication (add API keys or Cognito as needed)
- Lambda execution roles follow least-privilege principles

## 🎯 Performance Optimizations

- CloudFront caching: 5-minute TTL for search results
- PDF caching: 24-hour TTL
- Elasticsearch query caching (built-in)
- Lambda warm containers reduce cold starts

## 🚧 Future Enhancements

- [ ] Add authentication (Cognito)
- [ ] Support multi-page PDF preview
- [ ] Add filters (date, document type)
- [ ] Implement pagination for search results
- [ ] Add CloudWatch alarms for failures
- [ ] Use OpenSearch Serverless instead of EC2
- [ ] Add CI/CD pipeline
- [ ] Support additional file formats (DOCX, TXT)

## 🐛 Troubleshooting

### PDFs not being indexed
- Check Lambda logs: `aws logs tail /aws/lambda/pdf-ingest-<suffix>`
- Verify Elasticsearch is running: `curl http://<es-ip>:9200`
- Check S3 event notification is configured

### Search returns 502 error
- Verify search Lambda has `requests` library installed
- Check CORS headers are present in Lambda response
- Review Lambda execution role permissions

### Frontend shows nothing
- Clear CloudFront cache: `aws cloudfront create-invalidation --distribution-id <id> --paths "/*"`
- Check browser console for CORS errors
- Verify CloudFront behaviors are configured correctly

### PDF links return 403
- Verify S3 bucket policy allows CloudFront OAC
- Check CloudFront behavior for `*.pdf` path pattern
- Ensure filenames are URL-encoded (spaces = `%20`)

## 📝 License

MIT License - see LICENSE file for details

## 🙏 Acknowledgments

- Built as a demonstration of AWS serverless architecture
- Designed for FDA document search requirements
- Powered by Elasticsearch, AWS Lambda, and React

## 📧 Contact

For questions or issues, please open a GitHub issue or contact the maintainers.

---

**Built with ❤️ using AWS, Terraform, and React**
