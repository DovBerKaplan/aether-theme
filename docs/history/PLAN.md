# תוכנית: KDE Plasma בעיצוב AetherOS (Liquid Glass) מ-Stitch

## הקשר
המשתמש רוצה ששולחן העבודה שלו ייראה כמו פרויקט Stitch "Liquid Glass Linux OS" (‏AetherOS). בפרויקט יש 10 מסכים: Desktop+Dock, Files, Control Center, Terminal/Monitor. יש גרסה כהה (Glass) וגרסה בהירה (Serenity).
- **כהה (Glass):** רקע `#10131a`, משטחים `#0b0e14` בשקיפות 65–80% עם `backdrop-blur-2xl`, צבע ראשי ציאן `#00f2fe` עם זוהר, משני סגול `#4e1dbe`/`#cdbdff`, טקסט `#e1e2eb`, גופן Inter, גופן JetBrains Mono לשעון ולקוד, פינות 12–16px. ברקע יש "כתמי" ציאן וסגול מטושטשים.
- **בהיר (Serenity):** מונוכרום. רקע `#f8f9fa`, משטחים לבנים, הדגשה כמעט שחורה `#1a1d20`, טקסט `#191c1d`/`#595f65`, קווי מתאר `#c5c6ca`.
- **פריסה:** פאנל עליון צף ומעוגל מזכוכית (לוגו, workspaces בצורת pills, תאריך ושעה עם שניות, מגש מערכת), Dock תחתון צף בצורת pill, ווידג'טים (טלמטריה, מזג אוויר, פתקים), טרמינל שקוף.

החלטות המשתמש: **שתי הגרסאות עם החלפה אוטומטית** · **Kvantum Qt6 מ-PPA של Papirus** · היקף: **בסיס + טרמינל + ווידג'טים + מרכז בקרה**.

## מצב המערכת (נבדק)
- KDE neon, ‏Plasma/KWin **6.6.2**, ‏session **X11**, ‏Intel Iris Xe. החלפה אוטומטית של Global Theme לפי יום/לילה קיימת מ-Plasma 6.5.
- Kvantum מותקן **רק ל-Qt5** (`qt5-style-kvantum`), ולכן ה-theme הנוכחי `KvGlassWhiteSur` לא משפיע על אפליקציות Plasma 6. ב-apt של neon אין `qt6-style-kvantum`.
- גופנים: JetBrainsMono Nerd Font מותקן. Inter לא מותקן (`fonts-inter` זמין ב-apt).
- כבר מותקנים: Kvantum theme `LiquidGlass`, ‏desktoptheme `Blur-Glassy`/`KDE-Story`, אייקונים `Papirus-Dark/Light`, plasmoids `KdeControlStation` (v2.11, Plasma 6) ו-`AndromedaLauncher`.
- פאנל נוכחי: פאנל אנכי צף אחד (containment 2), עובי 50. שולחן עבודה אחד.
- `conky-all` זמין אבל לא נדרש, כי משתמשים בווידג'טים מובנים של Plasma.

## גישה
**תיקיית פרויקט ייעודית:** הצעד הראשון בביצוע הוא ליצור את `~/aether-theme/` כ-git repo חדש (`git init`, עם README קצר ו-`.gitignore` לגיבויים), ולהעביר אליה את ה-session (`change_directory`). כך העבודה לא נוגעת ב-temper-detection. מבנה: `src/` (color-schemes, desktoptheme, kvantum, look-and-feel, konsole, wallpaper), ‏`scripts/` (install, restore, layout.js, gen-wallpaper.py, aether-mode-sync), ‏`backups/` (ב-gitignore).

`scripts/install.sh` מעתיק ל-`~/.local/share` ומגדיר באמצעות `kwriteconfig6`/`plasma-apply-*`. אין שינויים בקבצי מערכת, חוץ מ-apt.

### 0. גיבוי
`~/aether-theme/backup-<date>.tar.gz` עם: `kdeglobals`, `kwinrc`, `plasmarc`, `plasmashellrc`, `plasma-org.kde.plasma.desktop-appletsrc`, `Kvantum/`, `konsolerc`, `~/.local/share/konsole/`, `kcminputrc`. בנוסף `restore.sh` שמחזיר את הכול ומפעיל מחדש את plasmashell.

