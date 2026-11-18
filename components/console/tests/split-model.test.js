// node components/console/tests/split-model.test.js
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const src = fs.readFileSync(path.join(__dirname, "../qml/SplitModel.js"), "utf8").replace(/^\.pragma library\n/, "");
const m = { exports: {} };
new Function("module", src)(m);
const S = m.exports;
let n = 0;
const test = (name, fn) => { try { fn(); n++; } catch (e) { console.error("FAIL", name, "\n", e.message); process.exit(1); } };
const sum = a => a.reduce((x, y) => x + y, 0);
const near = (a, b) => assert.ok(Math.abs(a - b) < 1e-9, a + " != " + b);
// runs op on tree and asserts the input was not mutated
const pure = (tree, op) => { const before = JSON.stringify(tree); const r = op(tree); assert.strictEqual(JSON.stringify(tree), before, "input mutated"); return r; };

test("split root, all sides", () => {
    for (const [side, dir, first] of [["left", "row", "n"], ["right", "row", "a"], ["top", "col", "n"], ["bottom", "col", "a"]]) {
        const t = pure(S.leaf("a"), x => S.splitGroup(x, "a", side, "n"));
        assert.strictEqual(t.dir, dir);
        assert.strictEqual(t.kids[0].group, first);
        assert.deepStrictEqual(t.sizes, [0.5, 0.5]);
    }
});
test("same-dir parent inserts sibling and halves target", () => {
    let t = S.splitGroup(S.leaf("a"), "a", "right", "b");
    t = pure(t, x => S.splitGroup(x, "b", "right", "c"));
    assert.deepStrictEqual(S.groupsIn(t), ["a", "b", "c"]);
    assert.deepStrictEqual(t.sizes, [0.5, 0.25, 0.25]);
    t = S.splitGroup(t, "a", "left", "z");
    assert.deepStrictEqual(S.groupsIn(t), ["z", "a", "b", "c"]);
    near(sum(t.sizes), 1);
});
test("nested split with other dir", () => {
    let t = S.splitGroup(S.leaf("a"), "a", "right", "b");
    t = S.splitGroup(t, "b", "bottom", "c");
    assert.strictEqual(t.kids[1].t, "split");
    assert.strictEqual(t.kids[1].dir, "col");
    assert.deepStrictEqual(S.findPath(t, "c"), [1, 1]);
});
test("closeGroup collapses and flattens", () => {
    let t = S.splitGroup(S.leaf("a"), "a", "right", "b");
    t = S.splitGroup(t, "b", "bottom", "c");
    const c1 = pure(t, x => S.closeGroup(x, "c"));
    assert.deepStrictEqual(S.groupsIn(c1), ["a", "b"]);
    assert.strictEqual(c1.t, "split"); assert.strictEqual(c1.kids[1].t, "leaf");
    near(sum(c1.sizes), 1);
    // col inside row inside col: closing the row's other leaf flattens into the root col
    let u = S.splitGroup(S.leaf("a"), "a", "bottom", "b");
    u = S.splitGroup(u, "b", "right", "c");
    const c2 = S.closeGroup(u, "c");
    assert.strictEqual(c2.dir, "col"); assert.strictEqual(c2.kids.length, 2);
    // flatten: col[a, row[b, col[c,d]]] -> close b -> col[a, col[c,d]] -> col[a,c,d]
    let v = S.splitGroup(S.leaf("a"), "a", "bottom", "b");
    v = S.splitGroup(v, "b", "right", "c");
    v = S.splitGroup(v, "c", "bottom", "d");
    const c3 = S.closeGroup(v, "b");
    assert.deepStrictEqual(S.groupsIn(c3), ["a", "c", "d"]);
    assert.strictEqual(c3.kids.length, 3); near(sum(c3.sizes), 1);
});
test("closing the last leaf gives null", () => assert.strictEqual(S.closeGroup(S.leaf("a"), "a"), null));
test("equalize at path and recursive", () => {
    let t = S.splitGroup(S.leaf("a"), "a", "right", "b");
    t = S.splitGroup(t, "b", "right", "c");
    t = S.splitGroup(t, "c", "bottom", "d");
    const e = pure(t, x => S.equalize(x, []));
    near(e.sizes[0], 1 / 3);
    const inner = S.equalize(S.resize(t, [2], 0, 0.1, 400), [], true);
    near(inner.kids[2].sizes[0], 0.5);
    const viaLeaf = S.equalize(t, [1]);
    near(viaLeaf.sizes[2], 1 / 3);
});
test("resize clamps at minimum", () => {
    const t = S.splitGroup(S.leaf("a"), "a", "right", "b");
    const r = pure(t, x => S.resize(x, [], 0, 0.9, 600));
    near(r.sizes[1] * 600, S.MIN_W);
    const l = S.resize(t, [], 0, -0.9, 600);
    near(l.sizes[0] * 600, S.MIN_W);
    const mid = S.resize(t, [], 0, 0.1, 1000);
    near(mid.sizes[0], 0.6); near(sum(mid.sizes), 1);
});
test("resize respects nested minimums", () => {
    let t = S.splitGroup(S.leaf("a"), "a", "right", "b");
    t = S.splitGroup(t, "b", "right", "c");   // row[a, b, c] -> sizes .5 .25 .25
    t = S.splitGroup(t, "a", "bottom", "x");  // a becomes col; fine
    const r = S.resize(t, [], 1, 0.5, 1400);
    assert.ok(r.sizes[2] * 1400 >= S.MIN_W - 1e-6);
});
test("layoutRects with gap", () => {
    const t = S.splitGroup(S.leaf("a"), "a", "right", "b");
    const r = pure(t, x => S.layoutRects(x, 0, 0, 1006, 500, 6));
    assert.deepStrictEqual(r.map(q => [q.group, q.x, q.w]), [["a", 0, 500], ["b", 506, 500]]);
    assert.ok(r.every(q => q.h === 500));
});
test("dividers sit in the gaps", () => {
    let t = S.splitGroup(S.leaf("a"), "a", "right", "b");
    t = S.splitGroup(t, "b", "bottom", "c");
    const d = pure(t, x => S.dividers(x, 0, 0, 1006, 506, 6));
    assert.strictEqual(d.length, 2);
    const v = d.find(q => q.dir === "row"), hz = d.find(q => q.dir === "col");
    assert.deepStrictEqual([v.x, v.y, v.w, v.h, v.i, v.path.length], [500, 0, 6, 506, 0, 0]);
    assert.deepStrictEqual([hz.x, hz.y, hz.h, hz.i, hz.path.join()], [506, 250, 6, 0, "1"]);
    assert.strictEqual(hz.w, 500);
    // dragging a divider through resize() with its own extent
    const r = S.resize(t, v.path, v.i, 20 / v.extent, v.extent);
    near(r.sizes[0], 0.5 + 20 / v.extent);
});
test("minSize adds up along the axis and gaps", () => {
    let t = S.splitGroup(S.leaf("a"), "a", "right", "b");
    t = S.splitGroup(t, "b", "bottom", "c");
    assert.strictEqual(S.minSize(t, "row", 6), S.MIN_W * 2 + 6);
    assert.strictEqual(S.minSize(t, "col", 6), S.MIN_H * 2 + 6);
    assert.strictEqual(S.minSize(S.leaf("a"), "row", 6), S.MIN_W);
    assert.strictEqual(Object.keys(S.PRESET_SLOTS).length, 6);
});
test("canSplit refuses tiny panes", () => {
    assert.strictEqual(S.canSplit(S.leaf("a"), "a", "right", 600, 500, 6), true);
    assert.strictEqual(S.canSplit(S.leaf("a"), "a", "right", 500, 500, 6), false);
    assert.strictEqual(S.canSplit(S.leaf("a"), "a", "bottom", 600, 300, 6), false);
});
test("neighbor in 2x2", () => {
    const t = S.preset("grid4", ["a", "b", "c", "d"]);   // cols: [a/c] [b/d]
    assert.strictEqual(S.neighbor(t, "a", "right", 1000, 800), "b");
    assert.strictEqual(S.neighbor(t, "a", "down", 1000, 800), "c");
    assert.strictEqual(S.neighbor(t, "d", "left", 1000, 800), "c");
    assert.strictEqual(S.neighbor(t, "d", "up", 1000, 800), "b");
    assert.strictEqual(S.neighbor(t, "a", "left", 1000, 800), null);
    assert.strictEqual(S.neighbor(t, "a", "up", 1000, 800), null);
});
test("presets with exact and fewer ids", () => {
    const ids = ["a", "b", "c", "d"];
    const slots = { single: 1, cols2: 2, rows2: 2, grid4: 4, cols3: 3, "main-side": 3 };
    for (const name of Object.keys(slots)) {
        for (let k = 1; k <= 5; k++) {
            const t = pure(S.leaf("x"), () => S.preset(name, ids.concat(["e"]).slice(0, k)));
            const g = S.groupsIn(t);
            assert.strictEqual(g.length, Math.min(k, slots[name]), name + " with " + k);
            const check = nd => { if (nd.t === "split") { near(sum(nd.sizes), 1); nd.kids.forEach(check); } };
            check(t);
        }
    }
    assert.strictEqual(S.preset("grid4", []), null);
    assert.strictEqual(S.preset("main-side", ids).sizes[0], 0.6);
});
test("immutability sweep", () => {
    const t = S.preset("grid4", ["a", "b", "c", "d"]);
    pure(t, x => S.splitGroup(x, "a", "left", "n"));
    pure(t, x => S.closeGroup(x, "b"));
    pure(t, x => S.equalize(x, [], true));
    pure(t, x => S.resize(x, [], 0, 0.1, 900));
});
console.log("ok " + n + " tests");
