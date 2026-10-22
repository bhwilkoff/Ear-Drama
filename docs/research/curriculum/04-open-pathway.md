# An open pathway through the cohort

*Research done October 7, 2026, for the curriculum build-out, and written
by Claude, awaiting Ben's review. Every claim has a source beside it, and
the full list is at the end. Nothing here was installed or run: this Mac
(an Apple M3 with 8 GB of memory) has Antigravity and the Claude app but
no Ollama, LM Studio, or other local model runtime, so every hardware and
quality claim comes from the tools' own documentation or from people who
measured them. Anything that rests on one secondary source is marked
**(one source)**, and anything I could not confirm is marked
**(unverified)**.*

## What I want from this pathway

I want someone who has decided that no AI company they know of is
ethical enough to trust, and who will not hand their work to Anthropic,
OpenAI, Google, Perplexity, or any other large AI service, to still be
able to take the cohort, build a human-shaped app, and earn the same
credential as everyone else. That person should not be treated as an
edge case, because the ethos of the course is theirs too: the template
asks every builder to name who their software serves and who it could
harm, and some people will apply that question to the agent itself.

**The open path is slower and smaller, and it is honest.**

The cost of this choice is real, and I want to say it plainly at the
start: a model running on a laptop is a much less capable partner than
the frontier agents the rest of the cohort uses, and the open path asks
more of the student's own judgment at every step. What follows is what
exists in October 2026, what a novice actually needs, and how each week
of the cohort changes.

## Three kinds of open

"Open" means three different things, and the difference matters for this
pathway because the people choosing it are choosing it on principle.

