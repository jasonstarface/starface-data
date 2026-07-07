# Starface Data for Claude Desktop

Ask Claude Desktop questions about Starface's data — sales, revenue, ad performance,
retail sell-through — and it queries the company datalake for you. Read-only.

## Setup (about 5 minutes, one time)

1. Open **Terminal** — press `Cmd + Space`, type `Terminal`, press Return.
2. **Copy this whole line, paste it into Terminal, and press Return:**

   ```
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/jasonstarface/starface-data/main/install.sh)"
   ```

3. Let it run. Along the way it may:
   - ask for your **Mac password** (to install the tools it needs — the password stays invisible
     as you type; just press Return), and
   - open a **browser** — sign in with your **Starface Google account** and click Allow.
4. When it says **✅ All set**, **quit Claude Desktop completely** (`Cmd + Q`) and reopen it.

That's the whole thing — one paste. (No app to open, so macOS won't block anything.)

## Using it

Just ask Claude Desktop normal questions, for example:

- "What was DTC net revenue last week?"
- "Meta ROAS for the last 90 days by country."
- "Top 10 SKUs by revenue this month."
- "CVS in-stock rate for Q2."
- "How many orders did we get yesterday across all channels?"

Claude knows the table layout and the house rules (which tables to use, how revenue is
defined), so you can ask in plain English.

## Notes

- **Read-only.** You can look at data; nothing can be changed or deleted through this.
- **Your own login.** You're signed in as you, and only see what your Google account is
  allowed to see.
- **Re-running the installer** is safe anytime (e.g. after a Mac update, or to sign back in).

## Something not working?

- *The paste didn't run / "command not found"* → make sure you copied the **entire** line
  (it starts with `/bin/bash`) and pasted it into Terminal, then pressed Return.
- *"Ask Jason for IAM access…"* → your account hasn't been granted access yet. Message Jason.
- *Claude doesn't seem to have the data tools* → make sure you fully **quit and reopened**
  Claude Desktop after installing.
- Anything else → send Jason (jason@starfaceworld.com) a screenshot of the Terminal window.
