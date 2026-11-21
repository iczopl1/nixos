.pragma library
// Safe math evaluator (recursive descent, no eval).
// Returns {ok:true, value:Number, text:String} or {ok:false}.
function evaluate(src) {
    var s = src.replace(/×/g, "*").replace(/÷/g, "/").replace(/,/g, ".");
    var i = 0, ops = 0;
    var fn = { sqrt: Math.sqrt, sin: Math.sin, cos: Math.cos, tan: Math.tan,
               asin: Math.asin, acos: Math.acos, atan: Math.atan,
               log: Math.log10, ln: Math.log, abs: Math.abs, exp: Math.exp,
               floor: Math.floor, ceil: Math.ceil, round: Math.round };
    var k = { pi: Math.PI, e: Math.E };
    function ws() { while (i < s.length && s[i] === " ") i++; }
    function fail() { throw 0; }
    function num() {
        var m = /^(\d+\.?\d*|\.\d+)(e[+-]?\d+)?/i.exec(s.slice(i));
        if (!m) fail();
        i += m[0].length;
        return parseFloat(m[0]);
    }
    function atom() {
        ws();
        var c = s[i];
        if (c === "(") {
            i++; var v = expr(); ws();
            if (s[i] !== ")") fail();
            i++; return v;
        }
        if (/[a-z]/i.test(c || "")) {
            var m = /^[a-z]+/i.exec(s.slice(i))[0].toLowerCase();
            i += m.length;
            if (k.hasOwnProperty(m)) return k[m];
            if (!fn.hasOwnProperty(m)) fail();
            ws();
            if (s[i] !== "(") fail();
            i++; var a = expr(); ws();
            if (s[i] !== ")") fail();
            i++; ops++; return fn[m](a);
        }
        return num();
    }
    function unary() {
        ws();
        if (s[i] === "-") { i++; ops++; return -unary(); }
        if (s[i] === "+") { i++; return unary(); }
        return power();
    }
    function power() {
        var b = atom(); ws();
        if (s[i] === "^" || (s[i] === "*" && s[i + 1] === "*")) {
            i += s[i] === "^" ? 1 : 2; ops++;
            return Math.pow(b, unary());
        }
        return b;
    }
    function term() {
        var v = unary();
        for (;;) {
            ws();
            var c = s[i];
            if (c === "*" || c === "/" || c === "%") {
                if (c === "*" && s[i + 1] === "*") return v;
                i++; ops++;
                var r = unary();
                v = c === "*" ? v * r : c === "/" ? v / r : v % r;
            } else return v;
        }
    }
    function expr() {
        var v = term();
        for (;;) {
            ws();
            var c = s[i];
            if (c === "+" || c === "-") {
                i++; ops++;
                var r = term();
                v = c === "+" ? v + r : v - r;
            } else return v;
        }
    }
    try {
        var v = expr(); ws();
        if (i !== s.length || ops === 0 || !isFinite(v)) return { ok: false };
        var t = String(parseFloat(v.toPrecision(12)));
        return { ok: true, value: v, text: t };
    } catch (x) {
        return { ok: false };
    }
}
