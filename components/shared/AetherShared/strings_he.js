.pragma library

// Hebrew for every string the island shows. Key = the English text exactly as written in the QML.
var dict = {
    // tiles
    "Wi‑Fi": "Wi‑Fi", "Bluetooth": "Bluetooth", "Night": "לילה", "Dark": "כהה", "Airplane": "טיסה", "Awake": "מסך דולק",
    "Mic": "מיקרופון", "Saver": "חיסכון", "Capture": "צילום", "Record": "הקלטה", "Area": "אזור",
    "Night Light": "תאורת לילה", "Dark theme": "ערכה כהה", "Airplane mode": "מצב טיסה", "Keep awake": "השארת המסך דולק",
    "Microphone": "מיקרופון", "Power saver": "חיסכון בחשמל", "Screenshot": "צילום מסך", "Screen record": "הקלטת מסך",
    "Off": "כבוי", "On": "פועל", "Muted": "מושתק", "Not connected": "לא מחובר", "%1 connected": "%1 מחוברים",
    "Available": "זמינות", "Done": "סיום", "Reset": "איפוס",
    // island
    "Time's up": "הזמן נגמר", "Desktop": "שולחן עבודה", "%1 min": "%1 דק׳",
    "NOTIFICATIONS": "התראות", "Clear": "נקה", "No notifications": "אין התראות",
    "Nothing playing": "שום דבר לא מושמע", "now": "עכשיו", "%1m": "לפני %1 דק׳",
    // shared
    "Show": "הצג", "Hide": "הסתר", "Copied": "הועתק",
    // Wi-Fi
    "Network details": "פרטי הרשת", "No Wi‑Fi adapter": "אין כרטיס Wi‑Fi", "Connecting to %1": "מתחבר אל %1",
    "Sign in required · %1": "נדרשת התחברות · %1", "Connected · %1": "מחובר · %1", "Wi‑Fi settings ↗": "הגדרות Wi‑Fi ↗",
    "Scan": "סריקה", "Wi‑Fi is off": "Wi‑Fi כבוי", "No Wi‑Fi adapter found": "לא נמצא כרטיס Wi‑Fi", "Turn on": "הפעלה",
    "Sign in to network": "התחברות לרשת", "Connected, no internet": "מחובר, ללא אינטרנט", "Connected": "מחובר",
    "Sign in": "התחברות", "Details": "פרטים", "Disconnect": "ניתוק", "Saved networks": "רשתות שמורות",
    "Show fewer": "הצג פחות", "Show all saved (%1)": "הצג את כל השמורות (%1)", "Looking for networks…": "מחפש רשתות…",
    "No networks found": "לא נמצאו רשתות", "Tap again to forget": "הקש שוב כדי לשכוח", "Forget network": "שכח רשת",
    "Needs system settings": "דורש הגדרות מערכת", "Out of range": "מחוץ לטווח", "Saved": "שמור", "Open": "פתוח",
    "Password": "סיסמה", "Connecting…": "מתחבר…", "Connect": "התחבר", "Cancel": "ביטול",
    "Authenticating…": "מאמת…", "Getting address…": "מקבל כתובת…", "Checking internet…": "בודק אינטרנט…",
    "Wrong password. Try again.": "הסיסמה שגויה. נסה שוב.", "Enter the password": "הזן סיסמה",
    "No IP address — try again or move closer": "אין כתובת IP — נסה שוב או התקרב", "Network not found": "הרשת לא נמצאה",
    "Couldn't connect": "לא ניתן להתחבר", "Couldn't start the connection": "לא ניתן להתחיל את החיבור",
    "Network didn't respond": "הרשת לא הגיבה", "This network type needs the system settings": "סוג רשת זה דורש את הגדרות המערכת",
    "Security": "אבטחה", "Signal": "עוצמת אות", "Frequency": "תדר", "Link speed": "מהירות חיבור", "IP address": "כתובת IP",
    "Gateway": "שער", "DNS": "DNS", "MAC address": "כתובת MAC",
    "Back on %1": "חזרה אל %1", "Connect automatically": "התחבר אוטומטית", "Reconnects by itself when it is in range": "מתחבר מחדש מעצמו כשהוא בטווח",
    "Password needed": "נדרשת סיסמה", "Paused until you connect it again": "מושהה עד שתחבר אותו שוב", "Saved · manual": "שמור · ידני",
    // Bluetooth
    "Device": "מכשיר", "Device details": "פרטי המכשיר", "No Bluetooth adapter": "אין מתאם Bluetooth",
    "Visible as “%1” while this panel is open": "גלוי בשם “%1” כל עוד החלון פתוח", "Bluetooth settings ↗": "הגדרות Bluetooth ↗",
    "Pairing…": "מצמיד…", "Battery %1%": "סוללה %1%", "Tap to pair": "הקש כדי להצמיד", "Bluetooth is off": "הBluetooth כבוי",
    "No Bluetooth adapter found": "לא נמצא מתאם Bluetooth", "Confirm that %1 shows this code": "ודא ש‑%1 מציג את הקוד הזה",
    "Type %1 on %2, then press Enter": "הקלד %1 ב‑%2 ולחץ Enter", "%1 wants to connect": "%1 מבקש להתחבר",
    "Enter the code for %1": "הזן את הקוד של %1", "Code": "קוד", "Pair": "הצמד", "Allow": "אפשר",
    "Saved devices": "מכשירים שמורים", "Pair new device": "הצמדת מכשיר חדש", "Looking for devices…": "מחפש מכשירים…",
    "Status": "מצב", "Battery": "סוללה", "Type": "סוג", "Address": "כתובת", "Name": "שם", "Rename": "שנה שם",
    "Forget device": "שכח מכשיר", "Pairing failed": "ההצמדה נכשלה", "Paired, but couldn't connect": "הוצמד, אך לא ניתן להתחבר",
    // Sound
    "Sound": "שמע", "No output device": "אין התקן פלט", "Unmute": "בטל השתקה", "Mute": "השתק", "Sound settings ↗": "הגדרות שמע ↗",
    "Output": "פלט", "Input": "קלט", "Apps": "אפליקציות", "%1 · paused": "%1 · מושהה",
    // Battery
    "No battery": "אין סוללה", "Power settings ↗": "הגדרות צריכת חשמל ↗", "Balanced": "מאוזן", "Performance": "ביצועים",
    "Longest battery life, reduced performance": "הסוללה מחזיקה הכי הרבה, ביצועים מופחתים",
    "Good performance, normal battery life": "ביצועים טובים, חיי סוללה רגילים",
    "Fastest, uses more power and runs warmer": "הכי מהיר, צורך יותר חשמל ומתחמם",
    " · limited by heat": " · מוגבל בגלל חום", "Charging": "בטעינה", "On battery": "על סוללה", "Full": "מלאה",
    "Power mode": "מצב צריכת חשמל", "Battery health": "בריאות הסוללה", "Fully charged": "טעונה במלואה",
    "Full in %1": "מלאה בעוד %1", "%1 h %2 min": "%1 שע׳ %2 דק׳", "%1 left": "נותרו %1",
    // Display
    "Display": "תצוגה", "Display settings ↗": "הגדרות תצוגה ↗", "Warmer colors in the evening": "צבעים חמים יותר בערב",
    "Warmth": "חום", "Theme": "ערכת נושא", "Light": "בהיר",
    // Calendar
    "Hebrew dates: %1": "תאריך עברי: %1",
    // Power
    "Power": "אפשרויות כיבוי", "Tap twice to restart, shut down or log out": "הקש פעמיים כדי להפעיל מחדש, לכבות או להתנתק",
    "Lock": "נעילה", "Sleep": "שינה", "Restart": "הפעלה מחדש", "Tap to restart": "הקש להפעלה מחדש", "Shut down": "כיבוי",
    "Tap to shut down": "הקש לכיבוי", "Log out": "התנתקות", "Tap to log out": "הקש להתנתקות", "Firmware setup": "הגדרות קושחה"
}