### 1. חבילות (sudo, באישור המשתמש)
`add-apt-repository ppa:papirus/papirus` → `qt6-style-kvantum qt5-style-kvantum fonts-inter`. לוודא ש-`kdeplasma-addons` מותקן (בשביל weather ו-notes).

### 2. ערכות צבעים
`~/.local/share/color-schemes/AetherGlass.colors` ו-`AetherSerenity.colors`. ממפים את טוקני ה-Material מ-Stitch לתפקידי KDE: Window, View, Button, Selection, Tooltip, Header. ‏Selection/Focus יהיו ציאן `#00f2fe` בכהה ו-`#1a1d20` בבהיר. ה-colors של GTK (Breeze-GTK דרך `kde-config-gtk-style`) יעקבו אחרי הערכה אוטומטית.

### 3. Plasma desktop theme `AetherGlass`
מבוסס על `Blur-Glassy` המותקן: מעתיקים, משנים שם ו-metadata, ומעגלים את ה-SVG של `widgets/panel-background`, `dialogs/background` ו-`solid/` ל-radius של 12–16px עם רקע שקוף ו-`blurbehind`. **בלי קובץ `colors`**, כדי שה-theme יעקוב אחרי ערכת הצבעים הפעילה ויעבוד בשני המצבים.

### 4. Kvantum themes ‏`AetherGlass` ו-`AetherSerenity`
מבוססים על `~/.config/Kvantum/LiquidGlass`: משנים צבעים בקובץ `.kvconfig` וב-SVG, ומגדירים `translucent_windows=true`, ‏`blurring=true`, ‏`reduce_window_opacity≈15`, ‏`popup_blurring=true`, פינות מעוגלות ו-menu shadows. ‏`widgetStyle=kvantum` ב-kdeglobals.

### 5. Global themes (look-and-feel) ומעבר אוטומטי
`~/.local/share/plasma/look-and-feel/org.aether.glass.desktop` ו-`org.aether.serenity.desktop`: ‏`defaults` עם color scheme, desktop theme, אייקונים (`Papirus-Dark` / `Papirus-Light`), cursor (`Breeze_Light` / `breeze_cursors`), widget style kvantum, ודקורציית חלון Breeze, שמקבלת את הצבעים מה-scheme. ההחלה עם `plasma-apply-lookandfeel` **בלי layout** (כדי לא לדרוס את הפאנלים). מעבר יום/לילה דרך הגדרות Global Theme (Plasma ≥6.5): ‏Light=Serenity, ‏Dark=Glass. את מפתחות `kdeglobals` המדויקים נבדוק בזמן הביצוע.

**מתג משלים** (Kvantum ו-Konsole לא עוקבים אחרי Global Theme): `~/.local/bin/aether-mode-sync` יחד עם systemd user `.path` unit שצופה ב-`~/.config/kdeglobals`. כשמשתנה `ColorScheme`, הסקריפט מריץ `kvantummanager --set AetherGlass|AetherSerenity` ומעדכן את `ColorScheme=` בפרופיל ה-Konsole.

### 6. גופנים ו-KWin
- גופנים (`kwriteconfig6 kdeglobals [General]`): ‏`font=Inter,10`, ‏`menuFont`/`toolBarFont=Inter`, ‏`smallestReadableFont=Inter,8`, ‏`fixed=JetBrainsMono Nerd Font,10`.
- KWin: ‏`[Plugins] blurEnabled=true`, ‏`[Effect-blur] BlurStrength≈10`, ‏NoiseStrength נמוך. בנוסף 4 virtual desktops בשמות `Workspace 1–4`.
- פינות מעוגלות לחלונות (אופציונלי, לפי התוצאה): אפקט KDE-Rounded-Corners שנבנה מקוד מקור מול KWin 6.6.2. ייעשה רק אם אחרי שאר השלבים החלונות עדיין נראים מרובעים.

### 7. רקע
חבילת wallpaper `~/.local/share/wallpapers/AetherOS/` עם `contents/images/` (בהיר) ו-`contents/images_dark/` (כהה). כך Plasma 6 מחליף רקע אוטומטית לפי המצב. התמונות ייווצרו ב-Python או ImageMagick ב-1920x1080 וב-3840x2160, בשחזור של הכתמים המטושטשים מה-HTML. בכהה: ציאן 10% ב-`-25%/-15%`, סגול 20% מימין, tint 10% למטה, על `#10131a`. בבהיר: גרדיאנט אפור רך.

