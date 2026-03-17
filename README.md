![POC](https://img.shields.io/badge/status-proof_of_concept-orange)
![macOS](https://img.shields.io/badge/platform-macOS_26-blue)
![AI](https://img.shields.io/badge/AI-MCP_powered-purple)

# HealthCheck

**An exploratory proof-of-concept for structured data digestion between LLMs, AI agents, and document data.**

HealthCheck explores a third approach to giving AI access to your data, beyond context stuffing and RAG. It uses the Model Context Protocol (MCP) to let an AI agent read, understand, and structure health documents into a relational database, then query that structured data on demand.

The result: your medical records become a queryable, structured knowledge base that the AI reasons over, not a blob of text crammed into a prompt.

---

## The Problem

Medical documents are dense, multilingual, and full of structured information (lab values, medications, diagnoses) trapped in unstructured PDFs. Current approaches to giving AI access to this data have real limitations:

### Context Stuffing

Dump the raw document text into the LLM's context window.

- **Token limits** - A patient with 40+ PDFs easily exceeds context windows. You can't fit a medical history into a single prompt.
- **No persistence** - Every conversation starts from scratch. The AI re-reads everything every time.
- **Cost** - Sending 100K+ tokens per query is expensive and slow.
- **No structure** - The AI sees flat text. It can't cross-reference a lab result from 2020 with a diagnosis from 2022 without both being in the same prompt.
- **Privacy risk** - The entire document is sent to the model provider on every request, even if the question only needs one data point.

### RAG (Retrieval-Augmented Generation)

Embed document chunks into a vector database, retrieve the top-k most similar chunks per query.

- **Lossy retrieval** - Embedding similarity is approximate. A query about "cholesterol" might miss a chunk that says "lipid panel" or uses a non-English medical term. Multilingual documents break semantic search.
- **No relational reasoning** - RAG retrieves text fragments, not structured data. It can't answer "show me how my hemoglobin trended over 3 years" because it doesn't know which chunks are lab results, what the values are, or how they relate across documents.
- **Chunk boundaries** - A lab report table split across chunks loses its structure. The value ends up in one chunk, the reference range in another.
- **No data model** - Everything is flat text. There's no concept of "patient", "medication", or "encounter", just similar-looking strings.
- **Privacy** - Chunks are typically sent to an embedding service, then stored in a vector DB. The data leaves your machine.

### Structured Digestion (This Approach)

Use the AI agent itself to read documents, extract structured clinical data into a relational database, and then query that database through typed tools.

- **Full structure** - Lab results have values, units, reference ranges, and flags. Medications have dosages, frequencies, and prescribing doctors. Diagnoses have ICD codes and statuses. The AI works with structured records, not text fragments.
- **Relational queries** - "Show me all abnormal labs from the last 2 years" is a database query, not a semantic search. Cross-referencing across documents, time periods, and clinical entities is trivial.
- **No token waste** - The AI only retrieves the specific data it needs. A question about allergies pulls 3 rows, not 50 pages of PDFs.
- **Persistence** - Data is extracted once, structured once, and queryable forever. No re-processing on every conversation.
- **Complete privacy** - All data stays in a local SQLite database on your machine. The AI agent calls local MCP tools, no embeddings sent to external services, no vector DB in the cloud, no document text in API requests. The model only sees the structured query results it explicitly requests.
- **AI-native extraction** - The same LLM that answers your questions also reads and understands the documents. It handles multilingual content, OCR artifacts, and ambiguous formatting naturally, no brittle regex or template matching.
- **Provenance tracking** - Every extracted entity links back to the exact document chunk it came from, with confidence scores. You can always trace a data point to its source.

---

## How It Works

```
PDF Document
  ↓
PDFParser (PDFKit embedded text + Vision OCR with structure detection)
  ↓
TextReconciler (picks best text version per page, scores quality)
  ↓
TextChunker (splits text using paragraph/section boundaries)
  ↓
SQLite Database (18 relational tables: patients, encounters, labs, meds, etc.)
  ↓
MCP Server (37 tools: ingestion, CRUD, query)
  ↓
AI Agent (reads document text → extracts structured data → answers questions)
```

The key insight: **the MCP server is a dumb data layer**. It parses PDFs and stores/retrieves data. The AI agent does the intelligence: reading documents, understanding clinical content across languages, extracting entities, and resolving ambiguities. The server provides raw text, the agent reasons about it, then calls back with structured data.

---

## Example: End-to-End Flow

```
User: "Ingest my blood test from CentralLab"

Agent: calls ingest_document     -> PDF parsed, text extracted, chunks stored
Agent: calls get_document_text   -> reads the raw text
Agent: (understands foreign-language medical terminology)
Agent: calls upsert_facility     -> creates CentralLab record
Agent: calls create_encounter    -> creates the lab visit
Agent: calls create_lab_result   -> x13, stores each test with values, units, ranges, flags
Agent: calls store_extraction_results -> links entities back to source document
Agent: calls save_document_summary    -> stores clinical summary

User: "What was my MPV?"

Agent: calls get_lab_history(test_name: "MPV") -> gets structured result
Agent: "Your MPV was 11.6 fL (reference: 6.5-11.0), slightly elevated."
```

No context stuffing. No embedding search. One precise database query.

---

## Comparison

| | Context Stuffing | RAG | Structured Digestion |
|---|---|---|---|
| **Data format** | Raw text in prompt | Text chunks + embeddings | Typed relational records |
| **Query precision** | Depends on what's in context | Approximate similarity | Exact database queries |
| **Cross-document reasoning** | Only if both docs fit in context | Poor, chunks are isolated | Native, relational joins |
| **Persistence** | None, re-send every time | Embeddings persist, text doesn't | Full structured persistence |
| **Token efficiency** | Send everything, every time | Send top-k chunks | Send only requested fields |
| **Multilingual** | Works if model understands | Embeddings may miss translations | AI extracts at ingestion time |
| **Privacy** | Full text sent every request | Text sent to embedding service | All data stays local |
| **Structured queries** | "Find labs where..." = hope | Approximate at best | `WHERE flag = 'high' AND test_date > '2023-01-01'` |
| **Provenance** | None | Chunk reference | Entity -> chunk -> document -> page |

---

## Trade-offs

This approach isn't universally better. It has real costs:

- **Upfront extraction effort** - The AI must read and structure each document, which takes time and API calls. Context stuffing and RAG are faster to set up.
- **Extraction errors** - The AI can misread values or miss entities. The system tracks confidence scores and supports review, but it's not perfect.
- **Schema rigidity** - The relational schema must be designed upfront. New entity types require schema changes. RAG handles arbitrary content more flexibly.
- **Best for structured data** - Medical records, financial documents, and lab reports benefit most. Free-form text (essays, emails) may not gain much from structured extraction.

For medical records specifically, the trade-offs favor structured digestion: the data is inherently structured, precision matters, privacy is critical, and patients accumulate documents over years that need cross-referencing.

---

## Tech Stack

- **Swift** with Swift 6 concurrency
- **MCP** - Model Context Protocol via `swift-sdk` v0.11.0 (stdio transport)
- **GRDB/SQLite** - 18 tables, typed Codable records, migrations
- **PDFKit + Vision** - Dual text extraction (embedded + OCR with structure detection)
- **Swift Testing** - 67 tests across 13 test files

## Setup

```bash
swift build                    # Build
swift test                     # Run tests (67 passing)
swift run HealthCheck --init   # Initialize database
swift run HealthCheck          # Start MCP server
```

## Status

This is a proof of concept exploring the structured digestion pattern. It is not production software. The extraction pipeline works end-to-end with real multilingual medical PDFs, but the approach needs more testing across document types and edge cases before drawing definitive conclusions.
