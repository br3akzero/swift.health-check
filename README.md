![Beta](https://img.shields.io/badge/status-beta-orange)
![macOS](https://img.shields.io/badge/platform-macOS_26-blue)
![AI](https://img.shields.io/badge/AI-MCP_powered-purple)

Better than basic RAG or Context Window Stuffing for health data

# HealthCheck

AI-enabled health document processing system. Ingest patient health PDFs, extract structured clinical data, and answer health questions interactively via an MCP server.

All data lives in a local SQLite database on your machine. The AI agent retrieves what it needs through MCP tools to answer your questions — your health data is never stored in the model's context or sent to external services.

## Processing Pipeline

```
PDF File
  ↓
PDFParser (PDFKit embedded text + Vision OCR with structure detection)
  ↓
TextReconciler (picks best text version per page, scores quality)
  ↓
TextChunker (splits text using paragraph/section boundaries)
  ↓
SQLite (structured clinical tables + document chunks)
  ↓
MCP Server (35 tools: ingestion, CRUD, query)
  ↓
AI Agent (reasons over structured data, answers questions)
```
