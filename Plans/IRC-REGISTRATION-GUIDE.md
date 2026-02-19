# Libera.Chat IRC Registration Guide

**Purpose:** Register your personal nick, the Gregor bot nick, create #gregor, and get your hostmask for the masterplan config.
**Time needed:** ~15 minutes
**Pre-requisite:** An email address for verification

---

## Step 0: Install an IRC Client

You need an IRC client on your local machine. Pick one:

```bash
# Option A: irssi (terminal, lightweight)
sudo apt install irssi

# Option B: weechat (terminal, feature-rich)
sudo apt install weechat

# Option C: HexChat (GUI, if you have X/Wayland forwarding on WSL2)
sudo apt install hexchat
```

---

## Step 1: Register Your Personal Nick

### 1.1 Connect to Libera.Chat

```bash
# Using irssi:
irssi -c irc.libera.chat -p 6697 --tls -n YOUR_CHOSEN_NICK

# Using weechat:
weechat
# Then inside weechat:
/server add libera irc.libera.chat/6697 -tls
/connect libera
/nick YOUR_CHOSEN_NICK
```

### 1.2 Register with NickServ

Once connected and using your desired nick:

```
/msg NickServ REGISTER YourStrongPassword your-email@example.com
```

**Password rules:**
- Use a strong, unique password (not reused anywhere)
- Store it in a password manager
- This password goes into `/etc/openclaw/env` later as `IRC_NICKSERV_PASSWORD`

### 1.3 Verify via Email

NickServ sends a verification email. It contains a command like:

```
/msg NickServ VERIFY REGISTER YOUR_NICK some-verification-code
```

Copy-paste that exact command into your IRC client. You should see:

```
NickServ: Your account is now verified.
```

### 1.4 Confirm Registration

```
/msg NickServ INFO YOUR_NICK
```

Should show your registered account details.

---

## Step 2: Register the Gregor Bot Nick

The bot needs its OWN separate account (not grouped to yours). This is because the bot will authenticate independently from the VPS.

### 2.1 Switch to the Bot Nick

```
/nick Gregor
```

If `Gregor` is taken, you'll get an error. Try alternatives:
- `Gregor_` or `Gregor-` (temporary, can try to claim later)
- `GregorBot`
- `Gregor|bot`

### 2.2 Register Gregor

```
/msg NickServ REGISTER BotStrongPassword your-email@example.com
```

**Use the same email or a different one** — Libera.Chat allows multiple nicks per email.

### 2.3 Verify Gregor's Registration

Check your email for the verification command and run it:

```
/msg NickServ VERIFY REGISTER Gregor some-verification-code
```

### 2.4 Switch Back to Your Nick

```
/nick YOUR_PERSONAL_NICK
/msg NickServ IDENTIFY YourStrongPassword
```

### 2.5 Save Gregor's Password

You'll need this for the masterplan:

```
# This goes in /etc/openclaw/env on the VPS:
IRC_NICKSERV_PASSWORD=BotStrongPassword
```

---

## Step 3: Create and Register #gregor

You must be identified with NickServ to register a channel.

### 3.1 Join the Channel

```
/join #gregor
```

If the channel doesn't exist, you'll create it and automatically become the operator (you'll see `@YOUR_NICK` in the user list).

### 3.2 Register with ChanServ

```
/msg ChanServ REGISTER #gregor
```

ChanServ confirms:

```
ChanServ: #gregor is now registered to YOUR_NICK.
```

### 3.3 Set Channel Topic

```
/msg ChanServ TOPIC #gregor Gregor — AI assistant powered by Claude | github.com/mj-deving/openclaw-bot
```

### 3.4 Set Channel Modes

```
# Make the channel moderated-ish but open to join:
/mode #gregor +nt

# +n = no external messages (must be in channel to send)
# +t = only ops can change topic
```

### 3.5 Give the Bot Auto-Op

After Gregor (the bot) joins later, you can auto-op it:

```
/msg ChanServ FLAGS #gregor Gregor +AOt
```

Flags: `+A` = auto-op, `+O` = op, `+t` = topic change

---

## Step 4: Find Your Hostmask

Your hostmask is what goes into the `allowFrom` whitelist in the masterplan config.

### 4.1 WHOIS Yourself

```
/whois YOUR_NICK
```

Look for a line like:

```
YOUR_NICK is ~username@hostname
```

or after being identified, Libera.Chat may give you a cloak:

```
YOUR_NICK is ~username@user/YOUR_NICK
```

### 4.2 Record the Hostmask Pattern

The full hostmask format is: `nick!user@host`

**If you have a cloak** (e.g., `user/YourNick`):
```
YOUR_NICK!*@user/YourNick
```

**If you have a raw IP/hostname** (e.g., `123.45.67.89`):
```
YOUR_NICK!*@123.45.67.89
```

**If you want to match any connection:**
```
YOUR_NICK!*@*
```
(Less secure — anyone using your nick before you identify could match)

### 4.3 Update the Masterplan

Replace all `yournick!*@*` placeholders in `Plans/MASTERPLAN.md` with your actual hostmask. The locations:

- `channels.irc.groupAllowFrom`
- `channels.irc.groups."#gregor".allowFrom`
- `channels.irc.toolsBySender`
- `channels.irc.allowFrom`

---

## Step 5: Verify Everything

Run these checks before moving to implementation:

```
# 1. Confirm your nick is registered
/msg NickServ INFO YOUR_NICK

# 2. Confirm Gregor is registered
/msg NickServ INFO Gregor

# 3. Confirm #gregor is registered
/msg ChanServ INFO #gregor

# 4. Confirm your hostmask
/whois YOUR_NICK
```

### Checklist

- [ ] Personal nick registered and verified
- [ ] Gregor nick registered and verified
- [ ] Gregor's NickServ password saved securely
- [ ] #gregor channel created and registered
- [ ] Your hostmask recorded
- [ ] Hostmask placeholders updated in MASTERPLAN.md

---

## After This Guide

With all registrations done, you're ready for **Phase 0** (VPS preparation). Bring the following to the next session:

1. Your IRC nick and hostmask pattern
2. Gregor's NickServ password
3. Your VPS SSH access details (IP, username)
4. Your Telegram bot token (from @BotFather — see Phase 3b in masterplan)

---

*All commands are for Libera.Chat specifically. Other IRC networks may differ.*
