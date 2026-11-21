# What this work cost

**About $153 of model time** at Anthropic API list prices, for everything in
this repo from the first commit (2026-11-16) to P8.8 (2026-11-21). That is
2,188 model responses over two Claude Code sessions, about 18 active hours.
Figures as of 2026-11-21 23:45.

## By session

| Session | Dates | What it produced | Responses | Cost |
|---|---|---|---:|---:|
| 1 | 11-16 21:59 to 11-18 14:11 | P0-P8.7, P9.1, P10: research, Ubuntu 24.04 on the 4.4 kernel, then mainline 7.2.2 with modem, wifi, charging, cameras, audio, GPU; one-command build; licensing (tests 1-54) | 1,885 | $131.35 |
| 2 | 11-21 21:02 to 23:45 | P8.8: hardware H.264/HEVC encoding, 30 fps camera video, firmware crashes no longer reset the phone (tests 56-81) | 303 | $21.36 |
| | | **Total** | **2,188** | **$152.71** |

Session 1 includes $10.61 for 6 subagents: 3 web-research helpers and the
walleye camera device-tree port (Opus 5.5), plus 3 short Haiku 5.5 lookups
($0.03). Session 1 by day:

| Day | Cost |
|---|---:|
| 11-16 (evening) | $8.88 |
| 11-17 | $85.19 |
| 11-18 | $37.28 |

## Where the money goes

Claude Opus 5.5 did the work ($4 / $20 per million input / output tokens).

| Item | Tokens | Price per 1M | Cost | Share |
|---|---:|---:|---:|---:|
| Cache reads | 430,369,074 | $0.20 | $86.06 | 56% |
| Output (replies, tool calls, thinking) | 1,847,491 | $20.00 | $36.48 | 24% |
| Cache writes | 4,079,454 | $8.00 (1 h) / $5.00 (5 min) | $30.16 | 20% |
| Uncached input | 4,448 | $4.00 | $0.02 | 0% |

- **Cache reads dominate.** Every response re-reads the whole conversation so
  far, so a long session costs more per step the longer it runs. Session 1
  averaged about 200k tokens of context per response.
- **The cache makes it affordable.** The same 430M tokens at the full input
  price would be $1,721 instead of $86.

## Session 2 by piece of work

Times are wall-clock and include kernel builds, phone reboots and waiting for
the owner.

| Work | Responses | Cost | Time |
|---|---:|---:|---:|
| 1. Hardware encode bring-up: firmware, DT, patches 0005-0007, `pixel2-camera` (tests 56-72) | 167 | $11.53 | 68 min |
| 2. Bitrate fix: real frame rate in the caps (test 73) | 10 | $0.87 | 3 min |
| 3. 30 fps: AE investigation, libcamera patch 0001 (tests 74-76) | 45 | $3.88 | 13 min |
| 4. Firmware crash no longer resets the phone: fault injection, patch 0008 (tests 77-81) | 54 | $2.88 | 63 min |
| 5. Rebuild the images, push, this report | 27 | $2.20 | 16 min |

## How this was measured

- **Source:** the token counts each response records in the Claude Code
  transcripts, counting each response once:
  - session 1: `~/.claude/projects/-Users-jps-github-ubuntu-touch-pixel2/`
    (the repo lived in `~/github` at first);
  - session 2: `~/.claude/projects/-Volumes-Pixel2Dev-ubuntu-touch-pixel2/`.
- **Prices:** Anthropic API list prices.
  - Opus 5.5: $4 / $20 per million input / output tokens, cache reads $0.20.
  - Haiku 5.5: $0.10 / $0.50, cache reads $0.01.
  - Cache writes cost 1.25x (5 min) or 2x (1 h) the input price.

  Claude Code's own cost tracker came to $20.30 for the part of session 2 it
  covered, matching this calculation.
- **Subscription:** on a Claude subscription these are API-equivalent figures,
  not an amount billed.
- **Not included:**
  - 9 commits from 11-18 17:33-21:58 (cross-building on x86 hosts, ccache, the
    on-phone full build of test 55). They were made in a session with no
    transcript on this Mac.
  - The Pixel 5 sessions, a separate project that only refers to this repo.
  - The owner's time, and electricity for the builds (test 55: 2 h 20 min for
    a full build on the phone).
