# Vendor Setup

This guide explains how to wire each upstream vendor through the local Bifrost
gateway in this repository.

## Concepts

Bifrost has two separate credential layers:

- Provider credentials: real upstream keys such as `OPENAI_API_KEY` or
  `ANTHROPIC_API_KEY`. Bifrost uses these to call the vendor.
- Virtual Key: the local governance key, `BIFROST_VK_PERSONAL`. Clients send
  this key to Bifrost so Bifrost can enforce budgets and rate limits.

Do not put provider API keys in client apps. Clients should talk to Bifrost and
send the Virtual Key.

## Common Setup

Create `.env` from the template:

```bash
cp .env.example .env
```

Set these values:

```dotenv
BIFROST_ENCRYPTION_KEY=...
BIFROST_VK_PERSONAL=sk-bf-...
```

Start Bifrost:

```bash
nix run .#bifrost-host
```

The default local base URLs are:

```text
OpenAI-compatible:  http://127.0.0.1:18080/v1
Bifrost OpenAI:    http://127.0.0.1:18080/openai/v1
Anthropic:         http://127.0.0.1:18080/anthropic
UI/API:            http://127.0.0.1:18080
```

Check the active hard budget:

```bash
curl -fsS http://127.0.0.1:18080/api/governance/budgets \
  | jq '.budgets[] | select(.id == "budget-personal-daily-hard")'
```

## OpenAI API

Use this when Bifrost should call OpenAI with an OpenAI API key.

In `.env`:

```dotenv
OPENAI_API_KEY=sk-...
```

`bifrost/config.json` already contains the `openai` provider. After editing
`.env`, restart Bifrost.

Test with the OpenAI-compatible route:

```bash
source .env

curl -fsS http://127.0.0.1:18080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "x-bf-vk: $BIFROST_VK_PERSONAL" \
  -d '{
    "model": "openai/gpt-4o-mini",
    "messages": [{"role": "user", "content": "Reply with ok"}]
  }'
```

OpenAI SDK-style clients can use:

```text
base_url: http://127.0.0.1:18080/v1
api_key:  $BIFROST_VK_PERSONAL
model:    openai/<model>
```

## Anthropic API Key

Use this when Bifrost should call Anthropic with an Anthropic API key. This is
different from Claude Code subscription auth.

In `.env`:

```dotenv
ANTHROPIC_API_KEY=sk-ant-...
```

`bifrost/config.json` already contains the `anthropic` provider. After editing
`.env`, restart Bifrost.

Test through the Anthropic-compatible route:

```bash
source .env

ANTHROPIC_BASE_URL=http://127.0.0.1:18080/anthropic \
ANTHROPIC_AUTH_TOKEN="$BIFROST_VK_PERSONAL" \
claude -p --model sonnet "Reply with exactly: anthropic-api-ok"
```

Use this mode only when `ANTHROPIC_AUTH_TOKEN` is the Bifrost Virtual Key. Do
not use this mode for Claude Code Max/Enterprise subscription auth.

## Claude Code Max or Enterprise Subscription

Use this when Claude Code is already logged in with account/OAuth auth and you
want Bifrost to enforce the Virtual Key budget. Bifrost receives the Virtual Key
through `x-bf-vk`; Claude Code keeps its own OAuth bearer token for the upstream
Anthropic call.

The kinko/direnv secret for this repository should expose:

```text
CLAUDE_CODE_OAUTH_TOKEN
BIFROST_VK_PERSONAL
```

It should not expose `ANTHROPIC_AUTH_TOKEN` for this mode.

Run:

```bash
direnv exec . sh -c '
  unset ANTHROPIC_AUTH_TOKEN
  unset ANTHROPIC_API_KEY
  ANTHROPIC_BASE_URL=http://127.0.0.1:18080/anthropic \
  ANTHROPIC_CUSTOM_HEADERS="x-bf-vk: $BIFROST_VK_PERSONAL" \
  claude -p --model sonnet "Reply with exactly: bifrost-ok"
'
```

Expected output:

```text
bifrost-ok
```

To pin Claude Code to models on other configured providers, set Claude Code's
model variables to provider-prefixed names, for example:

```bash
ANTHROPIC_DEFAULT_SONNET_MODEL="openai/gpt-4o-mini"
ANTHROPIC_DEFAULT_HAIKU_MODEL="openai/gpt-4o-mini"
```

The target model must support the tool use required by your Claude Code
workflow.

## Gemini API

Add a Gemini provider when Bifrost should call Google Gemini directly with a
Gemini API key.

In `.env`:

```dotenv
GEMINI_API_KEY=...
```

Add this provider block under `providers` in `bifrost/config.json`:

```json
"gemini": {
  "keys": [
    {
      "name": "gemini-primary",
      "value": "env.GEMINI_API_KEY",
      "models": ["*"],
      "weight": 1.0
    }
  ]
}
```

Add a matching `provider_configs` entry to the Virtual Key:

```json
{
  "id": 3,
  "provider": "gemini",
  "allowed_models": ["*"],
  "key_ids": ["*"],
  "weight": 1.0
}
```

Then restart Bifrost and call a Gemini model through the OpenAI-compatible
route:

```bash
source .env

curl -fsS http://127.0.0.1:18080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "x-bf-vk: $BIFROST_VK_PERSONAL" \
  -d '{
    "model": "gemini/gemini-2.5-pro",
    "messages": [{"role": "user", "content": "Reply with ok"}]
  }'
```

## AWS Bedrock

Use Bedrock when AWS is the upstream vendor. The exact credential source depends
on your AWS environment, but the Bifrost provider name is `bedrock`.

For inherited AWS credentials or IAM role auth, set normal AWS environment
variables outside `config.json`:

```dotenv
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_SESSION_TOKEN=...
AWS_REGION=us-east-1
```

Then add the provider block under `providers`. Leave `value` empty when Bifrost
should use the AWS default credential chain:

```json
"bedrock": {
  "keys": [
    {
      "name": "bedrock-primary",
      "value": "",
      "models": ["*"],
      "weight": 1.0,
      "bedrock_key_config": {
        "region": "us-east-1"
      }
    }
  ]
}
```

Add a matching `provider_configs` entry to the Virtual Key:

```json
{
  "id": 4,
  "provider": "bedrock",
  "allowed_models": ["*"],
  "key_ids": ["*"],
  "weight": 1.0
}
```

Model names are provider-prefixed, for example:

```text
bedrock/global.anthropic.claude-sonnet-4-5
bedrock/anthropic.claude-3-5-sonnet-20241022-v2:0
```

For Claude Code, pin the model:

```bash
ANTHROPIC_DEFAULT_SONNET_MODEL="bedrock/global.anthropic.claude-sonnet-4-5"
```

## Google Vertex AI

Use Vertex when Google Cloud is the upstream vendor. The Bifrost provider name
is `vertex`.

For Application Default Credentials, set:

```dotenv
VERTEX_PROJECT_ID=your-project-id
GOOGLE_APPLICATION_CREDENTIALS=/absolute/path/to/service-account.json
```

Then add the provider block under `providers`. Leave `value` empty when Bifrost
should use Google Application Default Credentials:

```json
"vertex": {
  "keys": [
    {
      "name": "vertex-primary",
      "value": "",
      "models": ["*"],
      "weight": 1.0,
      "vertex_key_config": {
        "project_id": "env.VERTEX_PROJECT_ID",
        "region": "us-central1",
        "auth_credentials": ""
      }
    }
  ]
}
```

For service account JSON stored directly in a secret manager or kinko-exported
environment variable, use `auth_credentials: "env.VERTEX_CREDENTIALS"` instead.

Add a matching `provider_configs` entry to the Virtual Key:

```json
{
  "id": 5,
  "provider": "vertex",
  "allowed_models": ["*"],
  "key_ids": ["*"],
  "weight": 1.0
}
```

Model names are provider-prefixed, for example:

```text
vertex/gemini-2.5-pro
vertex/claude-sonnet-4-5
```

For Claude Code, pin the model:

```bash
ANTHROPIC_DEFAULT_SONNET_MODEL="vertex/claude-sonnet-4-5"
```

## OpenRouter and Other OpenAI-Compatible Vendors

Bifrost supports many providers using the `provider/model-name` pattern. For
OpenRouter, add:

```dotenv
OPENROUTER_API_KEY=sk-or-...
```

```json
"openrouter": {
  "keys": [
    {
      "name": "openrouter-primary",
      "value": "env.OPENROUTER_API_KEY",
      "models": ["*"],
      "weight": 1.0
    }
  ]
}
```

Add the provider to the Virtual Key:

```json
{
  "id": 6,
  "provider": "openrouter",
  "allowed_models": ["*"],
  "key_ids": ["*"],
  "weight": 1.0
}
```

Then call models as:

```text
openrouter/<model-name>
```

The same shape applies to other supported Bifrost providers such as `mistral`,
`groq`, `cerebras`, `cohere`, `perplexity`, `xai`, `ollama`, `huggingface`,
`nebius`, `parasail`, `replicate`, `vllm`, and `sgl`.

## Budgets in bifrost-gage

`bifrost-gage` treats the selected Bifrost Virtual Key as the budget scope. The
menu edits Virtual Key level budgets and does not expose provider-specific
budget controls. Use separate Virtual Keys when you want separate Codex, Claude,
or other client budgets.

## References

- Bifrost provider configuration:
  https://docs.getbifrost.ai/quickstart/gateway/provider-configuration
- Bifrost Claude Code setup:
  https://docs.getbifrost.ai/cli-agents/claude-code
- Bifrost supported provider/model format:
  https://docs.getbifrost.ai/cli-agents/cursor
- Bifrost Bedrock provider setup:
  https://docs.getbifrost.ai/providers/supported-providers/bedrock
- Bifrost Vertex provider setup:
  https://docs.getbifrost.ai/providers/supported-providers/vertex
