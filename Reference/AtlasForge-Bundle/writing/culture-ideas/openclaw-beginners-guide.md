Title: The Complete Beginner's Guide to Setting Up Your Own AI Agent — Atlas Forge

URL Source: https://atlasforge.me/writing/openclaw-beginners-guide/

Markdown Content:
Most people interact with AI through a chat window. Type a question, get an answer, close the tab. Start over tomorrow with zero memory of what you discussed.

An AI agent is different. It runs continuously on your hardware. It remembers your preferences, your projects, your writing style. It messages you on Telegram like a colleague. It can search the web, read your files, manage your calendar, and take action on your behalf. It gets better the longer you use it.

[OpenClaw](https://openclaw.ai/) is the open-source infrastructure that makes this possible. It's a gateway that connects an AI model (like Claude) to your messaging apps, your file system, and a growing library of tools. All running locally on a machine you control.

This guide will take you from zero to a working AI agent in about 30 minutes. No programming experience required. We'll take a safety-first approach: start with a sandboxed setup, build trust, then expand capabilities gradually.

## Why You'd Want This

Before we get into the how, let's make the why concrete. Say you're an author working on your next book.

**Research synthesis.** You send your agent a voice note: "Find me the three most-cited papers on variable reward schedules published after 2020 and summarize each in two paragraphs." Ten minutes later, it messages you back with summaries, links, and a note that one of the papers contradicts a claim in your previous book.

**First-draft feedback.** You drop a chapter draft into your workspace folder. "Read Chapter 7 and flag any arguments that feel under-supported. Be direct." It returns specific callouts with suggestions, not generic praise.

**Launch coordination.** "What's on my calendar this week that conflicts with the book launch prep? Draft a reschedule email for anything non-essential." It checks your calendar, identifies conflicts, and writes the emails, waiting for your approval before sending anything.

**Institutional memory.** Three months into the project, you ask: "What was that study I mentioned in our conversation back in November, something about dopamine and anticipation?" It searches its memory and finds it, because it remembers every conversation you've had.

**Daily briefing.** Every morning at 7am, it checks your email, calendar, and news mentions, then sends you a two-paragraph summary on Telegram. No app to open. No inbox to wade through.

None of this requires you to sit at a computer. The agent runs 24/7. You interact with it the same way you'd text a human assistant.

## The Dedicated Machine Approach

Here's the most important recommendation in this guide: **run OpenClaw on a separate computer from the one you work on every day.**

The reason is simple. An AI agent has access to the file system of whatever machine it's running on. If that's your primary laptop, the one with your passwords, financial documents, unpublished manuscripts, and personal photos, you've given the agent access to all of it on day one.

A dedicated Mac Mini solves this cleanly:

*   **Safety sandbox.** The agent can only access what's on that machine. Your personal files stay on your laptop.
*   **Always-on.** A Mac Mini draws about 5 watts at idle. Leave it running 24/7 and your agent is always available, even when your laptop is closed.
*   **Headless operation.** After initial setup, you never need to plug in a monitor. Manage everything over SSH or through the OpenClaw dashboard in your browser.
*   **Clean separation.** If something goes wrong, you unplug one machine. Your daily work is untouched.

An M4 Mac Mini starts at $599 and is wildly overpowered for this. OpenClaw runs comfortably on 8GB of RAM.

If you don't want to buy dedicated hardware right now, you can absolutely install OpenClaw on your primary Mac to try it out. Everything in this guide still applies. Just be more intentional about what files you put in the agent's workspace.

## What You'll Need

Before starting, gather these four things:

**1. A Mac Mini (or any Mac running macOS 12+).** New or existing. M1 or newer is ideal, but Intel works too.

**2. An Anthropic account (Max plan strongly recommended).** Your agent needs access to Claude, the AI model that powers it. You have two options:

*   **Anthropic Max plan ($100/month, recommended):** Subscribe at [claude.ai](https://claude.ai/). This gives you generous usage of Claude through the CLI interface with no per-token billing surprises. Predictable cost, best models, and you also get access to Claude's web interface for your own use. For most people, this is the right choice.
*   **Anthropic API key (pay-per-use):** Go to [console.anthropic.com](https://console.anthropic.com/), create an account, and generate an API key. You load credits as you go. $20 will last several weeks of light use, but costs can be unpredictable with heavy usage. The upside: you can configure cheaper fallback models (like Claude Sonnet) for simple tasks, keeping expensive models for when you actually need them.

**3. A Telegram account.** Telegram is the easiest messaging channel to set up with OpenClaw, and the most reliable for beginners. If you don't already have Telegram, download it on your phone and create an account. It's free.

**4. VS Code with the Claude extension (strongly recommended).** This is the secret weapon for non-technical users. Download [VS Code](https://code.visualstudio.com/) (free), then install the [Claude extension](https://marketplace.visualstudio.com/items?itemName=anthropics.claude-code) from the Extensions marketplace. This gives you a chat interface inside VS Code where you can talk to Claude in plain English and it will handle all the technical details for you. Instead of typing commands into a terminal, you just say what you want: "Install OpenClaw on this machine." Claude does the rest. It's also your safety net: if anything goes wrong at any point, you describe the problem in English and Claude diagnoses and fixes it.

**5. About 30 minutes.** The actual installation takes 5 minutes. The rest is configuration and your first conversation.

## Step 1: Set Up VS Code

If this is a fresh Mac Mini, go through the standard macOS setup. Connect it to WiFi, sign into your Apple account, and get to the desktop.

Download and install [VS Code](https://code.visualstudio.com/). Open it, click the Extensions icon in the left sidebar (it looks like four squares), search for "Claude," and install the Claude extension by Anthropic. Sign in with your Anthropic account.

Now open the Claude chat panel. This is your command center for everything that follows. You won't need to touch the Terminal directly. Just tell Claude what you want in plain English and it handles the technical work.

## Step 2: Install OpenClaw

In the Claude chat inside VS Code, type:

> "Install OpenClaw on this machine using the official installer script. If Node.js isn't installed, install that first."

Claude will run the necessary commands, install any missing dependencies, and set up OpenClaw. The whole process takes 2-5 minutes. You'll see Claude working through each step and explaining what it's doing.

When the installation finishes, Claude will launch the onboarding wizard.

## Step 3: Walk Through the Onboarding Wizard

The onboarding wizard asks you a series of questions to configure your agent. If you're unsure about any prompt, just ask Claude in the chat: "What should I pick here?" It can see what's on screen and guide you through each choice.

**QuickStart vs Advanced:** Choose **QuickStart**. It picks sensible defaults. You can change everything later.

**Model/Auth:** Select **Anthropic** and paste your API key when prompted. For the model, accept the wizard's suggestion.

**Workspace:** Accept the default location. This is the folder where your agent stores its memory, instructions, and files.

**Gateway:** Accept the defaults. The gateway is the service that keeps your agent running in the background.

**Channels:** When it asks about messaging channels, select **Telegram**. You'll need to create a Telegram bot first:

1.   Open Telegram on your phone
2.   Search for **@BotFather** (it's an official Telegram bot for making bots)
3.   Send it the message **/newbot**
4.   Give your bot a name (e.g., "My Agent") and a username (e.g., "my_agent_2026_bot")
5.   BotFather gives you a token, a long string of numbers and letters
6.   Paste that token into the wizard

**Skip other channels for now.** When asked about WhatsApp, Discord, or other channels, skip them. We're starting simple.

**Daemon:** Say **yes** to installing the daemon. This makes OpenClaw start automatically when the Mac Mini boots up.

**Skills:** Accept any recommended skills. These give your agent additional capabilities like web search.

The wizard finishes by starting the gateway and verifying everything works.

## Step 4: Lock Down Security

Before you start chatting, make sure only you can talk to your agent. In the Claude chat in VS Code, say:

> "Open the OpenClaw config file and add my Telegram user ID to the allowlist so only I can message the bot. Also disable heartbeats for now."

Claude will ask for your Telegram user ID. To find it: search for the bot **@userinfobot** on Telegram and start a chat with it. It replies with your ID number. Give that to Claude and it will update the configuration.

Heartbeats are a feature where the agent periodically wakes up and checks on things. Useful later, but we're skipping it until you're comfortable with the basics.

Claude will save the config and restart the gateway for you.

## Step 5: Your First Conversation

You have two ways to talk to your agent:

**Option A: The Dashboard.** Tell Claude in VS Code: "Open the OpenClaw dashboard." This launches a web interface where you can chat with your agent directly in the browser. Great for initial testing.

**Option B: Telegram (recommended for daily use).** Open Telegram on your phone, find the bot you created, and send it a message:

> Hi! What can you do?

The agent will respond. It takes a few seconds on the first message as the model loads context. Try a few more:

> Summarize the key argument of "Hooked" by Nir Eyal in three sentences.

> What's the weather in San Francisco this week?

> Create a file called ideas.md in your workspace with the heading "Book Ideas" and three placeholder bullets.

That last one demonstrates something important. The agent can take actions, not just answer questions. It created a file on the Mac Mini.

## Step 6: Make It Yours

Your agent's personality, instructions, and behavior are controlled by a few text files in its workspace. The most important ones:

**SOUL.md** — The agent's personality and values. How it communicates, what tone it uses, what it prioritizes. Edit this to match how you want your agent to talk to you.

**AGENTS.md** — Operating instructions. What to check, how to handle requests, what tools to use. Think of it as the agent's job description.

**USER.md** — Information about you. Your name, timezone, projects, preferences. The more context you give it, the better it serves you.

**MEMORY.md** — The agent's long-term memory. It updates this over time as it learns about you and your work.

To edit these, you can chat with the agent directly: "Show me the contents of SOUL.md" or "Update USER.md to include that I'm an author working on a book about habit formation." Or edit via SSH if you're comfortable with that. Or use the dashboard's file browser.

Start with USER.md. Tell it who you are, what you're working on, and how you prefer to communicate. The agent reads these files at the start of every session.

## The Safety-First Roadmap

Here's the progression I recommend:

**Week 1: Telegram only, no external access.** Chat with your agent. Ask it questions. Have it organize files in its workspace. Build trust. Verify it follows your instructions and respects your preferences.

**Week 2: Add web search.** Tell Claude in VS Code: "Add a Brave Search API key to OpenClaw so the agent can search the web." You'll need a free API key from [brave.com/search/api](https://brave.com/search/api). Now your agent can search the web when you ask it questions. Still no ability to send messages or emails on your behalf.

**Week 3: Enable heartbeats.** Tell Claude: "Enable OpenClaw heartbeats every 30 minutes." Your agent now wakes up periodically and can proactively check on things. Start with a simple HEARTBEAT.md that just checks weather or news.

**Week 4+: Expand as needed.** Add email access (read-only first). Connect additional channels. Install specialized skills from [clawhub.com](https://clawhub.com/). Each expansion is a deliberate choice, not an accident.

The point is: you control the blast radius at every step. The agent only has the capabilities you explicitly give it.

## What Not to Connect (Yet)

In the spirit of starting safe, here's what I'd hold off on:

*   **Twitter/X** — A rogue tweet is hard to undo. Wait until you deeply trust your agent's judgment.
*   **Email sending** — Read access is fine. Sending on your behalf requires high trust.
*   **Financial accounts** — Keep these completely separate until you're an advanced user.
*   **Your primary computer's file system** — This is why we recommended the Mac Mini approach.

There's no rush. The agent isn't going anywhere. Expand capabilities as trust grows.

## Common Questions

**How much does it cost to run?** The Mac Mini is a one-time cost (~$599). If you're on the Anthropic Max plan ($100/month), that covers generous Claude usage with predictable billing. If you're using API keys instead, light use runs about $5-15/month, heavy use $30-50/month. You can also configure cheaper fallback models (like Claude Sonnet or even open-source models) for routine tasks, keeping costs down while reserving the best model for complex work. OpenClaw makes it easy to set up model fallback chains. OpenClaw itself is free and open source.

**Can I access my agent when I'm not home?** Yes. Telegram works from anywhere. For dashboard access outside your local network, you can set up Tailscale (a free VPN service). The OpenClaw wizard has built-in support for this.

**What happens if the Mac Mini loses power?** The agent stops until power returns. Because we installed the daemon, it starts back up automatically. No data is lost. Your agent picks up where it left off.

**Can multiple people use the same agent?** Yes. Add additional Telegram user IDs to the allowFrom list. Each person gets their own conversation session by default.

**Is my data private?** Your conversations are stored locally on the Mac Mini. OpenClaw never sends data to its own servers. The only external service is the AI provider (Anthropic) which processes your messages to generate responses. Review their data policy if this matters to you.

**What if something breaks?** This is where VS Code with the Claude extension really shines. Open VS Code, describe what happened ("the gateway stopped responding" or "I'm getting an error when I message the bot"), and Claude will diagnose the issue, check logs, and fix it. You never have to interpret error messages yourself. It's like having an on-call technician who speaks English.

**What if I want to start over?** Tell Claude in VS Code: "Reset the OpenClaw configuration and run the onboarding wizard again." It will handle the rest.

## Handy Slash Commands

These work inside any chat with your agent (Telegram or the dashboard):

*   **/status** — Check what model you're using and how much of your context window is left
*   **/new** or **/reset** — Start a fresh conversation
*   **/compact** — Free up space if the conversation gets long

For anything else (checking if the gateway is running, diagnosing issues, changing settings), just ask Claude in VS Code. It can run any maintenance task for you.

## Resources

*   **Official docs:**[docs.openclaw.ai](https://docs.openclaw.ai/)
*   **Community Discord:**[discord.gg/clawd](https://discord.gg/clawd) — active community, good for troubleshooting
*   **GitHub:**[github.com/openclaw/openclaw](https://github.com/openclaw/openclaw)
*   **Skills marketplace:**[clawhub.com](https://clawhub.com/) — browse additional capabilities
*   **Video walkthrough:** Search "OpenClaw setup tutorial" on YouTube for visual guides

## One More Thing

The most common mistake people make with AI agents isn't technical. It's treating them like a search engine.

An agent is more like a new hire. It needs onboarding. It needs to understand your context, your preferences, how you work.

Spend the first week not just using it, but teaching it. Edit the USER.md file. Correct it when it gets your tone wrong. Tell it what matters to you. The compound returns on that investment are significant. A well-configured agent after a month of use is qualitatively different from the same agent on day one.

Welcome to the future of personal computing. It starts with a Mac Mini and a Telegram message.