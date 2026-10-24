---
name: journal
description: Write today's entry in JOURNAL.md at the end of a session. Use when the user says "journal", "log today", "add a journal entry", or asks what we learned today.
---

# /journal

Draft a learning-journal entry for the current session and append it to `JOURNAL.md` in the project root.

## Steps

1. Read `JOURNAL.md`. Note the date and number of the last entry so the new one continues the sequence.
2. Run `git log --oneline -15` and `git status --short` to see what changed this session.
3. Look back over this conversation for what was built, which Roblox or Luau concepts came up, and where the user got stuck.
4. Draft one entry in exactly this shape. Keep every line short and in plain words a beginner would use:

   ```
   ## YYYY-MM-DD - Session N: <three-word title>

   **Built:** <what exists now that did not before>

   **Learned:**
   - <concept in one sentence, in the user's words where possible>
   - <concept>

   **Stuck / questions:**
   - <anything that confused the user, or "nothing today">

   **Next:** <one small concrete step>

   **Commit:** <latest commit message, or "not committed yet">
   ```

5. Show the draft and ask the user to correct the **Learned** lines in their own words. Do not append until they confirm.
6. Append the confirmed entry to the end of `JOURNAL.md`. Do not rewrite earlier entries.
7. If there are uncommitted changes, offer to commit them with a one-line message that matches the **Built** line.
