# CLAUDE.md - how to work in the {{PROJECT_NAME}} project

Claude Code reads this file automatically at the start of every session in this folder.
It explains how the project is laid out and how I, a beginner, want you to work with me.

## What this is

A Roblox game built with **Rojo**. The code lives in files in this folder and Rojo syncs it
live into Roblox Studio. Studio owns the *world* (parts, terrain, UI placed by hand, saved in
the `.rbxlx` place file). This folder owns the *code*.

## Layout (defined in default.project.json)

| On disk | Appears in Studio as | Runs on |
|---|---|---|
| `src/server/` | ServerScriptService.Server | the server: game rules, scores, saving data, anything players must not cheat |
| `src/client/` | StarterPlayer.StarterPlayerScripts.Client | each player's own computer: UI, camera, input, effects |
| `src/shared/` | ReplicatedStorage.Shared | both sides: ModuleScripts with shared helpers and config |
| `default.project.json` | the mapping above | n/a. Ask before changing it |
| `{{PROJECT_NAME}}.rbxlx` | the saved place (world) | n/a. Opened and saved in Studio |

Rojo file naming rules:

- `Thing.server.luau` becomes a Script. `Thing.client.luau` becomes a LocalScript. `Thing.luau` becomes a ModuleScript.
- An `init.server.luau` inside a folder turns that folder itself into a Script (same for `init.client.luau` and `init.luau`).

## Daily workflow

1. Terminal 1, in this folder: `rojo serve` (leave it running).
2. Roblox Studio: open `{{PROJECT_NAME}}.rbxlx`, then Plugins tab > Rojo > Connect.
3. Terminal 2, in this folder: `claude`.
4. Edit files in `src/`. They appear in Studio within a second. Press Play (F5) to test.
5. View > Output in Studio shows every `print()` and every error.
6. Built something by hand in Studio? Save the place (Ctrl+S). Changed code? Commit with git.

## How I want you to work with me

- I am new to programming and to Roblox. Explain what you change and why in plain words, in short paragraphs.
- Small steps. One feature at a time, then tell me exactly how to test it in Studio before we move on.
- When you add a script, say which folder it goes in and why (server, client or shared).
- The first time a Roblox concept comes up (RemoteEvents, Touched, Humanoid, DataStores, CollectionService...) teach it to me in two or three sentences.
- Ask before: changing `default.project.json`, adding packages (Wally), deleting files, or doing anything to the `.rbxlx` file.
- Never put secrets, API keys or passwords in code.
- If I ask for something that is a bad idea in Roblox (for example trusting the client with money), say so and offer the right way.

## Luau conventions

- Put `--!strict` at the top of new files. Add type annotations where they make the code clearer.
- `local` for everything. PascalCase for ModuleScripts and services, camelCase for variables and functions.
- Get services with `game:GetService("Players")`, never `game.Players`.
- Server-authoritative: the server decides anything that matters (health, money, wins). Clients only *ask* via RemoteEvents or RemoteFunctions, and the server validates every request.
- Clean up connections you create (`connection:Disconnect()`) when the thing they belong to goes away.
- Format with StyLua and lint with Selene before committing: `stylua src` then `selene src`.

## Testing

- There are no automated tests yet. "Tested" means: Play in Studio, do the action, confirm the Output window shows the expected print and no red errors.
- When you ask me to test, give me the exact clicks and what I should see.
- Later, when the project grows, suggest adding Jest-Lua or TestEZ for shared modules.

## Useful commands

```
rojo serve                            # live-sync this folder into Studio
rojo build -o {{PROJECT_NAME}}.rbxlx  # rebuild the place file from the project files
stylua src                            # format all Luau files
selene src                            # lint all Luau files
git add -A && git commit -m "..."     # save a checkpoint
git log --oneline                     # see the history of checkpoints
```

## Skills (typed as /name in Claude Code)

- `/graphify` is the primary way to understand this project. If `graphify-out/` exists, answer any
  "how does X work", "what calls Y" or "where is Z" question with `/graphify query "..."` before
  opening files. It costs far fewer tokens than reading scripts one by one and keeps the answer focused.
- If `graphify-out/` does not exist and the project has more than a handful of scripts, suggest
  running `/graphify .` once. After a big feature, suggest `/graphify . --update`.
- `/journal` (in `.claude/skills/journal/`) drafts today's `JOURNAL.md` entry. Offer it at the end of a session.
- If I correct you about the same thing twice, suggest turning the rule into a line in this file or a new skill.

## Learning log

I keep notes in `JOURNAL.md`. At the end of a session, offer to run `/journal` so we record
what we built, what I learned, what I got stuck on, and what is next.

## Reference

- Roblox Creator docs: https://create.roblox.com/docs
- Luau language: https://luau.org
- Rojo: https://rojo.space/docs/v7