### 8. פאנלים (סקריפט Plasma JS דרך `qdbus6 org.kde.plasmashell /PlasmaShell evaluateScript`)
מסירים את הפאנל האנכי (containment 2) ומוסיפים:
- **עליון, צף:** גובה ~44, ‏`floating=1`. בתוכו: ‏`AndromedaLauncher` (או kickoff עם אייקון לוגו), ‏`org.kde.plasma.pager` (תצוגת שמות כ-pills), spacer, ‏`digitalclock` (תאריך מעל שעה עם שניות, גופן JetBrains Mono), ‏systemtray ו-`KdeControlStation`.
- **תחתון, Dock צף:** ‏`lengthMode=fit`, ממורכז, ‏`icontasks` בלבד עם אייקונים גדולים (≈48), עם האפליקציות המוצמדות מהעיצוב: ‏Dolphin, ‏Konsole, ‏System Monitor, ‏Chrome, ‏VS Code, ‏System Settings.

### 9. טרמינל (Konsole)
`~/.local/share/konsole/AetherGlass.colorscheme` ו-`AetherSerenity.colorscheme` (16 צבעי ANSI, עם ציאן וסגול כ-accent), ו-`Aether.profile` עם JetBrainsMono NF 11, ‏`Opacity=0.78` + Blur, margin 12. יוגדר כ-`DefaultProfile` ב-`konsolerc`.

### 10. ווידג'טים על שולחן העבודה (אותו סקריפט JS, על containment 1)
- טלמטריה: ‏`org.kde.plasma.systemmonitor` עם CPU%, תדר, RAM, טמפ' ורשת (faces מסוג text/line).
- מזג אוויר: ‏`org.kde.plasma.weather` לתל אביב.
- פתקים: ‏`org.kde.plasma.notes` ("Pinned Scratchpad").
- סידור בעמודה ימנית/עליונה כמו בעיצוב. רקע הווידג'טים בא מה-desktop theme, כלומר זכוכית.

### 11. מרכז בקרה
הגדרת `KdeControlStation` בפאנל העליון: שקיפות, פינות ואייקונים תואמים, וכפתורי Wi-Fi, Bluetooth, ‏Dark mode, ‏Volume ו-Brightness, כמו במסך "Control Center & Quick Settings".

## קבצים עיקריים
- `~/aether-theme/{install.sh,restore.sh,layout.js,gen-wallpaper.py}`
- `~/.local/share/{color-schemes,plasma/desktoptheme/AetherGlass,plasma/look-and-feel/org.aether.*,wallpapers/AetherOS,konsole}/…`
- `~/.config/Kvantum/{AetherGlass,AetherSerenity}/`
- `~/.local/bin/aether-mode-sync`, ‏`~/.config/systemd/user/aether-mode-sync.{path,service}`
- הגדרות: ‏`kdeglobals`, ‏`kwinrc`, ‏`plasma-org.kde.plasma.desktop-appletsrc`, ‏`konsolerc`

## אימות
1. צילום מסך עם `spectacle -b -n -f -o /tmp/aether-dark.png`, והשוואה ויזואלית למסך Stitch "AetherOS Desktop Workspace & Dock".
2. מעבר ידני ל-Serenity (`plasma-apply-lookandfeel -a org.aether.serenity.desktop`), ובדיקה ש-Kvantum, ‏Konsole והרקע מתחלפים אחרי בערך 2 שניות. צילום והשוואה ל-"AetherOS Serenity Desktop - Light Mode".
3. פתיחת Dolphin, ‏System Settings ו-Konsole, ובדיקה שיש שקיפות וטשטוש ושהטקסט קריא בשני המצבים.
4. `systemctl --user status aether-mode-sync.path` פעיל. ‏`journalctl --user -u aether-mode-sync` בלי שגיאות.
5. `plasmashell --replace` או logout/login, ובדיקה שהכול נשמר.
6. בדיקת `restore.sh` בתחילת הביצוע, על הגיבוי, כדי לוודא שאפשר לחזור.

## הערות
- הטשטוש ב-X11 עובד, אבל ב-Wayland הוא חלק יותר. מעבר ל-Wayland session הוא אופציונלי ולא חלק מהתוכנית.
- אפליקציות Electron/Chrome לא יקבלו שקיפות. הן ייראו כהות או בהירות לפי ערכת ה-GTK.
