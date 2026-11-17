# 🔓 LidAwake

**Close the lid. Your agent keeps cooking.**

You know the walk. Laptop held open at a 20° angle like a waiter carrying soup. Screen glowing into your chest. Walking to the kitchen, the car, the bathroom (we don't judge), all because if that lid closes, your coding agent dies halfway through building its **10th dashboard of the day**.

Stop larping as a laptop-shaped clamshell. Say no more. Use this.

LidAwake is a tiny menu bar app that keeps your Mac running with the lid **fully closed**: no external monitor, no charger, no dongle sacrifices. Click the laptop, close the lid, go touch grass. Your agent will still be shipping dashboard #11 when you get back.

<p align="center"><img src="docs/menu.png" width="520" alt="LidAwake menu: awake with lid closed, off in 58:56, countdown in the menu bar"></p>

<p align="center"><sub>Unlocked laptop + countdown = your Mac is pulling an all-nighter on purpose.</sub></p>

## Features

- **One-click toggle.** 🔒 Locked laptop = normal Mac, sleeps when you close it. 🔓 Unlocked laptop = lid-proof insomniac Mac.
- **Optional timer.** "Stay on for 2 hours" then it puts itself to bed. The countdown sits right in the menu bar.
- **Low-battery safety net.** Unplugged and down to 10%? It turns itself off so your Mac can sleep instead of dying in your backpack.
- **Overheat safety net.** If macOS says the machine is overheating (the fans-maxed, throttling kind of hot), it turns itself off so a closed Mac can sleep and cool down.
- **Quitting turns it off.** You can't accidentally leave your Mac on for three weeks by force-quitting.
- **Survives restarts.** If the timer ran out while the app was closed, it turns off the moment it opens again.
- **Stays honest.** If you flip the setting from Terminal, the icon notices within 10 seconds.
- **~200 lines of Swift.** No Electron, no dependencies, no telemetry, no subscription, no "Pro" tier. You can read the whole thing on the toilet. Again, no judgement.

## Install

You need macOS 14+ and the Xcode Command Line Tools (`xcode-select --install`). Then:

```bash
git clone https://github.com/hazy2go/lidawake.git
cd lidawake
./build.sh
open ~/Applications/LidAwake.app
```

The first time you turn it on, macOS asks for your password **once**. After that it toggles with no prompts. To open it automatically, tick **Launch at Login** in the menu.

## How it works (aka "is this sketchy?")

Fair question. The app is a nice face on one built-in command:

```bash
sudo pmset -a disablesleep 1   # stay awake, lid closed or not
sudo pmset -a disablesleep 0   # back to normal
```

That needs root, and nobody wants to type a password every time. So on first use LidAwake shows the standard macOS admin prompt and installs **one** sudoers rule at `/etc/sudoers.d/lidawake`:

```
youruser ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
```

That rule allows **exactly those two commands, with exactly those arguments**, for your user only. Nothing else gets password-free root. The install is careful about it:

- the staging file is made by `mktemp` inside `/etc/sudoers.d/` as root (unguessable name, and sudo ignores files with a `.` in the name while staging)
- it's checked with `visudo -c` before going live, so a broken rule can't lock you out of sudo
- then it's moved into place in one atomic step
- your username is checked against `[A-Za-z0-9_.-]` before it goes anywhere near a sudoers file

The app never stores your password and never sees it. The macOS dialog handles that.

## ⚠️ Read this, seriously

- **Don't put it in a bag while it's on.** A closed, running laptop in a backpack gets hot. It turns itself off if macOS reports overheating, but that is a last resort, not a plan. Use the timer.
- **The display still turns off** when you close the lid. Only sleep is blocked.
- `disablesleep` is a system setting that **survives reboots**. If you delete the app while it's on, the setting stays on. Use `./uninstall.sh` and it gets cleaned up.
- Logging out or a crash doesn't turn it off (only Quit does). The next time the app opens, it picks up where it left off and enforces any expired timer.

## Uninstall

```bash
./uninstall.sh
```

Turns sleep back on, removes the sudoers rule, deletes the app and its settings. Your Mac goes back to passing out the moment you close it, as nature intended.

## FAQ

**Isn't this just `caffeinate`?**
No. `caffeinate` gives up the moment you close the lid. That's the whole problem.

**Isn't this just Amphetamine?**
Spiritually. This one is ~200 lines you can read in five minutes, and it does one thing.

**Will it melt my MacBook?**
Not if it can breathe. Leave it on a desk, not in a duffel bag.

**My agent finished the dashboard. Now what?**
Ask it for another dashboard. That's the cycle. LidAwake doesn't judge either.

## License

MIT. Do whatever. Close your lid with pride.
