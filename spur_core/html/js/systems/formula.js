// ========================================
// SYSTEMS — the Formula card's line, READ (never worked out) so its pins appear as you type
//
// shared/systems/formula.lua is the ONE evaluator: the server's Check and the walker work every
// formula out there, so the two languages never disagree about % or ^ or a division by 0. This is a
// copy of its reader alone: the tokens, the shape, the names a line reads (its input pins), what each
// name is used as, what it answers, and why it does not read. The server's Check has the last word
// (its pins replace these when it answers).
//
// Keep it in step with formula.lua: the systems harness reads one list of lines with both.
// ========================================

export const MAX_LENGTH = 200;
export const MAX_DEPTH = 16;
export const MAX_NAMES = 16;

const FUNCS = {
    min: { min: 1, max: 16 }, max: { min: 1, max: 16 },
    abs: { min: 1, max: 1 }, floor: { min: 1, max: 1 }, ceil: { min: 1, max: 1 },
    round: { min: 1, max: 2 }, clamp: { min: 3, max: 3 }, sqrt: { min: 1, max: 1 },
    distance: { min: 2, max: 2 },
};
const WORDS = new Set(['and', 'or', 'not', 'true', 'false']);
const BINARY = {
    or: 1, and: 2,
    '==': 3, '~=': 3, '<': 3, '<=': 3, '>': 3, '>=': 3,
    '+': 4, '-': 4,
    '*': 5, '/': 5, '%': 5,
};
const UNARY_LEVEL = 6;

// Lua's character classes, ASCII (the server reads in the C locale).
const SPACE = /[ \t\n\v\f\r]/;
const DIGIT = /[0-9]/;

class FormulaError extends Error {}
function fail(msg) { throw new FormulaError(msg); }

/** A number as Lua 5.4 writes a float in a message (3 -> "3.0"). */
function luaNum(v) {
    if (Number.isInteger(v) && Math.abs(v) < 1e15) return v.toFixed(1);
    return String(v);
}

function bytes(s) {
    try { return new TextEncoder().encode(s).length; } catch (e) { return s.length; }
}

function tokenize(src) {
    const toks = [];
    let i = 0;
    const n = src.length;
    while (i < n) {
        const c = src[i];
        if (SPACE.test(c)) {
            i++;
        } else if (DIGIT.test(c) || (c === '.' && DIGIT.test(src[i + 1] || ''))) {
            const m = /^[0-9]*\.?[0-9]*/.exec(src.slice(i));
            let j = i + m[0].length;
            const ex = /^[eE][+-]?[0-9]+/.exec(src.slice(j));
            if (ex) j += ex[0].length;
            // Always a number here (as Lua's tonumber of the same text): 1.  .5  1e3  1.e3
            toks.push({ t: 'num', v: Number(src.slice(i, j)), at: i });
            i = j;
        } else if (/[A-Za-z_]/.test(c)) {
            const word = /^[A-Za-z_][A-Za-z0-9_]*/.exec(src.slice(i))[0];
            toks.push({ t: WORDS.has(word) ? word : 'name', v: word, at: i });
            i += word.length;
        } else if (c === '"' || c === "'") {
            const close = src.indexOf(c, i + 1);
            if (close < 0) fail('a piece of text is missing its closing quote');
            toks.push({ t: 'str', v: src.slice(i + 1, close), at: i });
            i = close + 1;
        } else {
            const two = src.slice(i, i + 2);
            if (two === '==' || two === '~=' || two === '!=' || two === '<=' || two === '>=') {
                toks.push({ t: two === '!=' ? '~=' : two, at: i });
                i += 2;
            } else if (c === '=') {
                fail('use == to compare (= alone sets nothing here)');
            } else if ('+-*/%^()<>,.'.includes(c)) {
                toks.push({ t: c, at: i });
                i++;
            } else {
                // The whole character (an emoji is two UTF-16 halves), as formula.lua names the letter.
                fail(`"${String.fromCodePoint(src.codePointAt(i))}" means nothing in a formula`);
            }
        }
    }
    toks.push({ t: 'end', at: n });
    return toks;
}

function shown(t) {
    if (t.v === undefined) return t.t;
    return typeof t.v === 'number' ? luaNum(t.v) : t.v;
}

class Parser {
    constructor(toks) { this.toks = toks; this.i = 0; this.depth = 0; }
    peek() { return this.toks[this.i]; }
    take() { return this.toks[this.i++]; }
    expect(kind, msg) { const t = this.take(); if (t.t !== kind) fail(msg); return t; }
    enter() { this.depth++; if (this.depth > MAX_DEPTH) fail(`more than ${MAX_DEPTH} levels of brackets`); }
    leave() { this.depth--; }

