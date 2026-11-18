.pragma library
// The split-view tree of the console shelf. Pure functions: every operation returns a new
// tree and never touches its input (QML var properties only notify on reassignment).
//   leaf  { t: "leaf", group: id }
//   split { t: "split", dir: "row" | "col", sizes: [fractions, sum 1], kids: [node, ...] }
// "row" = kids side by side, "col" = kids stacked.

var MIN_W = 260;
var MIN_H = 160;

function clone(n) { return JSON.parse(JSON.stringify(n)); }
function leaf(group) { return { t: "leaf", group: group }; }

function nodeAt(tree, path) {
    var n = tree;
    for (var i = 0; i < path.length; ++i) n = n.kids[path[i]];
    return n;
}
function findPath(tree, group) {
    if (!tree) return null;
    if (tree.t === "leaf") return tree.group === group ? [] : null;
    for (var i = 0; i < tree.kids.length; ++i) {
        var p = findPath(tree.kids[i], group);
        if (p) return [i].concat(p);
    }
    return null;
}
function groupsIn(tree) {
    if (!tree) return [];
    if (tree.t === "leaf") return [tree.group];
    var out = [];
    tree.kids.forEach(function (k) { out = out.concat(groupsIn(k)); });
    return out;
}

function splitGroup(tree, group, side, newGroup) {
    var t = clone(tree);
    var dir = (side === "left" || side === "right") ? "row" : "col";
    var before = side === "left" || side === "top";
    var path = findPath(t, group);
    if (!path) return t;
    var fresh = leaf(newGroup);
    var self = nodeAt(t, path);
    if (path.length > 0) {
        var parent = nodeAt(t, path.slice(0, -1));
        var i = path[path.length - 1];
        if (parent.dir === dir) {
            var half = parent.sizes[i] / 2;
            parent.sizes[i] = half;
            parent.sizes.splice(before ? i : i + 1, 0, half);
            parent.kids.splice(before ? i : i + 1, 0, fresh);
            return t;
        }
        parent.kids[i] = { t: "split", dir: dir, sizes: [0.5, 0.5], kids: before ? [fresh, self] : [self, fresh] };
        return t;
    }
    return { t: "split", dir: dir, sizes: [0.5, 0.5], kids: before ? [fresh, self] : [self, fresh] };
}

// Collapses one-kid splits and merges a split into a same-direction parent.
function normalize(n) {
    if (n.t === "leaf") return n;
    var kids = [], sizes = [];
    for (var i = 0; i < n.kids.length; ++i) {
        var k = normalize(n.kids[i]);
        if (k.t === "split" && k.dir === n.dir) {
            for (var j = 0; j < k.kids.length; ++j) { kids.push(k.kids[j]); sizes.push(n.sizes[i] * k.sizes[j]); }
        } else { kids.push(k); sizes.push(n.sizes[i]); }
    }
    return kids.length === 1 ? kids[0] : { t: "split", dir: n.dir, sizes: sizes, kids: kids };
}
function closeGroup(tree, group) {
    var t = clone(tree);
    var path = findPath(t, group);
    if (!path) return t;
    if (path.length === 0) return null;
    var parent = nodeAt(t, path.slice(0, -1));
    var i = path[path.length - 1];
    var gift = parent.sizes[i];
    parent.kids.splice(i, 1);
    parent.sizes.splice(i, 1);
    parent.sizes[i > 0 ? i - 1 : 0] += gift;
    return normalize(t);
}

function equalize(tree, path, recursive) {
    var t = clone(tree);
    var p = path || [];
    var n = nodeAt(t, p);
    if (n.t === "leaf") { if (p.length === 0) return t; n = nodeAt(t, p.slice(0, -1)); }
    (function eq(x) {
        if (x.t === "leaf") return;
        x.sizes = x.kids.map(function () { return 1 / x.kids.length; });
        if (recursive) x.kids.forEach(eq);
    })(n);
    return t;
}

// Smallest pixel extent a node needs along an axis ("row" = width, "col" = height).
function minExtent(n, axis) {
    if (n.t === "leaf") return axis === "row" ? MIN_W : MIN_H;
    var parts = n.kids.map(function (k) { return minExtent(k, axis); });
    return n.dir === axis ? parts.reduce(function (a, b) { return a + b; }, 0) : Math.max.apply(null, parts);
}
// The smallest the whole layout may get along an axis (gaps included) - the shelf's width
// handle never goes below it.
function minSize(tree, axis, gap) {
    var g = gap === undefined ? 6 : gap;
    if (!tree) return 0;
    if (tree.t === "leaf") return axis === "row" ? MIN_W : MIN_H;
    var parts = tree.kids.map(function (k) { return minSize(k, axis, g); });
    return tree.dir === axis ? parts.reduce(function (a, b) { return a + b; }, 0) + g * (parts.length - 1)
                             : Math.max.apply(null, parts);
}
// How many panes each preset can hold.
var PRESET_SLOTS = { "single": 1, "cols2": 2, "rows2": 2, "grid4": 4, "cols3": 3, "main-side": 3 };
function resize(tree, path, i, deltaFrac, totalPx) {
    var t = clone(tree);
    var n = nodeAt(t, path);
    if (n.t !== "split" || i < 0 || i >= n.kids.length - 1 || totalPx <= 0) return t;
    var a = n.sizes[i], b = n.sizes[i + 1];
    var minA = minExtent(n.kids[i], n.dir) / totalPx;
    var minB = minExtent(n.kids[i + 1], n.dir) / totalPx;
    var d = Math.max(minA - a, Math.min(b - minB, deltaFrac));
    if (minA + minB > a + b) return t;   // no room at all
    n.sizes[i] = a + d;
    n.sizes[i + 1] = b - d;
    return t;
}

