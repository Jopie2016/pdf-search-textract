# PDF Search System with AWS Textract & Elasticsearch

A full-stack serverless application that automatically extracts text from PDF documents using AWS Textract, indexes them in Elasticsearch, and provides a React-based search interface with highlighted snippets.


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
  
