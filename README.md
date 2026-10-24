# Roblox + Claude Code starter kit for Windows 11

A one-click setup that takes a Windows 11 PC with no development tools on it to a working
Roblox game-development environment driven by Claude Code, plus a first project and a way to
record what you learn.

## What you end up with

- **Roblox Studio** to build and play-test your game.
- **Claude Code** in a terminal and inside VS Code, reading and writing your game's code.
- **Rojo** so that the code Claude writes on disk appears in Studio instantly.
- **VS Code** with Luau autocomplete, formatting and lint warnings.
- **Git** so every working version is saved and you can always go back.
- A first project at `C:\Users\<you>\RobloxProjects\my-first-game` with a `CLAUDE.md` that
  teaches Claude how the project works and a `JOURNAL.md` for your learning log.
- Two **skills** (reusable instructions Claude loads on demand, see below): **graphify**, which
  builds a knowledge graph of your project so Claude answers questions from the graph instead of
  re-reading every file, and **/journal**, which writes the day's log entry for you.

## Before you start

| Need | Why | Cost |
|---|---|---|
| A Roblox account | to log in to Roblox Studio | free, https://www.roblox.com |
| A Claude **Pro** or **Max** subscription | Claude Code does not work on the free plan | paid, https://claude.ai |
| About 6 GB of free disk and 20 minutes | installs plus first downloads | |

You do **not** need to be an administrator, and it is better not to "Run as administrator":
per-user tools then install into your own account. Windows will show one or two "allow this app
to make changes" prompts for Git and VS Code. Click Yes.

## Run it

1. Put this whole folder somewhere easy, for example `C:\Users\<you>\Downloads\roblox-dev-starter`.
   Keep `Setup-RobloxDev.ps1` and the `templates` folder together.
2. Double-click **Run-Setup.cmd**. A black window opens and reports progress step by step.
3. When it finishes it prints a summary table and a "What to do next" list. Follow that list.

