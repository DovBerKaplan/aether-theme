.pragma library

// Gregorian <-> Hebrew calendar (arithmetic calendar, the one every Hebrew date is computed
// with). Months are numbered from Tishri = 1 inside a year, in civil order; `leap` years have
// Adar I (6) and Adar II (7). Day numbers are Rata Die (1 Jan 1 CE = 1).

var EPOCH = -1373427   // Rata Die of 1 Tishri, year 1

function elapsedDays(y) {
    var m = Math.floor((235 * y - 234) / 19)
    var parts = 12084 + 13753 * m
    var day = m * 29 + Math.floor(parts / 25920)
    if ((3 * (day + 1)) % 7 < 3) day++
    return day
}
function newYear(y) {
    var a = elapsedDays(y - 1), b = elapsedDays(y), c = elapsedDays(y + 1)
    var delay = c - b === 356 ? 2 : (b - a === 382 ? 1 : 0)
    return EPOCH + b + delay
}
function isLeap(y) { return (7 * y + 1) % 19 < 7 }
function yearLength(y) { return newYear(y + 1) - newYear(y) }

// Lengths of the months of year y, in order from Tishri.
function monthLengths(y) {
    var len = yearLength(y)
    var heshvan = len % 10 === 5 ? 30 : 29
    var kislev = len % 10 === 3 ? 29 : 30
    var m = [30, heshvan, kislev, 29, 30]
    if (isLeap(y)) m.push(30, 29)    // Adar I, Adar II
    else m.push(29)                  // Adar
    return m.concat([30, 29, 30, 29, 30, 29])   // Nisan .. Elul
}

function rataDie(year, month0, day) {   // Gregorian, month0 = 0..11
    return Math.floor(Date.UTC(year, month0, day) / 86400000) + 719163
}

// -> { year, month (1 = Tishri), day, leap, monthCount }
function fromGregorian(year, month0, day) {
    var rd = rataDie(year, month0, day)
    var y = Math.floor((rd - EPOCH) / 365.2468) + 1
    while (newYear(y + 1) <= rd) y++
    while (newYear(y) > rd) y--
    var offset = rd - newYear(y)
    var lens = monthLengths(y)
    var m = 0
    while (offset >= lens[m]) { offset -= lens[m]; m++ }
    return { year: y, month: m + 1, day: offset + 1, leap: isLeap(y), monthCount: lens.length }
}

var NAMES = ["תשרי", "חשוון", "כסלו", "טבת", "שבט"]
var AFTER = ["ניסן", "אייר", "סיוון", "תמוז", "אב", "אלול"]
function monthName(y, month) {
    if (month <= 5) return NAMES[month - 1]
    if (isLeap(y)) {
        if (month === 6) return "אדר א׳"
        if (month === 7) return "אדר ב׳"
        return AFTER[month - 8]
    }
    return month === 6 ? "אדר" : AFTER[month - 7]
}

// Hebrew numerals: 15 -> ט״ו, 16 -> ט״ז; with a thousands part when `thousands` is set.
function gematria(n, thousands) {
    var ones = ["", "א", "ב", "ג", "ד", "ה", "ו", "ז", "ח", "ט"]
    var tens = ["", "י", "כ", "ל", "מ", "נ", "ס", "ע", "פ", "צ"]
    var hundreds = ["", "ק", "ר", "ש", "ת", "תק", "תר", "תש", "תת", "תתק"]
    var s = ""
    if (thousands && n >= 1000) { s += ones[Math.floor(n / 1000)] + "׳"; n %= 1000 }
    s += hundreds[Math.floor(n / 100)]
    n %= 100
    if (n === 15) s += "טו"
    else if (n === 16) s += "טז"
    else s += tens[Math.floor(n / 10)] + ones[n % 10]
    if (s.length === 1) return s + "׳"
    return s.slice(0, -1) + "״" + s.slice(-1)
}
function dayLetters(d) { return gematria(d, false) }
function yearLetters(y) { return gematria(y % 1000, false) }

// "י״ז חשוון תשפ״ז"
function format(h) { return dayLetters(h.day) + " " + monthName(h.year, h.month) + " " + yearLetters(h.year) }