- **Fully open** means the weights, the training data, the training code,
  and the recipe are all public. The Open Source Initiative's definition
  asks for the code and weights plus "sufficiently detailed information"
  about the data, and the short list of models it validated includes
  AI2's OLMo, EleutherAI's Pythia, and LLM360's Amber and CrystalCoder,
  while Llama 2 and Mixtral did not pass
  ([OSI, OSAID FAQ](https://opensource.org/ai/faq); summarized in
  [Moesif's 2026 guide](https://www.moesif.com/blog/technical/api-development/Open-Source-AI/)).
- **Open weights** means you can download and run the model, but the data
  it learned from is not published, and the license may carry use
  restrictions. Most of the strongest local coding models are this kind
  ([Hugging Face community post, 2026](https://huggingface.co/blog/daya-shankar/open-source-llms)).
- **Who made it** is the third question, and for this pathway it may be
  the first one. An open-weights model from Alibaba or Mistral is still
  made by a large AI company, so a student who is avoiding large AI
  companies should know whose work they are running.

### The models that matter here

| Model | Made by | What kind of open | License | Good for |
|---|---|---|---|---|
| Olmo 3 (7B and 32B; Think, Instruct, Base) | Allen Institute for AI (Ai2), a nonprofit research institute | Fully open: weights, the 9.3-trillion-token Dolma 3 dataset, training code, checkpoints, and logs ([Ai2 blog](https://allenai.org/blog/olmo3); [paper](https://www.alphaxiv.org/abs/2512.13961)) | Open; Ai2 releases "all code, checkpoints, logs" ([Ollama library](https://ollama.com/library/olmo-3)) | Talking through the why, explaining code, small edits. Ollama lists it as text only, without the tools capability ([Ollama library](https://ollama.com/library/olmo-3)) |
| Apertus (8B and 70B; 1.5 since September 17, 2026) | EPFL, ETH Zurich, and the Swiss National Supercomputing Centre, public institutions | Fully open: weights, data preparation scripts, checkpoints, and training code; trained only on public data with opt-outs honored ([ETH press release](https://ethz.ch/en/news-and-events/eth-news/news/2025/09/press-release-apertus-a-fully-open-transparent-multilingual-language-model.html)) | Apache 2.0 ([ETH press release](https://ethz.ch/en/news-and-events/eth-news/news/2025/09/press-release-apertus-a-fully-open-transparent-multilingual-language-model.html)) | Many languages; 1.5 adds "stronger tool use" ([Apertus 1.5 announcement](https://www.apertus-ai.org/articles/2026-09-apertus-1-5-ga/)) |
| SERA (8B to 32B) | Ai2, as its first Open Coding Agents release, January 27, 2026 | Weights, training code, recipes, and synthetic data are open, but it is fine-tuned from Alibaba's Qwen 3 ([Ai2, Open Coding Agents](https://allenai.org/blog/open-coding-agents)) | Open (exact license not stated on the page) **(unverified)** | A coding agent: SERA-32B solves 54.2% of SWE-Bench Verified at 64K context ([Ai2](https://allenai.org/blog/open-coding-agents)) |
| StarCoder2 (3B, 7B, 15B) | BigCode, a community project led with Hugging Face and ServiceNow | Weights, The Stack v2 dataset, and training code are released ([Hugging Face blog](https://huggingface.co/blog/starcoder2)) | BigCode OpenRAIL-M, which adds use restrictions, so it is not an OSI license ([BigCode](https://www.bigcode-project.org/docs/pages/bigcode-openrail/)) | Code completion more than conversation |
| Devstral Small 2 (24B) | Mistral AI, a large AI company | Open weights only | Apache 2.0; the larger Devstral 2 uses a modified MIT license with a revenue limit ([Mistral](https://mistral.ai/news/devstral-2-vibe-cli/)) | Agentic coding on a 32 GB Mac **(one source)** |
| Qwen3-Coder and Qwen3-Coder-Next | Alibaba's Qwen team, a large AI company | Open weights only | Apache 2.0 ([Qwen on GitHub](https://github.com/QwenLM/qwen3)) | The local model most guides recommend for agents; Next needs about 46 GB **(one source)** |

Meta's Llama and Google's Gemma are left out on purpose: Gemma is
Google's, and the OSI analysis did not pass Llama 2's license
([OSI FAQ](https://opensource.org/ai/faq)).

## Running a model on your own computer

A runtime is the program that loads a model and answers it. Almost all
of them are built on the same engine, llama.cpp, so the choice is mostly
about how friendly the program is and what license it carries
([Stribog, 2026](https://stribog.com/blog/lm-studio-ollama-llama-cpp-local-model-runtimes-compared)).

| Runtime | License | Notes |
|---|---|---|
| Ollama | MIT ([Wikipedia](https://en.wikipedia.org/wiki/Ollama)) | The one most agents expect. Its models run on your computer unless you pick one ending in `:cloud`, which runs on Ollama's own servers under a no-retention promise ([Ollama, cloud models](https://ollama.com/blog/cloud-models)). On the open path, a student never picks a `:cloud` model. |
| llama.cpp | MIT ([Wikipedia](https://en.wikipedia.org/wiki/Llama.cpp)) | The engine underneath; a command line, not a friendly app. |
| Jan | Apache 2.0, relicensed from AGPLv3 in May 2025 **(one source)** ([DEV review](https://dev.to/jovan_chan_9500711396d4e6/jan-ai-review-2026-13ei)) | A desktop chat app with an MLX engine for Apple silicon, still marked experimental in 2026. |
| LM Studio | Proprietary, free for personal use ([centron comparison](https://www.centron.de/en/tutorials/ollama-vs-lm-studio-vs-llama-cpp)) | Friendly, but closed source, so it does not fit a student who chose this path for openness. |
| MLX | Apple's array framework for Apple silicon **(license unverified)** | Fast on a Mac; most students meet it inside Jan or LM Studio rather than directly. |

**Ollama is the recommended runtime**, because it is MIT licensed, every
agent below can talk to it, and a student only has to learn one command
to fetch a model.

One warning belongs in the setup lesson itself. Aider's documentation
says Ollama "uses a 2k context window by default" and "silently discards
context that exceeds the window" ([Aider, Ollama](https://aider.chat/docs/llms/ollama.html)),
which means an agent can quietly forget the instructions it was given. Cline's
guide asks for at least 32K ([Ollama, Cline](https://docs.ollama.com/integrations/cline)),
and OpenHands warns that with the default "not even the system prompt
will fit" ([OpenHands, local LLMs](https://docs.openhands.dev/openhands/usage/llms/local-llms)).

## Agents that can drive a local model

| Agent | Who stands behind it | License | Needs tool calling? | Reads `AGENTS.md`? |
|---|---|---|---|---|
| Aider | A community project | Apache 2.0 ([4Geeks listing](https://agents.4geeks.com/agent/aider)) | No: it edits files through plain-text formats, including "whole", where the model returns each file in full ([Aider, edit formats](https://aider.chat/docs/more/edit-formats.html)) | Yes, with `read: AGENTS.md` in `.aider.conf.yml` ([agents.md](https://agents.md/); [awesome-agent-conventions](https://github.com/ItamarZand88/awesome-agent-conventions)) |
| opencode | An open-source project | MIT **(unverified)** | Yes | Yes ([agents.md](https://agents.md/)); finds Ollama on its own, and `ollama launch opencode` configures it ([Zenva](https://academy.zenva.com/opencode-local-llm-ollama/); [aicodinghub](https://aicodinghub.app/opencode-local-models/)) |
| goose | Block gave it to the Linux Foundation's Agentic AI Foundation in December 2025 ([Wikipedia](https://en.wikipedia.org/wiki/Goose_(AI_agent))) | Apache 2.0 | Yes | Yes, `AGENTS.md` first and then `.goosehints` ([goose docs](https://goose-docs.ai/docs/guides/context-engineering/using-goosehints/)) |
| Cline | A company's open-source VS Code extension | Apache 2.0 **(one source)** | Yes | Yes, beside `.clinerules` ([Cline rules](https://docs.cline.bot/customization/cline-rules)) |
| OpenHands | An open-source project | MIT ([PromptQuorum](https://www.promptquorum.com/power-local-llm/openhands-review)) | Yes, and it warns that weak models "behave like a plain chatbot" | Not named on agents.md |
| Continue | Bought by Cursor in June 2026; its repository is now read-only **(one source)** ([runaihome](https://runaihome.com/blog/continue-dev-ollama-local-ai-coding-stack-2026/)) | Apache 2.0 | For agent mode | Not named |

**The column that decides the pathway is the fourth one.** Every agent
except Aider needs the model to call tools reliably, and the fully open
models are the weakest at that. Olmo 3 has no tools tag in Ollama's
library ([Ollama](https://ollama.com/library/olmo-3)), even though vLLM
can parse its function calls
([vLLM, tool calling](https://docs.vllm.ai/en/latest/features/tool_calling/)).
So a student who wants a fully open model from a public institution
should use Aider, which only asks the model to write text.

## The computer you need

| What the student has | What runs | What to expect |
|---|---|---|
| 8 GB of memory (this Mac) | A 7B or 8B model at 4-bit, about 4.5 to 6 GB: Olmo 3 7B is 4.5 GB ([Ollama](https://ollama.com/library/olmo-3)) and Apertus 8B is about 5 to 6 GB ([Unsloth GGUF](https://huggingface.co/unsloth/Apertus-8B-Instruct-2509-GGUF)) | Usable for conversation and one-file changes, with a short context, roughly 10 to 15 words a second on an M1 **(one source)** ([modelfit](https://modelfit.io/guides/can-8gb-mac-run-llm/)). Nothing else heavy can be open at the same time. |
| 16 GB | An 8B model with a longer context, or a 14B model | Comfortable for Aider; Devstral Small 2 is described as the floor for Cline on 16 GB **(one source)** ([Atlas Cloud](https://www.atlascloud.ai/blog/tips/best-qwen-model-for-local-coding)). |
| 32 GB or more on Apple silicon | Devstral Small 2 (24B), Olmo 3 32B (19 GB), or SERA-32B | Agentic tools start to work. OpenHands asks for 64 GB of unified memory, or a GPU with 24 GB, for its recommended model ([OpenHands](https://docs.openhands.dev/openhands/usage/llms/local-llms)). |
| A Windows or Linux PC with a recent GPU | Whatever fits in the card's memory | One tester reports a 16 GB card running Qwen3-Coder at single-file tasks on par with a frontier model **(one source)** ([Ganglani](https://www.kunalganglani.com/blog/local-llm-vs-claude-coding-benchmark)). |
| A Chromebook | Linux runs in a container you turn on in Settings ([Google, Chromebook Help](https://support.google.com/chromebook/answer/9145439?hl=en)), and it works on 4 GB machines | Not enough for a local model. Use the hosted fallback below. |

## When the computer is not enough

The **Public AI Inference Utility** is the one hosted option I found that
is not a large AI company. It launched September 2, 2025, serves public
and sovereign models (Apertus from Switzerland and SEA-LION from
Singapore at launch), runs on donated compute and advertising subsidies,
and offers free public chat ([Public AI, the Utility](https://publicai.co/stories/utility)).
Its developer platform has an OpenAI-compatible endpoint, lists Apertus,
SEA-LION, and Ai2's Olmo, and gives each new account $2 of starter
credit before per-token prices apply ([Public AI Gateway](https://platform.publicai.co/docs)).
Aider can point at any endpoint like that with `OPENAI_API_BASE` and a
model named `openai/<model>` ([Aider, OpenAI-compatible](https://aider.chat/docs/llms/openai-compat.html)).

Two things I could not confirm: whether Public AI is a registered
nonprofit (its pages describe "public" and "nonprofit" access but its
developer docs do not say **(unverified)**), and how far $2 goes over five
weeks. A cohort teacher should check both before recommending it, and a
student who will not send their code to any server at all should know
that this path does.

## How it compares with a frontier agent

The honest answer is that the gap has narrowed on single tasks and stayed
wide on long ones. One measurement put the best open-weights model within
a point of the best Claude model on SWE-bench Verified in February 2026,
while local 32B models "degrade past 32K tokens in practice" and could
not split work into subagents the way Claude Code did
([InsiderLLM](https://insiderllm.com/guides/local-alternatives-claude-code-2026/);
[byteiota, the 70% problem](https://byteiota.com/local-llms-vs-claude-for-coding-the-70-problem/)).
The same writers say smaller local models "punish vague requests" and do
exactly what you asked rather than what you meant. Those numbers are for
32B models on capable machines, which most novices will not have, so the
gap for an 8 GB laptop and a 7B model is wider again.

I think that last point is also the teaching opportunity. A small model
that does exactly what you asked makes the student say exactly what they
mean, which is the skill the path's "talking to your agent" page is trying
to build in the first place.

## The pathway, as I would recommend it

**The strict path, for a student who wants a fully open model from a
public institution and nothing sent anywhere.** Ollama, Olmo 3 7B Instruct
(or Apertus 8B, for a student who works in a language other than English),
and Aider, with `AGENTS.md` loaded through `.aider.conf.yml`. It needs at
least 8 GB and is better at 16. The agent writes text and the student runs
everything, which is slower and teaches a great deal.

**The practical open path, for a student who accepts open weights from an
AI company but will not use a hosted service.** Ollama, Devstral Small 2 or
Qwen3-Coder, and opencode or goose, which act like the agent the rest of
the cohort uses. It needs 32 GB on a Mac or a GPU with 16 GB or more.

**The fallback, for a student whose computer cannot run a model.** Aider
pointed at the Public AI Inference Utility with Apertus or Olmo. Their code
leaves the computer, but it goes to public models on public compute rather
than to a large AI company.

In every case the student picks once in Cohort Prep, writes down why in
their app's decisions, and can change their mind later.

## What changes in each week

| Week (from `COURSE.md`) | What changes on the open path |
|---|---|
| Cohort Prep | Install Ollama, fetch one model (a 4.5 GB download), set the context to at least 8K for Aider or 32K for the others, install Aider or opencode, and prove it works by asking the agent to change the app's name. The first win (the app's address on their phone) is the same. |
| 1: Why we build, the first prototype | The why conversation works well with any model, because it is talk. The prototype gets built in smaller asks: one screen, one file, one change at a time. The web is the first platform for everyone, and it is also the lightest for a small model. |
| 2: The shape of an app, going native | Building a native app while a model is loaded can run a laptop out of memory, so the student closes the model during builds. On 8 or 16 GB, I would suggest the installable web app as the second "platform" rather than Xcode or Android Studio. |
| 3: Seeing it work | Olmo 3 is text only, so the agent cannot look at a screenshot. The student is the eyes: they describe what they see or paste the error, which is the stage's lesson ("the agent is never the tester") made literal. |
| 4: Shipping, keeping it running | Nothing changes. The free sharing paths in stage 05 do not involve an AI at all. |
| 5: Raising the ceiling, working with AI | The skills and memories become sections of `AGENTS.md` (or `CONVENTIONS.md`), because none of these agents read `.claude/skills/`. The feature is smaller, and that is fine. |

## What the template needs

- **A shorter agent file for small models.** `AGENTS.md` is 22,019 bytes,
  roughly five to six thousand tokens, which is most of an 8K context
  before the student says a word. The open path needs a short version
  (a few hundred words: the why, the one rule, the commands, and where to
  look) that the long one points to, and a test like
  `tools/test_agent_files.py` that keeps it short.
- **Config files the agents read:** `.aider.conf.yml` with
  `read: AGENTS.md`, and an `opencode.json` example pointing at Ollama.
  `AGENTS.md` already works for opencode, goose, Cline, and Aider
  ([agents.md](https://agents.md/)).
- **A setup stage section**, "If you will not use an AI company," beside
  the Claude and Antigravity instructions in `docs/path/setup.md`, with the
  three paths above and the context-window warning.
- **Skills as pages.** The three skills a learner asks for by name
  (`human-shaped-review`, `learning-orientation-design`,
  `make-it-look-like-itself`) need a plain-Markdown version the student
  can hand to any agent, or read aloud to it.
- **Agent attribution.** The hub reads which agent worked on a commit from
  its `Co-Authored-By` lines (`assets/followup-lib.js` on the `site`
  branch). Aider marks its commits in its own way **(unverified)**, so the
  hub should learn to recognize Aider, opencode, and goose, or show
  "unsigned" without judgment.

## The evidence for the credential stays the same

The credential is earned from what the student built and what they can
show: the app at a real address, the repository's history, their
`HUMAN-SHAPED.md` answers, what they brought back each week, their
reviews, and the recognitions from class. None of that depends on which
agent helped. An open-path student will probably have more small commits
and more of their own reasoning in the history, and their decision to take
this path is itself evidence of the "who could this harm" question the
course is built around. The one adjustment is the review step: the
`human-shaped-review` skill becomes a page they walk through with a small
model, or with a classmate, and the review file is still theirs to share
or not.

## Honest limits

- **GitHub is owned by Microsoft.** The hub signs people in with GitHub,
  and the cohort's conversation lives there, so this path is not free of
  large companies. I have not looked at Codeberg or another host, and that
  is a decision for Ben.
- **The downloads come from Hugging Face or Ollama**, both companies,
  even when the model itself is from a public institution.
- **SERA is fully open training on top of Alibaba's weights**, so it is not
  as clean as Olmo or Apertus for a student who avoids AI companies.
- **Nobody has run this path yet.** Before the first cohort offers it, one
  person should take Cohort Prep and week 1 on an 8 GB Mac with Olmo 3 and
  Aider, and write down what broke.

## What I could not verify

opencode's and Cline's exact licenses, MLX's license, whether Public AI is
a registered nonprofit, SERA's license, whether Olmo 3 calls tools
reliably through Ollama, how Aider marks its commits, and every hardware
claim marked **(one source)**.

## Sources

- Ai2, "Olmo 3": https://allenai.org/blog/olmo3
- Olmo 3 paper: https://www.alphaxiv.org/abs/2512.13961
- Ai2, Open Coding Agents (SERA): https://allenai.org/blog/open-coding-agents
- Ollama library, olmo-3: https://ollama.com/library/olmo-3
- ETH Zurich, Apertus press release: https://ethz.ch/en/news-and-events/eth-news/news/2025/09/press-release-apertus-a-fully-open-transparent-multilingual-language-model.html
- Apertus 1.5 general availability: https://www.apertus-ai.org/articles/2026-09-apertus-1-5-ga/
- Unsloth, Apertus 8B GGUF: https://huggingface.co/unsloth/Apertus-8B-Instruct-2509-GGUF
- Open Source Initiative, OSAID FAQ: https://opensource.org/ai/faq
- Moesif, "What Is Open Source AI?": https://www.moesif.com/blog/technical/api-development/Open-Source-AI/
- Hugging Face, StarCoder2 and The Stack v2: https://huggingface.co/blog/starcoder2
- BigCode OpenRAIL-M: https://www.bigcode-project.org/docs/pages/bigcode-openrail/
- Mistral, Devstral 2 and Vibe CLI: https://mistral.ai/news/devstral-2-vibe-cli/
- Qwen3 on GitHub: https://github.com/QwenLM/qwen3
- Hugging Face community, open-source LLMs 2026: https://huggingface.co/blog/daya-shankar/open-source-llms
- Wikipedia, Ollama: https://en.wikipedia.org/wiki/Ollama
- Wikipedia, llama.cpp: https://en.wikipedia.org/wiki/Llama.cpp
- Stribog, local runtimes compared: https://stribog.com/blog/lm-studio-ollama-llama-cpp-local-model-runtimes-compared
- centron, Ollama vs LM Studio vs llama.cpp: https://www.centron.de/en/tutorials/ollama-vs-lm-studio-vs-llama-cpp
- Ollama, cloud models: https://ollama.com/blog/cloud-models
- Jan review (DEV): https://dev.to/jovan_chan_9500711396d4e6/jan-ai-review-2026-13ei
- Aider, Ollama: https://aider.chat/docs/llms/ollama.html
- Aider, OpenAI-compatible APIs: https://aider.chat/docs/llms/openai-compat.html
- Aider, edit formats: https://aider.chat/docs/more/edit-formats.html
- Ollama, Cline integration: https://docs.ollama.com/integrations/cline
- Cline, rules: https://docs.cline.bot/customization/cline-rules
- OpenHands, local LLMs: https://docs.openhands.dev/openhands/usage/llms/local-llms
- OpenHands review (PromptQuorum): https://www.promptquorum.com/power-local-llm/openhands-review
- goose, hints and context files: https://goose-docs.ai/docs/guides/context-engineering/using-goosehints/
- Wikipedia, goose: https://en.wikipedia.org/wiki/Goose_(AI_agent)
- agents.md: https://agents.md/
- awesome-agent-conventions: https://github.com/ItamarZand88/awesome-agent-conventions
- 4Geeks, Aider listing: https://agents.4geeks.com/agent/aider
- Zenva, OpenCode with Ollama: https://academy.zenva.com/opencode-local-llm-ollama/
- aicodinghub, OpenCode local models: https://aicodinghub.app/opencode-local-models/
- runaihome, Continue after the Cursor acquisition: https://runaihome.com/blog/continue-dev-ollama-local-ai-coding-stack-2026/
- vLLM, tool calling: https://docs.vllm.ai/en/latest/features/tool_calling/
- modelfit, 8 GB Macs: https://modelfit.io/guides/can-8gb-mac-run-llm/
- Atlas Cloud, Qwen for local coding: https://www.atlascloud.ai/blog/tips/best-qwen-model-for-local-coding
- Kunal Ganglani, local vs Claude: https://www.kunalganglani.com/blog/local-llm-vs-claude-coding-benchmark
- InsiderLLM, local alternatives to Claude Code: https://insiderllm.com/guides/local-alternatives-claude-code-2026/
- byteiota, the 70% problem: https://byteiota.com/local-llms-vs-claude-for-coding-the-70-problem/
- Google, Linux on Chromebook: https://support.google.com/chromebook/answer/9145439?hl=en
- Public AI, the Inference Utility: https://publicai.co/stories/utility
- Public AI Gateway docs: https://platform.publicai.co/docs

So the open path exists, and it is narrower. Try it once before we offer it.
