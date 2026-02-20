# How Gregor's Memory Works (ELI5)

## The Big Picture

```
  You write things            Gregor reads them later
  in markdown files           when you ask questions
       │                              ▲
       ▼                              │
┌─────────────┐    "index"    ┌──────────────┐    "search"    ┌─────────┐
│  .md files  │ ──────────►  │  Brain DB     │ ──────────►   │ Results │
│  (raw text) │   chop up    │  (SQLite)     │   find best   │ (top 6) │
└─────────────┘   + digest   └──────────────┘   matches      └─────────┘
```

## Step 1: Writing Memories

Gregor's memory lives as plain markdown files:

```
~/.openclaw/workspace/memory/
└── 2025-07-17.md          ◄── just a text file!
    │
    │  "My name is Gregor. I was created by Marius.
    │   I engage on Lattice for the Demos protocol.
    │   My key directives are..."
```

That's it. Plain text. You (or Gregor) just write `.md` files in that folder.

## Step 2: Indexing (The Meat Grinder)

When you run `openclaw memory index`, this happens:

```
    Your .md file (2992 bytes)
    ┌──────────────────────────────────────────┐
    │ "My name is Gregor. I was created by     │
    │ Marius. I engage on Lattice for the      │
    │ Demos protocol. My key directives are    │
    │ to be helpful, private, and accurate..." │
    └──────────────────────────────────────────┘
                      │
                      ▼  CHOP into chunks
                         (400 tokens each, 80 overlap)
              ┌───────────┬───────────┬─────┐
              │  Chunk 1  │  Chunk 2  │ ... │  = 5 chunks total
              └─────┬─────┴─────┬─────┴─────┘
                    │           │
                    ▼           ▼
              ┌─────────────────────────┐
              │   embeddinggemma-300m   │  ◄── tiny AI brain (329MB)
              │   (runs LOCALLY on VPS) │      lives on your machine
              │                        │      NO data sent anywhere
              └───────────┬────────────┘
                          │
                    turns each chunk into
                    a list of 768 numbers
                          │
                          ▼
              ┌──────────────────────────┐
              │  [0.23, -0.41, 0.87,     │  ◄── "embedding vector"
              │   0.12, -0.55, 0.33,     │      a fingerprint of
              │   ... 768 numbers ...]   │      what the text MEANS
              └──────────────────────────┘
                          │
                          ▼
              ┌──────────────────────────┐
              │  ~/.openclaw/memory/     │
              │  main.sqlite             │  ◄── all chunks + vectors
              │                          │      stored here
              │  ┌────┬────────┬───────┐ │
              │  │ id │ text   │ vec   │ │
              │  ├────┼────────┼───────┤ │
              │  │ 1  │ "My na │ [0.2…]│ │
              │  │ 2  │ "I eng │ [0.4…]│ │
              │  │ 3  │ "My ke │ [-0.1…│ │
              │  │ 4  │ ...    │ ...   │ │
              │  │ 5  │ ...    │ ...   │ │
              │  └────┴────────┴───────┘ │
              └──────────────────────────┘
```

**The key idea:** The 768 numbers capture the *meaning* of the text, not the words. "Lattice protocol" and "Demos network engagement" would have *similar* numbers even though they use different words.

## Step 3: Searching (The Magic Part)

When Gregor gets a question, two searches happen at once:

```
  Question: "What do you know about Lattice?"
                    │
        ┌───────────┴───────────┐
        ▼                       ▼
   VECTOR SEARCH           TEXT SEARCH
   (meaning-based)         (word-based)
        │                       │
        │  Turn question        │  Just look for
        │  into 768 numbers,    │  the word "Lattice"
        │  find chunks with     │  in the text
        │  similar numbers      │
        │                       │
        │  Score: 0.724         │  Score: exact match
        ▼                       ▼
        └───────────┬───────────┘
                    │
                    ▼  COMBINE (hybrid)
              ┌─────────────┐
              │ 70% vector  │  ◄── meaning matters more
              │ 30% text    │  ◄── but exact words help too
              └──────┬──────┘
                     │
                     ▼  then two more tricks:
              ┌─────────────┐
              │ MMR filter  │  ◄── "don't repeat yourself"
              │ (diversity) │      picks DIFFERENT chunks,
              └──────┬──────┘      not 5 copies of same thing
                     │
                     ▼
              ┌─────────────┐
              │ Time decay   │  ◄── newer memories rank higher
              │ (30-day      │      old stuff fades (but never
              │  half-life)  │      fully disappears)
              └──────┬──────┘
                     │
                     ▼
              Top 6 results (if score > 0.35)
              injected into Gregor's context
```

## The Whole Flow (End to End)

```
   You on Telegram: "What did Marius tell you about privacy?"
        │
        ▼
   ┌─────────────────────────────────────────────────┐
   │                 OpenClaw Gateway                  │
   │                                                   │
   │  1. Receive message from Telegram                 │
   │  2. Search memory ──► main.sqlite ──► 3 matches  │
   │  3. Build prompt:                                 │
   │     ┌───────────────────────────────────────────┐│
   │     │ System: "You are Gregor..."               ││
   │     │ Memory: [chunk about privacy directives]  ││  ◄── injected!
   │     │ Memory: [chunk about Marius identity]     ││
   │     │ Memory: [chunk about key rules]           ││
   │     │ User: "What did Marius tell you..."       ││
   │     └───────────────────────────────────────────┘│
   │  4. Send to Claude Opus ──► get answer           │
   │  5. Reply on Telegram                             │
   └───────────────────────────────────────────────────┘
```

## TL;DR (Truly ELI5)

```
  📝 You write notes in files
       ↓
  🔪 Files get chopped into small pieces
       ↓
  🧠 Tiny local AI turns each piece into a "meaning fingerprint"
       ↓
  💾 Fingerprints stored in a database
       ↓
  🔍 When Gregor gets a question, he finds pieces
     with the most similar meaning fingerprint
       ↓
  💬 Those pieces get stuffed into the prompt
     so Claude can answer with Gregor's memories
```

**What makes it special:** The fingerprints (embeddings) are made *locally* on the VPS by a tiny 329MB model. No text ever leaves the machine for memory search. Fully private.

## Technical Specs

| Component | Detail |
|-----------|--------|
| Database | `~/.openclaw/memory/main.sqlite` (SQLite + sqlite-vec) |
| Embedding model | `embeddinggemma-300m` (329MB GGUF, local via node-llama-cpp) |
| Vector dimensions | 768 |
| Chunk size | 400 tokens, 80 token overlap |
| Search type | Hybrid (70% vector + 30% FTS) |
| Reranking | MMR (lambda 0.7) for diversity |
| Recency boost | Temporal decay with 30-day half-life |
| Min score | 0.35 (below = filtered out) |
| Max results | 6 per query |
| Source files | `~/.openclaw/workspace/memory/*.md` |
