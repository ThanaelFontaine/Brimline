# The menu bar: tidy it, or hide icons

*[Version française](menu-bar.fr.md)*

Claude, ChatGPT, Cursor and Gemini each put their own icon in the menu bar, and Brimline already shows where they stand. **Settings, Menu Bar** gives two ways to make room. Neither asks for any permission (no Accessibility, no Screen Recording), uses a private API or writes a file of macOS or of another app.

## 1. Remove an icon for good (tidy up)

For each of Claude, ChatGPT and Cursor installed on the Mac, the tab names the app's own switch ("Turn off “Menu bar”" in Claude, "Show in menu bar" in ChatGPT, "Menu Bar Icon" in Cursor), says where it is and opens the app. It also opens System Settings on Menu Bar, where macOS has its own "Allow in the Menu Bar" switch for each app, and explains the Command-drag out of the menu bar. The names of the switches are the ones read in the apps on 27 October 2026 and can change with their versions.

Brimline cannot remove another app's icon itself: macOS leaves that choice to each app, and to you.

## 2. Hide icons without removing them

**Off by default.** Turn on **Settings, Menu Bar, Hide without removing, "Hide the icons placed left of the bar"**.

<p align="center">
  <img src="images/menubar-hiding-gesture-light.png" width="600" alt="Three menu bars: Brimline's bar left of the icons; after the Command-drag, Claude, ChatGPT, Cursor and Gemini left of the bar; after a click on the bar, they are gone, the bar is an arrow « and Brimline stays">
</p>

1. **The bar appears.** Brimline adds one item of its own to the menu bar: a thin vertical bar. The first time, it lands left of the other icons (macOS puts a new item there).
2. **Once, the gesture.** Hold Command and drag, in the menu bar, each icon to hide (Claude, ChatGPT, Cursor, Gemini) to the left of the bar. macOS remembers the place of every icon, the bar's too, from one launch to the next.
3. **Hide and show.** A click on the bar hides everything left of it, and the bar becomes an arrow «, right beside the icons that stay; a click on the arrow brings them back. In the Brimline window, **"Hide the icons"** and **"Show the hidden icons"** do the same; the same button is in Settings.

<p align="center">
  <img src="images/settings-menuBar-hiding-light.png" width="520" alt="Settings, Menu Bar, Hide without removing: the switch, the gesture to make once, the Hide the icons button and the note on the technique">
</p>

### How it works

Brimline never touches another app's icon. To hide, it makes **its own bar** very long: the bar grows to the left and pushes the icons beside it out of the visible part of the menu bar, where macOS does not draw them. To show them, the bar gets its normal length back. Hidden Bar and Dozer used this technique before macOS 27.

**Apple does not document it.** It was tried on **macOS 27.0.1, on a 1920 pt screen without a notch** (28 October 2026). It was **not tried on a MacBook with a notch, nor with several screens**, nor across sleep and lock. A later version of macOS could break it; Brimline should then hide nothing, and every icon should stay shown (not tried).

What the tries showed, and what Brimline does with it:

- The length must stay under about half of the screen: from 960 pt (on 1920), macOS takes the bar out and hides nothing (the 10,000 pt of Hidden Bar no longer works on macOS 27). The limit was the same at the two places measured: with the bar at 838 pt, 940 pt pushed and 960 pt got the bar taken out; with the bar at 1512 pt (28 October 2026), 900 to 940 pt pushed and 950 pt got it taken out. Other places were not tried. Brimline uses **48 % of the narrowest screen** on macOS 27 and later (921 pt on 1920), computed again each time a screen comes, goes or changes size (the icons are shown, the bar settles, then the check runs again). On macOS 26 and before, it keeps the length of Hidden Bar.
- An icon pushed onto the menus of the app in front is not drawn; one that still fits beside them stays shown. So when the bar is far right (its left edge more than 48 % of the screen plus 50 pt from the left), the push may leave the icons nearest the bar shown, more of them with an app whose menus are short. Brimline still hides what it can, and the menu bar window and the Menu Bar tab of Settings say: "The icons closest to the bar may stay visible: macOS lets the bar push them by about half the screen only. Keep only the icons to hide left of the bar (hold Command and drag the others to its right): the bar then sits further left and pushes them all out." Tried on 28 October 2026 with the bar at 1512 pt and Finder or Claude in front, by real clicks in the menu bar window, and with Settings in front: the icons nearest the bar (two of them) stayed visible, moved left, and the others were hidden; a « sign appeared in their place. Up to version 0.2.1, it refused to hide in that case.
- While the icons are hidden, the bar is drawn as an arrow « at the right end of the long item: it stays where you put it, beside the icons that stay shown, and a click on it shows the hidden icons. macOS may also show a « of its own right after the menus of the app in front, as soon as it has icons it does not draw: a click on it shows them in place of those menus. That one belongs to macOS, and Brimline cannot move it. Both were seen on 28 October 2026 with the bar at 1442 pt.
- No signal says that the icons really left the menu bar: Brimline reads its bar's place only while the icons are shown, and refuses when it cannot read it.

### You always get your icons back

- **Brimline stays right of the bar, so it is never hidden**, and neither is its window with the "Show the hidden icons" button. The bar is put in after Brimline's own icon, so it lands left of it; and before each hiding Brimline checks that its own icon is right of the bar, and refuses otherwise ("Brimline's icon is left of the bar: drag it right of the bar, or it would be hidden too."). After a click on the bar, a refusal opens Settings on Menu Bar, where it is written.
- **Turning the setting off** shows every icon and takes the bar out of the menu bar: when the setting is off, there is no bar at all.
- **Quitting Brimline** brings every icon back: the bar belongs to Brimline's process and leaves with it. After a crash it should be the same, by design (the bar goes away with the app), not tried. At each launch the icons start shown, even when they were hidden at the last quit.
- **Opening Brimline again** (Finder, Spotlight) shows the hidden icons, and opens the settings: a way back that does not depend on the menu bar.
- The bar cannot be dragged out of the menu bar, and it never quits Brimline.

### What it leaves behind

The place of the bar is kept by macOS, like the place of every icon you drag (on macOS 27, in its own Menu Bar preferences, under the name of Brimline's executable and `brimline-separator`). Brimline never writes that file. Brimline may also appear in System Settings, Menu Bar, Allow in the Menu Bar, like any app with an icon. Whether turning the setting off and on again keeps the bar's place was not checked: if the bar comes back at the left of the icons, make the gesture again.
