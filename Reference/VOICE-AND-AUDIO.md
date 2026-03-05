# Voice & Audio — Reference

Deep research on speech-to-text (STT) for OpenClaw and Telegram bots. Covers OpenClaw's built-in audio pipeline, cloud and self-hosted STT providers, Telegram Bot API voice handling, and architecture patterns.

**Research date:** 2026-03-05
**Research scope:** 9 parallel research agents across Claude, Gemini, and Grok

---

## Table of Contents

1. [OpenClaw Native Audio Pipeline](#1-openclaw-native-audio-pipeline)
2. [Cloud STT Provider Comparison](#2-cloud-stt-provider-comparison)
3. [Self-Hosted STT Options](#3-self-hosted-stt-options)
4. [Telegram Bot API Voice Handling](#4-telegram-bot-api-voice-handling)
5. [Architecture Patterns](#5-architecture-patterns)
6. [Framework Landscape](#6-framework-landscape)
7. [Decision Matrix](#7-decision-matrix)

---

## 1. OpenClaw Native Audio Pipeline

OpenClaw has built-in voice transcription via `tools.media.audio`. No custom code, no middleware, no Whisper server required.

### How It Works

1. Voice message arrives from Telegram (OGG/Opus format, `.oga` extension)
2. OpenClaw downloads the audio file (respects `maxBytes` cap, default 20 MB)
3. Files under 1024 bytes are skipped
4. First eligible STT model in the configured chain is called
5. On failure, falls through to the next model
6. On success: message body is replaced with `[Audio]` block, `{{Transcript}}` variable is set
7. Slash commands and @mentions work inside voice notes
8. Optional `echoTranscript` sends the text back to the user

### Auto-Detection Order (When No Models Configured)

1. Local CLIs: `sherpa-onnx-offline` → `whisper-cli` → `whisper` (Python)
2. Gemini CLI via `read_many_files`
3. Provider keys: OpenAI → Groq → Deepgram → Google

### Configuration

```json
{
  "tools": {
    "media": {
      "audio": {
        "enabled": true,
        "maxBytes": 20971520,
        "echoTranscript": true,
        "echoFormat": "[Transcript]: \"{transcript}\"",
        "models": [
          { "provider": "groq", "model": "whisper-large-v3" },
          { "provider": "openai", "model": "gpt-4o-mini-transcribe" }
        ]
      }
    }
  }
}
```

### CLI Fallback Configuration

For zero-cost offline transcription as a fallback:

```json
{
  "type": "cli",
  "command": "whisper-cli",
  "args": ["--model", "base", "{{MediaPath}}"],
  "timeoutSeconds": 45
}
```

### Group Mention Detection

When `requireMention: true`, voice notes get "preflight" transcription — the transcript is scanned for `@BotName` patterns before processing. Disable per-group:

```json
{
  "channels": {
    "telegram": {
      "groups": {
        "<chatId>": {
          "disableAudioPreflight": true
        }
      }
    }
  }
}
```

### Known Issues

- GitHub issues [#22554](https://github.com/openclaw/openclaw/issues/22554), [#17101](https://github.com/openclaw/openclaw/issues/17101): Telegram voice not auto-transcribed. Fix: set `tools.media.audio.enabled: true` explicitly and configure at least one provider model. The auto-detection path has been buggy — explicit config is more reliable.
- Discussion [#6062](https://github.com/openclaw/openclaw/discussions/6062): Latency complaints on audio notes.
- Feature request [#14374](https://github.com/openclaw/openclaw/issues/14374): Auto-transcription requested and shipped — closed as duplicate of #11066 (core functionality).

---

## 2. Cloud STT Provider Comparison

### Pricing Table

| Provider | Model | Cost/min | Cost/hr | Free Tier | OGG/Opus Support |
|----------|-------|----------|---------|-----------|-----------------|
| **Groq** | whisper-large-v3-turbo | **$0.0007** | $0.04 | Free tier available | Yes |
| **Groq** | distil-whisper-large-v3-en | $0.0003 | $0.02 | Same | Yes (English only) |
| **OpenAI** | gpt-4o-mini-transcribe | $0.003 | $0.18 | None | Yes |
| **OpenAI** | whisper-1 / gpt-4o-transcribe | $0.006 | $0.36 | None | Yes |
| **Deepgram** | nova-3 (pre-recorded) | $0.0043 | $0.26 | **$200 credit** (~4 years at low volume) | Yes |
| **AssemblyAI** | universal | $0.0025 | $0.15 | $50 credit | **No** — needs ffmpeg conversion |
| **ElevenLabs** | scribe_v1 | $0.007 | $0.40 | Limited | Yes |
| **Google Cloud** | chirp-2 | $0.016 | $0.96 | 60 min/mo free | Yes |
| **Azure** | standard real-time | $0.0167 | $1.00 | 5 hrs/mo free | Partial |
| **Amazon** | transcribe standard | $0.024 | $1.44 | 60 min/mo (12 months) | Yes |

### Monthly Cost Estimate (30 msgs/day × 30 seconds each = ~450 min/month)

| Provider | Monthly Cost | Notes |
|----------|-------------|-------|
| **Groq** (whisper-large-v3-turbo) | **$0.32** | Cheapest. Free tier may cover it entirely |
| OpenAI (gpt-4o-mini-transcribe) | $1.35 | Best simplicity if you already have the SDK |
| Deepgram (nova-3) | $1.94 | $200 free credit covers ~4 years |
| AssemblyAI (universal) | $1.13 | Cheapest per-minute, but needs format conversion |
| Google Cloud (chirp-2) | $7.20 | Overkill for personal use |

### Accuracy (Word Error Rate)

| Provider / Model | Clean Audio WER | Notes |
|-----------------|-----------------|-------|
| OpenAI gpt-4o-transcribe | ~8.9% | Best in independent benchmarks |
| OpenAI gpt-4o-mini-transcribe | ~13.2% | Good enough for voice messages |
| Deepgram nova-3 | <10% | Strong on English, especially noisy audio |
| Groq whisper-large-v3-turbo | ~8-10% | Same Whisper model, just faster inference |
| Google chirp-3 | ~10-12% | Good multilingual |

### Latency (30-second pre-recorded clip)

| Provider | Typical Latency | Notes |
|----------|----------------|-------|
| **Deepgram** | <1 second | Fastest available |
| **Groq** | <1 second | 216x realtime speed |
| OpenAI | 1-3 seconds | Solid |
| AssemblyAI | 2-5 seconds | Async polling model adds overhead |
| Google Cloud | 2-5 seconds | Depends on model |

### Recommendation

**For OpenClaw/Gregor:** Groq (cheapest, fastest, free tier, OGG-native). Fallback to OpenAI if you already have that key configured.

**For free-tier optimization:** Deepgram's $200 credit lasts ~4 years at personal-bot volume.

---

## 3. Self-Hosted STT Options

### Engine Comparison

| Engine | Architecture | RAM (base model) | 30s Audio (CPU) | English WER | Languages |
|--------|-------------|-----------------|-----------------|-------------|-----------|
| **whisper.cpp** | C/C++ (ggml) | ~400-500 MB | 3-7s | ~5% | 99 |
| **faster-whisper** | CTranslate2 (Python) | ~700 MB (INT8) | 2-4s | ~5% | 99 |
| **Vosk** | Kaldi-based | ~200 MB | 1-2s | ~12% | 20+ |
| **Moonshine** | ONNX encoder-decoder | ~200 MB | <1s | ~12% | English only |

### Model Sizes and RAM (whisper.cpp)

| Model | Parameters | Disk (GGML) | Runtime RAM | WER (English) | Fits 4GB VPS? |
|-------|-----------|-------------|-------------|---------------|---------------|
| tiny | 39M | 75 MB | ~273 MB | ~7.6% | Yes |
| base | 74M | 142 MB | ~388 MB | ~5.0% | Yes |
| small | 244M | 466 MB | ~852 MB | ~3.4% | Marginal |
| medium | 769M | 1.5 GB | ~2.1 GB | ~2.9% | No (with other services) |
| large-v3 | 1.55B | 2.9 GB | ~3.9 GB | ~2.4% | No |

Quantized variants (Q8_0, Q4_0) reduce size by 45-68% with <2% accuracy loss.

### whisper.cpp HTTP Server

whisper.cpp includes a built-in HTTP server with an OpenAI-compatible API:

```bash
# Start as a sidecar service
./whisper-server -m models/ggml-base.en.bin \
  --host 127.0.0.1 --port 8080 \
  --convert \
  -t 4

# Call from any HTTP client
curl http://127.0.0.1:8080/inference \
  -F file=@voice.wav \
  -F response_format=json
```

Supports OpenAI-compatible endpoint via `--inference-path "/v1/audio/transcriptions"` — can use the OpenAI SDK pointed at localhost.

### Honest Assessment: Self-Hosted Gotchas

**Hallucinations:** A peer-reviewed ACM study ("Careless Whisper") found 1.4% of transcriptions contain fabricated content. 40% of those fabrications were harmful. Trigger: silence/pauses — exactly the pattern in short voice messages. Cloud providers (OpenAI API) retranscribe when hallucination is detected; self-hosted models don't.

**Memory leaks in faster-whisper:** Multiple open GitHub issues ([#390](https://github.com/SYSTRAN/faster-whisper/issues/390), [#660](https://github.com/SYSTRAN/faster-whisper/issues/660), [#1055](https://github.com/SYSTRAN/faster-whisper/issues/1055)). PyAV decoder objects not garbage-collected. Production services get OOM-killed every few hours. Requires watchdog restarts.

**Cold start:** Model loading takes 80ms (tiny) to 10s (large-v3). First transcription after cold start significantly slower — Home Assistant users report 20-23 seconds.

**Accuracy degradation:** Real-world WER is far worse than benchmarks:
- Female speakers: accuracy drops to ~80% vs 90%+ for males
- Children's speech: ~60% errors
- Background noise: 15-25% WER
- Non-native accents: highly variable

**Cost reality:** At personal-bot volume (10-50 msgs/day), cloud API costs ~$0.30-1.35/month. Self-hosting engineering time alone exceeds years of API costs. Breakeven is ~2,400 hours/month of transcription.

### When Self-Hosted Makes Sense

- 500+ hours/month transcription (business scale)
- Strict regulatory on-premise requirement
- Air-gapped / offline environment
- You enjoy the engineering challenge

### When It Doesn't

- Personal voice messages (minutes/day) — cloud API wins on every axis
- Budget VPS already running other services — memory pressure risk
- You value engineering time above $0/hour

---

## 4. Telegram Bot API Voice Handling

### Voice Message Format

Telegram sends voice messages as OGG container with Opus codec (`.oga` extension, `audio/ogg` MIME type, 48 kHz).

### Bot API Voice Object

| Field | Type | Description |
|-------|------|-------------|
| `file_id` | String | Identifier for downloading (bot-specific, reusable) |
| `file_unique_id` | String | Unique across bots (cannot be used to download) |
| `duration` | Integer | Audio length in seconds |
| `mime_type` | String | Typically `audio/ogg` |
| `file_size` | Integer | Size in bytes |

### Download Flow

```
1. Receive message.voice.file_id
2. Call getFile(file_id) → returns { file_id, file_size, file_path }
3. URL: https://api.telegram.org/file/bot<TOKEN>/<file_path>
4. GET → raw OGG/Opus binary
```

**Constraints:**
- Download URL valid for **60 minutes** only
- Max file size: **20 MB** (standard Bot API)
- `file_id` is reusable indefinitely, `file_path` URL expires — cache `file_id`, not the URL

### Telegram Premium Transcription — NOT Available to Bots

`messages.transcribeAudio` is **MTProto-only**, not exposed in the HTTP Bot API. Bots cannot access Telegram's native transcription. There is no `transcript` field on the Bot API `Voice` object.

---

## 5. Architecture Patterns

### Pattern A: OpenClaw Native (Recommended)

```
User sends voice → OpenClaw downloads OGG → Calls configured STT provider
→ Replaces message body with transcript → Processes as normal text
```

Zero code. Config-only.

### Pattern B: Custom Bot Pipeline

For custom Telegram bots (grammY, Telegraf, node-telegram-bot-api):

```
User sends voice → Bot receives file_id → Download OGG buffer
→ Send to STT API (OGG accepted natively by Groq/OpenAI/Deepgram)
→ Feed transcript text to LLM → Reply
```

**Key insight:** Modern STT APIs accept OGG/Opus directly — no ffmpeg conversion needed.

**grammY example (TypeScript):**
```typescript
import { Bot, Context } from "grammy";
import { FileFlavor, hydrateFiles } from "@grammyjs/files";
import OpenAI, { toFile } from "openai";

type MyContext = FileFlavor<Context>;
const bot = new Bot<MyContext>(process.env.BOT_TOKEN!);
const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

bot.api.config.use(hydrateFiles(bot.token));

bot.on("message:voice", async (ctx) => {
  const file = await ctx.getFile();
  const url = file.getUrl();
  const response = await fetch(url);
  const buffer = Buffer.from(await response.arrayBuffer());

  const transcription = await openai.audio.transcriptions.create({
    file: await toFile(buffer, "voice.ogg", { contentType: "audio/ogg" }),
    model: "whisper-1",
  });

  await ctx.reply(transcription.text, {
    reply_parameters: { message_id: ctx.msg.message_id },
  });
});
```

### Pattern C: whisper.cpp Sidecar

For self-hosted, deploy whisper.cpp HTTP server as a systemd service:

```bash
# systemd unit pointing to whisper.cpp server
./whisper-server -m ggml-base.en.bin --host 127.0.0.1 --port 8080 --convert -t 4
```

Then call from any HTTP client — OpenAI SDK works if you set `baseURL` to localhost.

### Audio Format Conversion (When Required)

Most modern APIs don't need this. But for services requiring WAV:

```bash
ffmpeg -i voice.oga -ar 16000 -ac 1 -c:a pcm_s16le voice.wav -y
```

Node.js via `fluent-ffmpeg`:
```typescript
import ffmpeg from "fluent-ffmpeg";

ffmpeg(inputPath)
  .audioCodec("pcm_s16le")
  .audioFrequency(16000)
  .audioChannels(1)
  .output(outputPath)
  .run();
```

### Queue Pattern (For Concurrent Voice Messages)

If multiple voice messages arrive simultaneously, use BullMQ (Redis-backed, Bun-compatible):

```typescript
import { Queue, Worker } from "bullmq";

const queue = new Queue("voice-transcription", { connection });

// Producer: enqueue from voice handler
await queue.add("transcribe", { fileId, chatId, messageId });

// Worker: process sequentially
const worker = new Worker("voice-transcription", async (job) => {
  const audioBuffer = await downloadTelegramVoice(job.data.fileId);
  const transcript = await transcribe(audioBuffer);
  await sendResponse(job.data.chatId, transcript);
}, { connection, concurrency: 2 });
```

---

## 6. Framework Landscape

### General-Purpose Bot Frameworks

| Framework | Native STT | Native TTS | Streaming Voice | Notes |
|-----------|-----------|-----------|----------------|-------|
| **OpenClaw** | Yes | Yes | Yes (Discord, Realtime API) | Most complete. Config-driven, auto-detects providers |
| **Rasa** | Yes | Yes | Yes (Genesys, AudioCodes) | Enterprise telephony focus. Requires Rasa Pro |
| **LangChain** | No | No | No | "Sandwich" pattern — wire external providers yourself |
| **Botpress** | No | No | No | Text-only. Feature requests still open |
| **AutoGPT** | No | No | No | Third-party wrappers only |

### Voice-First Frameworks (Purpose-Built)

| Framework | Architecture | Best For |
|-----------|-------------|----------|
| **Pipecat** | Python pipeline | Richest STT/TTS service integrations |
| **LiveKit Agents** | WebRTC rooms | Cleanest API, fastest zero-to-working |
| **TEN Framework** | Graph-based | Most flexible, multi-language |

### Telegram Bot STT Ecosystem

No dedicated grammY or Telegraf STT plugin exists. The pattern is: voice event listener + file download (`@grammyjs/files`) + external STT SDK. The TypeScript Telegram STT space is underserved — Python dominates.

### NPM Packages for Whisper Integration

| Package | Approach | Notes |
|---------|----------|-------|
| `nodejs-whisper` | child_process → whisper.cpp | Auto-converts to WAV, broadest model support |
| `smart-whisper` | Native N-API addon | Model persists in memory, fastest for production |
| `whisper-node` | child_process → whisper.cpp | Simplest API surface |
| `node-whisper` | Wraps whisper CLI | TypeScript-first, zero dependencies |

### Emerging: Native Multimodal Audio in LLMs

Models that accept audio input directly, bypassing STT entirely:
- **OpenAI gpt-4o-audio-preview** — native audio understanding
- **Google Gemini 2.5** — audio tokens at 25 tokens/second
- **Alibaba Qwen2.5-Omni** — separates reasoning (Thinker) from speaking (Talker)

Via OpenRouter, send base64-encoded audio as `input_audio` type in the content array. This skips STT but costs more (LLM response tokens >> STT API costs).

---

## 7. Decision Matrix

### For OpenClaw/Gregor (Your Setup)

| Approach | Complexity | Monthly Cost | Recommended? |
|----------|-----------|-------------|-------------|
| **OpenClaw native + Groq** | **Zero** (config only) | ~$0.30 | **Yes — start here** |
| OpenClaw native + OpenAI | Zero | ~$1.35 | Solid fallback |
| whisper.cpp sidecar on VPS | Medium | $0 (CPU cost) | Only if offline matters |
| Custom bot code | High | Varies | Only for non-OpenClaw bots |

### For Non-OpenClaw Agents

| Use Case | Best Approach |
|----------|--------------|
| Custom Telegram bot (TypeScript) | grammY + `@grammyjs/files` + Groq SDK |
| Custom Telegram bot (Python) | aiogram/python-telegram-bot + faster-whisper |
| Enterprise voice agent | Rasa Pro or Pipecat |
| Offline/air-gapped | whisper.cpp with base.en Q8_0 |

---

## Sources

### OpenClaw Native
- [OpenClaw Audio & Voice Notes docs](https://docs.openclaw.ai/nodes/audio)
- [OpenClaw TTS docs](https://docs.openclaw.ai/tts)
- [LumaDock: Add voice to OpenClaw](https://lumadock.com/tutorials/openclaw-voice-tts-stt-talk-mode)
- [OpenClaw and Voice AI (Medium)](https://medium.com/@ggarciabernardo/openclaw-and-voice-ai-ee3ce4fffcea)

### Cloud STT Providers
- [Groq Speech-to-Text docs](https://console.groq.com/docs/speech-to-text)
- [OpenAI Speech-to-Text](https://platform.openai.com/docs/guides/speech-to-text)
- [Deepgram Pricing](https://deepgram.com/pricing)
- [AssemblyAI Pricing](https://www.assemblyai.com/pricing)
- [Google Cloud Speech-to-Text Pricing](https://cloud.google.com/speech-to-text/pricing)
- [Azure Speech Services Pricing](https://azure.microsoft.com/en-us/pricing/details/cognitive-services/speech-services/)

### Self-Hosted STT
- [whisper.cpp (GitHub)](https://github.com/ggml-org/whisper.cpp)
- [faster-whisper (GitHub)](https://github.com/SYSTRAN/faster-whisper)
- [Vosk (alphacephei)](https://alphacephei.com/vosk/)
- [Moonshine (GitHub)](https://github.com/moonshine-ai/moonshine)
- [Careless Whisper: Hallucination Study (ACM)](https://dl.acm.org/doi/fullHtml/10.1145/3630106.3658996)
- [Whisper Quantization Analysis (arXiv 2503.09905)](https://arxiv.org/html/2503.09905v1)

### Telegram Bot API
- [Telegram Bot API — Voice Object](https://core.telegram.org/bots/api)
- [Telegram Voice Transcription (MTProto)](https://core.telegram.org/api/transcribe)
- [grammY Files Plugin](https://grammy.dev/plugins/files)

### Architecture & Benchmarks
- [Best Open Source STT 2026 (Northflank)](https://northflank.com/blog/best-open-source-speech-to-text-stt-model-in-2026-benchmarks)
- [Choosing Whisper Variants (Modal)](https://modal.com/blog/choosing-whisper-variants)
- [STT API Benchmarks & Pricing](https://futureagi.substack.com/p/speech-to-text-apis-in-2026-benchmarks)
- [Realtime AI Agent Frameworks Comparison](https://medium.com/@ggarciabernardo/realtime-ai-agents-frameworks-bb466ccb2a09)
