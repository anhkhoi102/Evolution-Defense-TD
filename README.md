# Evolution Defense

![Evolution Defense: a dragon attacks the medieval kingdom](Docs/images/dragon.jpg)

**Build towers. Stop the monsters. Grow from the Stone Age to the future!**

Evolution Defense is a tower defense game for Mac. Monsters walk along a road
toward your village. Build towers beside the road to stop them before they get
there. Your towers grow stronger as you upgrade them. Your village grows too,
from tents to a castle, a factory and a shining future city.

- 🌍 **4 ages:** Stone Age, Medieval, Industrial and Futuristic
- 🐺 **19 kinds of enemies:** wolves, trolls, dragons, mutants and robots
- 👑 **4 big bosses**, one at the end of each age
- 🗺️ **3 battlefields:** Grassland, Desert and Lakeside
- 🏰 **4 kinds of towers** that each grow through 5 levels

---

## 🖥️ What you need

- A **Mac with an Apple chip** (M1, M2, M3, M4 or newer)
- **macOS 14 Sonoma** or newer

Not sure? Click the ** Apple menu** in the top-left corner of the screen and
choose **About This Mac**. Look for **Chip** (it should say *Apple M…*) and
**macOS** (the number should be 14 or higher).

---

## 📥 How to install

> 👋 **Kids:** ask a grown-up to help with step 5. It needs the Mac's password.

**1. Download the game**

Go to the [Releases page](https://github.com/anhkhoi102/Evolution-Defense-TD/releases/latest).
Click **EvolutionDefense.zip** to download it.

**2. Unzip it**

Open your **Downloads** folder. Double-click **EvolutionDefense.zip**. The
**EvolutionDefense** app appears next to it (it has a little floating island
on its icon).

*If you already see the app instead of the zip, Safari unzipped it for you.
Go straight to step 3.*

**3. Move it to Applications**

Drag **EvolutionDefense** onto **Applications** in the left side of the Finder
window.

**4. Open it the first time**

Open **Applications** and double-click **EvolutionDefense**.

The Mac will show a message saying it can't check the app. That's normal for
games that aren't from the App Store. Click **Done** (on some Macs the
button says **Cancel**).

**5. Allow the game (only the first time)**

1. Click the ** Apple menu** and choose **System Settings**.
2. Click **Privacy & Security** in the list on the left.
3. Scroll down until you see a message about **Evolution Defense**.
4. Click **Open Anyway**.
5. Click **Open Anyway** again and type the Mac's password (or use Touch ID).

**6. Play! 🎉**

The game opens. From now on, just double-click it like any other app. You can
also find it in **Launchpad**.

---

## 🎮 How to play

First, pick a battlefield: on the main menu, click **Battlefield** and choose Grassland, Desert or Lakeside. Then:

1. **Pick a tower.** Click a tower card at the bottom of the screen, or press
   **1**, **2**, **3** or **4**.
2. **Build it.** Click one of the round dirt pads beside the road.
3. **Start the wave.** Press **N** or click the big **Start Wave** button. The
   monsters come!
4. **Earn gold.** Every monster you stop gives you gold.
5. **Upgrade.** Click a tower, then click the yellow **Evolve** button to make
   it stronger (or press **U**).
6. **Protect your base.** Don't let monsters reach your village. If its health
   bar runs out, you lose. Survive all 20 waves to win!

| Tower | What it's good at |
|---|---|
| 🧡 **Splash** | Throws rocks and bombs that hit a whole group |
| 💚 **Sniper** | Shoots very far and hits hard |
| ❤️ **Heavy** | Big damage against tough monsters |
| 💙 **Rapid Fire** | Shoots very fast |

**Handy keys**

| Key | What it does |
|---|---|
| **1 2 3 4** | Pick a tower |
| **N** | Start the next wave |
| **Space** | Pause the game |
| **F** | Play faster (2×) |
| **U** | Upgrade the selected tower |
| **T** | Open the technology tree |
| **Q** | Call the Militia (from wave 3) |
| **E** | Summon the Hero (from wave 5) |
| **R** | Repair your base (between waves) |
| **Esc** | Cancel / pause |

**Tips**

- 🛣️ Build towers where the road bends. They can hit monsters for longer there.
- ⬆️ A few upgraded towers beat lots of small ones.
- 🔬 Bosses give **Research Points**. Spend them in the technology tree (**T**).
- ✨ Monsters with a **gold ring** are **elites**: much tougher. Use Heavy towers on them.
- 💚 **Trolls heal** the monsters around them (you'll see a green circle). Stop them first!
- 🧭 The bottom panel tells you what kind of wave is coming (air, armored, swarm…). Get ready for it!
- 🛡️ **Call for help!** During a wave, press **Q** for the Militia or **E** for the Hero, then click on the road. They fight for a few seconds, then need time to recharge. The Hero is great against bosses!
- 😌 Too hard? Choose **Easy** when you start a new game.
- 💾 The game saves by itself between waves. Click **Continue** to keep playing later.

---

## 🗑️ How to uninstall

Drag **EvolutionDefense** from **Applications** to the **Trash**.

---

## 👩‍💻 For grown-ups and developers

Want to build the game yourself? You need **Xcode 27** or newer.

```bash
git clone https://github.com/anhkhoi102/Evolution-Defense-TD.git
cd Evolution-Defense-TD
Scripts/build.sh release --open
```

- [Developer guide](Docs/DEVELOPMENT.md): how the game works, building, testing, balance and controls
- [Asset guide](Docs/ASSETS.md): how the art is made and how to replace it
- [Visual overhaul report](Docs/ART_OVERHAUL_REPORT.md): art direction and performance

## 🙏 Credits

Made with Swift, SwiftUI and SpriteKit.

The 3D models, effects and sounds are free CC0 assets from
[Kenney](https://kenney.nl), [Quaternius](https://quaternius.com) and
[OpenGameArt](https://opengameart.org). The font is
[Lilita One](https://fonts.google.com/specimen/Lilita+One) by Juan Montoreano
(SIL Open Font License). The full list is in
[Docs/ASSET_LICENSES.md](Docs/ASSET_LICENSES.md).
