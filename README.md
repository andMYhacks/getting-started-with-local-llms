# Getting Started with Local LLMs

A collection of guides, configs, and examples for running large language models on your own hardware — from building a secure, headless GPU server to serving models with vLLM and Ollama and reaching them privately over Tailscale.

> **Status:** Work in progress. Guides and examples are added as the setup evolves.

---

## Why run LLMs locally?

- **Privacy** — prompts, code, and data never leave hardware you control.
- **Cost** — no per-token billing once the hardware is in place.
- **Control** — choose your models, quantization, context length, and sampling settings.
- **Availability** — keep working without depending on a third-party API.
- **Guardrails** — Circumvent refusals and other mechanisms that reduce a model's capabilities.

---

## What's in this repo

| Path | Description |
|---|---|
| [`linux-dev-server-setup.md`](./linux-dev-server-setup.md) | End-to-end guide to building a headless Ubuntu Server 24.04 LTS box for remote development, security research, and local LLM inference. |
| [`vllm-examples/`](./vllm-examples) | Example configurations and launch scripts for serving models with [vLLM](https://github.com/vllm-project/vllm). |
| [`models.yaml`](./models.yaml) | Example client-side provider config that registers several OpenAI-compatible endpoints (vLLM and Ollama) and the models each one serves. |
| [`tailscale-acls.json`](./tailscale-acls.json) | Example Tailscale ACL policy that lets your laptop and dev box reach inference servers on only the ports they need. |
| [`LICENSE`](./LICENSE) | MIT License. |

---

## Architecture at a glance

```
┌──────────────┐        Tailscale (tailnet)        ┌────────────────────────┐
│   Laptop     │ ────────────────────────────────▶ │  Inference server(s)   │
│ tag:laptop   │   SSH, :8000 (vLLM), :11434       │  tag:inference         │
└──────┬───────┘          (Ollama), :443           │  vLLM / Ollama + GPU   │
       │                                           └───────────▲────────────┘
       │  all ports                                            │ :443 / :8000 / :11434 only
       ▼                                                       │
┌──────────────┐                                               │
│   Dev box    │ ──────────────────────────────────────────────┘
│   tag:dev    │   (no SSH to inference servers)
└──────────────┘
```

Every model server exposes an **OpenAI-compatible API** (`/v1`), so any client that speaks the OpenAI protocol can use them by changing the base URL.

---

## Quick start

### 1. Build the server

Follow [`linux-dev-server-setup.md`](./linux-dev-server-setup.md). It covers:

1. **Choosing a distro** — why Ubuntu Server 24.04 LTS (NVIDIA/CUDA support, long-term security updates).
2. **Writing the install image** on macOS with `diskutil` and `dd`.
3. **Partitioning and encryption** — LUKS2 full-disk encryption over LVM, with a dedicated `/data` partition for model weights.
4. **Secrets management** with the 1Password CLI (`op`) and a service account.
5. **Joining Tailscale** with a pre-approved, tagged auth key.
6. **SSH hardening and remote unlock** — key-only auth, plus Dropbear and `tailscale-initramfs` so you can run `cryptroot-unlock` over Tailscale after a reboot.
7. **Drivers and tooling** — NVIDIA driver 580, `uv`/`pipx`, vLLM, Ollama, the Hugging Face CLI, Colima, and Neovim/LazyVim.

Reference hardware used in the guide: 64 GB RAM, 6 TB storage, NVIDIA RTX 3080 Ti, with a MacBook Air as the client.

### 2. Serve a model

**Ollama** (simplest):

```bash
ollama pull <model>
ollama serve            # listens on :11434, OpenAI-compatible API at /v1
```

**vLLM** (higher throughput, more tuning options):

```bash
uv pip install vllm --torch-backend auto
vllm serve <hf-org>/<model> --port 8000
```

See [`vllm-examples/`](./vllm-examples) for ready-made configurations.

> ⚠️ Ollama has **no built-in authentication**. Don't expose it to the public internet — keep it on localhost or behind Tailscale.

### 3. Lock down the network

1. Open the [Tailscale admin console](https://login.tailscale.com/admin/acls) → **Access controls**.
2. Paste in [`tailscale-acls.json`](./tailscale-acls.json) and replace `you_username@github` with your own login.
3. Tag your machines: `tag:inference` (model servers), `tag:dev` (dev box), `tag:laptop` (your laptop).

The policy:

- lets your admin user and laptop reach inference and dev machines on all ports;
- lets the dev box reach inference servers **only** on `443`, `8000` (vLLM), and `11434` (Ollama), and blocks SSH to them;
- includes `tests` so Tailscale verifies the rules every time you save the policy.

An optional (commented-out) Tailscale SSH block is included for recovery scenarios.

### 4. Point a client at your models

[`models.yaml`](./models.yaml) is an example provider config (written for the `oh-my-pi` client, but the shape maps onto most OpenAI-compatible tools). Each provider defines:

| Field | Purpose |
|---|---|
| `baseUrl` | The server's `/v1` endpoint (Tailscale hostname or `127.0.0.1`). |
| `api` | Protocol — `openai-completions`. |
| `apiKey` | Placeholder value; local servers don't validate it. |
| `contextWindow` / `maxTokens` | Context size and max output tokens. |
| `compat` | Flags for features the server doesn't support (e.g. developer role, reasoning effort). |
| `extraBody` | Extra request parameters such as sampling values or `chat_template_kwargs`. |
| `whenThinking` | Overrides applied when thinking mode is on (e.g. `enable_thinking: true`). |
| `samplingParams` / `samplingParamsByThinkingLevel` | Per-model sampling defaults. |

The example registers models such as Qwen3 Coder (128K context on vLLM), a Qwen reasoning model with thinking toggled per request, and smaller 9B models (Nemotron Nano, Qwen3.5) on Ollama.

Replace the `your-*-box-name.tailnet.ts.net` hostnames with your own machines' MagicDNS names.

Quick sanity check from any machine on your tailnet:

```bash
curl https://<your-box>.<tailnet>.ts.net/v1/models
```

---

## Prerequisites

- A client machine to access your local LLMs from 
    - I use macOS client, and the guide uses macOS commands for image writing and SSH config; adapt as needed.
- A Linux machine with an NVIDIA GPU (the guide uses an RTX 3080 Ti) and plenty of RAM and disk for model weights.
- A USB drive and the [Ubuntu Server 24.04 LTS](https://ubuntu.com/download/server) ISO.
- A [Tailscale](https://tailscale.com/) account. **Note**: these are free for personal use!
- *(Optional)* A [1Password](https://1password.com/) account for secrets and SSH agent forwarding.

---

## Security notes

- Keep `/boot/efi` and `/boot` as the only unencrypted partitions.
- Disable SSH password authentication once key login works.
- Never commit real API keys, Tailscale auth keys, or 1Password service-account tokens (`ops_…`).
- Keep inference ports off the public internet — use Tailscale ACLs to grant the minimum access each device needs.

---

## Contributing

Issues and pull requests are welcome — new guides, hardware notes, model configs, and corrections all help.

## License

Released under the [MIT License](./LICENSE).