Prefer the terminal? Open PowerShell in this folder and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Setup-RobloxDev.ps1
```

Useful variations:

```powershell
.\Setup-RobloxDev.ps1 -DryRun                          # show the plan, change nothing
.\Setup-RobloxDev.ps1 -ProjectName obby-game           # name the first project
.\Setup-RobloxDev.ps1 -Skip Node                       # leave out Node.js
.\Setup-RobloxDev.ps1 -Skip Studio,Project             # only the tooling
.\Setup-RobloxDev.ps1 -Skip Skills                     # leave out uv + graphify
```

Step names for `-Skip`: Git, VSCode, Studio, Node, Claude, Rokit, Tools, Extensions, Plugin, Skills, Project.

The script is safe to run again. Everything already installed is detected and skipped, so if
one step fails you fix the cause and run it again. Every run writes a log to
`C:\Users\<you>\roblox-dev-setup-logs\`.

## What gets installed and why

| Tool | What it is for | How it is installed |
|---|---|---|
| Git for Windows | version history; also gives Claude Code a Bash shell | `winget install Git.Git` |
| Visual Studio Code | editor where you read code and run Claude Code side by side | `winget install Microsoft.VisualStudioCode` |
| Roblox Studio | the game engine and world editor | `winget install Roblox.RobloxStudio`; when winget's copy is out of date, Roblox's signed installer from `setup.rbxcdn.com` |
| Node.js LTS | many Claude Code extras (MCP servers) need it | `winget install OpenJS.NodeJS.LTS` |
| Claude Code | the AI coding agent | Anthropic's installer `irm https://claude.ai/install.ps1 \| iex` (auto-updates); falls back to `winget install Anthropic.ClaudeCode` |
| Rokit | installs and version-pins Roblox command-line tools | latest release from github.com/rojo-rbx/rokit, then `rokit self-install` (what Rokit's `install.ps1` does) |
| Rojo | syncs files on disk into Studio; builds place files | `rokit add --global rojo-rbx/rojo` |
| StyLua | formats Luau code | `rokit add --global JohnnyMorganz/StyLua` |
| Selene | finds mistakes in Luau code | `rokit add --global Kampfkarren/selene` |
| Rojo Studio plugin | the Studio end of the sync | `rojo plugin install` |
| VS Code extensions | Claude Code, luau-lsp, Rojo, StyLua, Selene, roblox-ui | `code --install-extension ...` |
| uv | runs Python tools without you managing Python; downloads Python itself | Astral's installer `irm https://astral.sh/uv/install.ps1 \| iex`; falls back to `winget install astral-sh.uv` |
| graphify | knowledge graph of your project; the `/graphify` skill in Claude Code | `uv tool install --python 3.13 graphifyy` then `graphify install --platform windows` |
| /journal skill | example project skill, copied into the new project | `templates\skills\journal\SKILL.md` to `.claude\skills\journal\` |

## How the pieces fit together

```
 You + Claude Code  ──edit──>  src\*.luau  (your project folder, tracked by git)
                                   │
                              rojo serve
                                   │  live sync
                                   v
                            Roblox Studio  ──Play (F5)──>  Output window shows prints & errors
                                   │
                           Ctrl+S saves the WORLD (parts, terrain, UI) to my-first-game.rbxlx
```

Two things to internalise early:

- **Code lives on disk, world lives in Studio.** Claude edits `src\`. Anything you build by
  dragging parts around in Studio lives in the `.rbxlx` file. Save both.
- **Server vs client.** `src\server` runs on Roblox's machines and is the only place that may
  decide things that matter (points, money, who won). `src\client` runs on each player's PC and
  handles what they see and press. `src\shared` is code both sides can use.

## Your first 15 minutes after setup

1. Open Roblox Studio from the Start menu, log in, close the template picker.
2. Open a **new** Terminal window (Start > Terminal). New, so it picks up the PATH changes.
3. Run `claude` and follow the browser login.
4. `cd C:\Users\<you>\RobloxProjects\my-first-game` then `rojo serve`. Leave it running.
5. In Studio: File > Open from File > `my-first-game.rbxlx`. Plugins tab > Rojo > Connect.
6. Second terminal in the same folder: `claude`. Ask it:
   *"Read CLAUDE.md and explain how this project is set up, like I'm brand new."*
7. Press Play (F5) in Studio. View > Output should show `Hello world, from server!`.
8. Ask Claude: *"Make a part that changes colour when a player touches it. Explain every line."*
   Watch it appear in Studio, play, touch it. You have shipped your first feature.
9. Type `/graphify .` in Claude Code. It builds the project's knowledge graph. Then try
   `/graphify query "what runs on the server?"`. From now on, ask questions that way first.
10. Type `/journal`. Claude drafts today's entry; you fix the "Learned" lines in your own words.

## Skills: teaching Claude something once

A **skill** is a folder holding a `SKILL.md` file: a name, one line saying when to use it, and
instructions. Claude Code loads it only when it is needed, so a skill costs nothing until it fires.
You run one by typing `/name`, or Claude picks it up itself when your request matches the description.

| Where the folder lives | Applies to |
|---|---|
| `C:\Users\<you>\.claude\skills\<name>\SKILL.md` | every project on your PC |
| `<project>\.claude\skills\<name>\SKILL.md` | that project only; commit it so it travels with the code |
| plugins (type `/plugin` inside Claude Code) | bundles of skills from a marketplace, used as `/plugin:skill` |

The kit sets up two.

### /graphify: the primary skill, and the one that saves tokens

[graphify](https://github.com/Graphify-Labs/graphify) turns a folder into a knowledge graph: every
script, function and module, the links between them, and a plain-English `GRAPH_REPORT.md`. Code is
parsed locally, so building the graph for code uses no AI budget; Claude only names the clusters.
The graph lives in `graphify-out\` and survives between sessions.

Why it matters when you pay for a plan: without a graph, every "how does X work?" makes Claude
search and open files, and every file it reads is spent from your session's token budget. With a
graph, Claude runs a query and gets back only the handful of connected nodes that matter. Smaller
context, quicker answers, and far less re-reading as the game grows. `CLAUDE.md` tells Claude to
check the graph first whenever `graphify-out\` exists.

```
/graphify .                                 # build or rebuild the graph for this project
/graphify query "how does scoring work"     # answer from the graph, not by reading every file
/graphify query "..." --budget 800          # cap the answer at roughly 800 tokens
/graphify path "RoundTimer" "Leaderstats"   # how two things connect
/graphify explain "TouchHandler"            # everything connected to one node
/graphify . --update                        # after a big change, re-extract only what changed
```

Habits: run `/graphify .` once the project has more than a handful of scripts, `--update` after each
big feature, and ask questions through it before asking Claude to open files. Optional always-on
mode: run `graphify claude install` in the project folder once; it adds a section to `CLAUDE.md`
and a hook so Claude consults the graph without being told.

### /journal: an example you can read in two minutes

The new project contains `.claude\skills\journal\SKILL.md`, a seven-step skill that drafts today's
`JOURNAL.md` entry from the git log and the conversation, asks you to put the "Learned" lines in your
own words, then appends it. Open the file. That is all a skill is. Copy it to make your own, for
example `/test-plan` (write Studio test steps for the last change), `/explain-file` (explain one
script line by line) or `/commit` (write a plain-English commit message for what changed).

### Finding more

Inside Claude Code: `/plugin marketplace add anthropics/claude-plugins-official`, then `/plugin` to
browse and install. Claude Code's built-in `/init` writes a first `CLAUDE.md` for any project that
has none. Docs: https://code.claude.com/docs/en/skills

## A learning path that works

Each stage is a weekend or a few evenings. Give Claude the quoted prompt as a starting point, and
always end a session by asking it to update `JOURNAL.md`.

1. **Touch, print, change.** Parts that react to players. *"Explain Touched events and debounce."*
   Concepts: Workspace, Parts, events, functions, variables.
2. **Game loop.** A round timer, a scoreboard in a leaderstats folder. *"Build a 60-second round
   with a countdown shown to all players."* Concepts: loops, `task.wait`, Players service, leaderstats.
3. **Client and server talk.** A button in the UI that asks the server to do something.
   *"Add a ScreenGui button that fires a RemoteEvent; the server validates and gives 10 points."*
   Concepts: RemoteEvents, why the server must validate, ReplicatedStorage.
4. **Save progress.** *"Save each player's points with DataStoreService, with retries and a test
   plan."* Concepts: DataStores, pcall, PlayerRemoving.
5. **Tidy and ship.** *"Review the code for anything a cheater could abuse and anything duplicated.
   Suggest what to turn into shared modules."* Then File > Publish to Roblox.

After that: Wally for packages, Jest-Lua or TestEZ for tests, and the Roblox Creator docs
tutorials at https://create.roblox.com/docs/tutorials.

## Documenting the journey

The habits below cost minutes and pay for themselves within a week.

- **`/journal` at the end of every session.** It drafts the entry (Built / Learned / Stuck / Next /
  Commit) from the git log and the conversation; you correct the "Learned" lines in your own words.
  If you cannot explain a concept, you have not learned it yet.
- **Commit after every working step.** `git add -A && git commit -m "Touch part changes colour"`.
  The commit log becomes the timeline of your learning. Ask Claude: *"write the commit message
  for what we just did"*. Later, `git log --oneline` is a history you can read back.
- **Push to a private GitHub repo** once you are comfortable. Free backup, and something to show.
- **Grow CLAUDE.md.** Every time you correct Claude ("no, I want short explanations", "always use
  strict mode"), ask it to add that rule to `CLAUDE.md`. It is the project's memory across sessions.
  Claude Code's `/init` command can also generate one for a project that has none.
- **Keep a `docs\decisions.md`** with one line per decision: "Points live on the server because the
  client can be modified." Ask Claude to append to it whenever you choose between two approaches.
- **Screenshots and GIFs** in a `media\` folder. Progress is motivating when you can see it.
- **Resume sessions** with `claude --continue` or `claude --resume` so context carries over.
- **One prompt pattern to copy:** *"Before writing code, explain the plan in three bullet points
  and wait for my OK."* It keeps you in control and you learn the reasoning, not just the result.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `claude` is not recognised | Open a **new** terminal. Still broken? Check `C:\Users\<you>\.local\bin\claude.exe` exists and that folder is on your user PATH. Or run `winget install Anthropic.ClaudeCode`. |
| `rojo` or `rokit` not recognised | Same: new terminal. Rokit installs to `C:\Users\<you>\.rokit\bin`. On Windows, Rokit may ask for a full restart. If the setup log says Rokit failed, the `rokit self-install` lines just above the `[FAIL]` say why. |
| rokit: "The following tool has not been marked as trusted" | Rokit asks before installing a tool the first time, and gives this error when it cannot ask. Run the `rokit add ...` command yourself in a terminal and answer yes, or run `rokit trust <owner/tool>` first. |
| Roblox Studio: "Installer hash does not match" (winget exit code -1978335215) | winget's catalog entry is behind Roblox's latest installer. The script then downloads Roblox's signed installer itself. If that also fails, install Studio from https://create.roblox.com and re-run. |
| `winget` is not recognised | Microsoft Store > search "App Installer" > Update. Then re-run. |
| "running scripts is disabled on this system" | Use `Run-Setup.cmd`, or the `-ExecutionPolicy Bypass` command above. |
| Studio: Rojo button missing | Run `rojo plugin install` in a terminal, then restart Studio. |
| Studio: Rojo cannot connect | Is `rojo serve` running in the project folder? Default address is `localhost:34872`. |
| Claude Code says the free plan is not supported | Claude Code needs Pro or Max. Log in at https://claude.ai with that account. |
| `/graphify` is not in the `/` menu | In a terminal run `graphify install --platform windows`, then restart Claude Code. The skill file should be at `C:\Users\<you>\.claude\skills\graphify\SKILL.md`. |
| `graphify` or `uv` not recognised | New terminal. In VS Code's terminal, quit and reopen VS Code. Still broken? Sign out of Windows and back in. uv and its tools live in `C:\Users\<you>\.local\bin`; run `uv tool update-shell` if that folder is still missing from PATH. |
| graphify: "Microsoft Visual C++ 14.0 or greater is required" | uv picked a Python too new for graphify's `tree-sitter` dependency. Run `uv tool install --python 3.13 graphifyy`, then `graphify install --platform windows`. Re-running the setup script does this for you. |
| `/journal` is not in the `/` menu | Start `claude` from inside the project folder; project skills only load there. Check `.claude\skills\journal\SKILL.md` exists. |
| Setup failed half way | Read the `[FAIL]` line and the log in `roblox-dev-setup-logs\`. Fix the cause, re-run; done steps are skipped. |

## Optional extras, once the basics feel comfortable

- **Roblox Studio MCP server** (github.com/Roblox/studio-rust-mcp-server): lets Claude read and
  change the open place in Studio directly, not just the code. Official, but Roblox has marked it
  as no longer actively developed, and anything connected to it can modify your place. Try it on a
  copy of your game first.
- **Wally** (`rokit add --global UpliftGames/wally`): package manager for Luau libraries.
- **GitHub Desktop**: a visual way to see what changed and commit, if the terminal feels like a lot.