function layoutRects(tree, x, y, w, h, gap) {
    var g = gap === undefined ? 6 : gap;
    if (!tree) return [];
    if (tree.t === "leaf") return [{ group: tree.group, x: Math.round(x), y: Math.round(y), w: Math.round(w), h: Math.round(h) }];
    var row = tree.dir === "row";
    var room = (row ? w : h) - g * (tree.kids.length - 1);
    var out = [], pos = row ? x : y;
    for (var i = 0; i < tree.kids.length; ++i) {
        var ext = room * tree.sizes[i];
        out = out.concat(row ? layoutRects(tree.kids[i], pos, y, ext, h, g)
                             : layoutRects(tree.kids[i], x, pos, w, ext, g));
        pos += ext + g;
    }
    return out;
}
// One draggable divider per gap between siblings: where it sits, which split it belongs to
// (path), the kid index on its left/top, and the split's pixel extent along its axis.
function dividers(tree, x, y, w, h, gap, path) {
    var g = gap === undefined ? 6 : gap;
    var p = path || [];
    if (!tree || tree.t === "leaf") return [];
    var row = tree.dir === "row";
    var room = (row ? w : h) - g * (tree.kids.length - 1);
    var out = [], pos = row ? x : y;
    for (var i = 0; i < tree.kids.length; ++i) {
        var ext = room * tree.sizes[i];
        var kx = row ? pos : x, ky = row ? y : pos, kw = row ? ext : w, kh = row ? h : ext;
        out = out.concat(dividers(tree.kids[i], kx, ky, kw, kh, g, p.concat([i])));
        if (i < tree.kids.length - 1) {
            out.push({ path: p, i: i, dir: tree.dir, extent: room,
                       x: Math.round(row ? pos + ext : x), y: Math.round(row ? y : pos + ext),
                       w: Math.round(row ? g : w), h: Math.round(row ? h : g) });
        }
        pos += ext + g;
    }
    return out;
}
function canSplit(tree, group, side, w, h, gap) {
    var rects = layoutRects(splitGroup(tree, group, side, "\u0000new"), 0, 0, w, h, gap);
    return rects.every(function (r) { return r.w >= MIN_W && r.h >= MIN_H; });
}

// The adjacent pane in a direction: touching on that side, most overlap on the other axis.
function neighbor(tree, group, dir, w, h) {
    var rects = layoutRects(tree, 0, 0, w, h, 0);
    var me = rects.filter(function (r) { return r.group === group; })[0];
    if (!me) return null;
    var best = null, bestOv = 0, bestDist = 1e9;
    rects.forEach(function (r) {
        if (r === me) return;
        var dist, ov;
        if (dir === "left") { dist = me.x - (r.x + r.w); ov = Math.min(me.y + me.h, r.y + r.h) - Math.max(me.y, r.y); }
        else if (dir === "right") { dist = r.x - (me.x + me.w); ov = Math.min(me.y + me.h, r.y + r.h) - Math.max(me.y, r.y); }
        else if (dir === "up") { dist = me.y - (r.y + r.h); ov = Math.min(me.x + me.w, r.x + r.w) - Math.max(me.x, r.x); }
        else { dist = r.y - (me.y + me.h); ov = Math.min(me.x + me.w, r.x + r.w) - Math.max(me.x, r.x); }
        if (dist < -1 || ov <= 0) return;
        if (dist < bestDist - 1 || (Math.abs(dist - bestDist) <= 1 && ov > bestOv)) { best = r.group; bestOv = ov; bestDist = dist; }
    });
    return best;
}

// Ready-made layouts. With fewer ids than slots the shape degrades to what fits:
// grid4 with 3 ids = two columns, the left one split in two; with 2 = cols2; main-side with 2 = cols2.
function preset(name, ids) {
    var n = ids.length;
    if (n === 0) return null;
    function row(list, sizes) { return list.length === 1 ? list[0] : { t: "split", dir: "row", sizes: sizes || list.map(function () { return 1 / list.length; }), kids: list }; }
    function col(list) { return list.length === 1 ? list[0] : { t: "split", dir: "col", sizes: list.map(function () { return 1 / list.length; }), kids: list }; }
    var L = ids.map(leaf);
    if (name === "single" || n === 1) return L[0];
    if (name === "cols2") return row(L.slice(0, 2));
    if (name === "rows2") return col(L.slice(0, 2));
    if (name === "cols3") return row(L.slice(0, 3));
    if (name === "grid4") {
        if (n === 2) return row(L.slice(0, 2));
        if (n === 3) return row([col([L[0], L[2]]), L[1]]);
        return row([col([L[0], L[2]]), col([L[1], L[3]])]);
    }
    if (name === "main-side") {
        if (n === 2) return row(L.slice(0, 2), [0.6, 0.4]);
        return row([L[0], col([L[1], L[2]])], [0.6, 0.4]);
    }
    return L[0];
}

if (typeof module !== "undefined") module.exports = { leaf, splitGroup, closeGroup, equalize, resize, findPath, nodeAt, groupsIn, neighbor, preset, MIN_W, MIN_H, layoutRects, canSplit, dividers, minSize, PRESET_SLOTS };