    primary() {
        const t = this.take();
        if (t.t === 'num') return { k: 'num', v: t.v };
        if (t.t === 'str') return { k: 'str', v: t.v };
        if (t.t === 'true') return { k: 'bool', v: true };
        if (t.t === 'false') return { k: 'bool', v: false };
        if (t.t === '(') {
            this.enter();
            const e = this.expr(0);
            this.expect(')', 'a bracket ( is never closed');
            this.leave();
            return e;
        }
        if (t.t === 'name') {
            if (this.peek().t === '(') {
                const spec = FUNCS[t.v];
                if (!spec) fail(`there is no function called ${t.v}`);
                this.take();
                this.enter();
                const args = [];
                if (this.peek().t !== ')') {
                    for (;;) {
                        args.push(this.expr(0));
                        if (this.peek().t !== ',') break;
                        this.take();
                    }
                }
                this.expect(')', `${t.v}( is never closed`);
                this.leave();
                if (args.length < spec.min || args.length > spec.max) {
                    fail(spec.min === spec.max ? `${t.v} takes ${spec.min}` : `${t.v} takes ${spec.min} to ${spec.max}`);
                }
                return { k: 'call', f: t.v, args };
            }
            if (FUNCS[t.v]) fail(`${t.v} is a function: write ${t.v}(...)`);
            let node = { k: 'name', v: t.v };
            if (this.peek().t === '.') {
                this.take();
                const f = this.take();
                if (f.t !== 'name' || !(f.v === 'x' || f.v === 'y' || f.v === 'z')) fail(`after ${t.v}. only x, y or z`);
                node = { k: 'field', v: t.v, f: f.v };
            }
            return node;
        }
        if (t.t === 'end') fail('the formula ends too soon');
        fail(`${shown(t)} cannot go there`);
    }

    unary() {
        const t = this.peek();
        if (t.t === 'not' || t.t === '-') {
            this.take();
            this.enter();
            const e = this.expr(UNARY_LEVEL);
            this.leave();
            return { k: 'un', op: t.t, e };
        }
        const base = this.primary();
        if (this.peek().t === '^') {
            this.take();
            this.enter();
            const rhs = this.expr(UNARY_LEVEL);
            this.leave();
            return { k: 'bin', op: '^', a: base, b: rhs };
        }
        return base;
    }

    expr(minLevel) {
        let left = this.unary();
        for (;;) {
            const t = this.peek();
            const level = BINARY[t.t];
            if (!level || level <= minLevel) break;
            this.take();
            this.enter();
            const right = this.expr(level);
            this.leave();
            left = { k: 'bin', op: t.t, a: left, b: right };
        }
        return left;
    }
}

/** Read a formula: { ast } or { error } (in a builder's words, the server's). */
export function parse(src) {
    if (typeof src !== 'string') return { error: 'a formula is text' };
    if (bytes(src) > MAX_LENGTH) return { error: `a formula is ${MAX_LENGTH} characters at most` };
    if (!/[^ \t\n\v\f\r]/.test(src)) return { error: 'the formula is empty' };
    try {
        const p = new Parser(tokenize(src));
        const ast = p.expr(0);
        if (p.peek().t !== 'end') fail(`${shown(p.peek())} cannot go there`);
        if (names(ast).length > MAX_NAMES) return { error: `a formula takes ${MAX_NAMES} names at most` };
        return { ast };
    } catch (e) {
        if (e instanceof FormulaError) return { error: e.message };
        return { error: 'the formula could not be read' };
    }
}

/** The names a formula reads, in the order they first appear: its input pins. */
export function names(ast) {
    const out = [], seen = new Set();
    const walk = (n) => {
        if (n.k === 'name' || n.k === 'field') {
            if (!seen.has(n.v)) { seen.add(n.v); out.push(n.v); }
        } else if (n.k === 'un') walk(n.e);
        else if (n.k === 'bin') { walk(n.a); walk(n.b); }
        else if (n.k === 'call') n.args.forEach((a) => walk(a));
    };
    walk(ast);
    return out;
}

/** What each name is used as: 'vector' (only ever name.x/y/z or in distance()), else 'any'. */
export function inputTypes(ast) {
    const types = {};
    const walk = (n, asPlace) => {
        if (n.k === 'field') types[n.v] = types[n.v] || 'vector';
        else if (n.k === 'name') {
            if (asPlace) types[n.v] = types[n.v] || 'vector';
            else types[n.v] = 'any';
        } else if (n.k === 'un') walk(n.e);
        else if (n.k === 'bin') { walk(n.a); walk(n.b); }
        else if (n.k === 'call') n.args.forEach((a) => walk(a, n.f === 'distance'));
    };
    walk(ast);
    return types;
}

/** What a formula answers: 'bool', 'number', 'text' or 'any'. */
export function resultType(ast) {
    if (ast.k === 'bool') return 'bool';
    if (ast.k === 'num') return 'number';
    if (ast.k === 'str') return 'text';
    if (ast.k === 'un') return ast.op === 'not' ? 'bool' : 'number';
    if (ast.k === 'bin') return BINARY[ast.op] && BINARY[ast.op] <= 3 ? 'bool' : 'number';
    if (ast.k === 'call' || ast.k === 'field') return 'number';
    return 'any';
}

/** The Formula card's value pins for a line (cards_core.lua's pinsFor): { inputs, outputs } or { error }. */
export function formulaPins(expr) {
    const r = parse(expr == null ? 'a + b' : expr);
    if (r.error) return { error: r.error };
    const types = inputTypes(r.ast);
    const inputs = names(r.ast).map((name) => ({ key: name, type: types[name] === 'vector' ? 'vector' : 'any', label: name }));
    const rt = resultType(r.ast);
    return { inputs, outputs: [{ key: 'result', type: rt === 'bool' || rt === 'text' || rt === 'number' ? rt : 'any', label: 'Result' }] };
}
