// Fonctions statistiques utilisées par stats.html (lois de probabilité : jStat).
// Chaque test renvoie la statistique, les degrés de liberté, la p-value et une taille d'effet.
(function (global) {
  "use strict";

  const sum = a => a.reduce((s, x) => s + x, 0);
  const mean = a => sum(a) / a.length;
  const variance = a => { const m = mean(a); return sum(a.map(x => (x - m) ** 2)) / (a.length - 1); };
  const sd = a => Math.sqrt(variance(a));

  function quantile(a, p) {
    const s = [...a].sort((x, y) => x - y);
    const i = (s.length - 1) * p, lo = Math.floor(i), hi = Math.min(lo + 1, s.length - 1);
    return s[lo] + (s[hi] - s[lo]) * (i - lo);
  }
  const median = a => quantile(a, 0.5);

  function skewness(a) {
    const m = mean(a), s = sd(a), n = a.length;
    return sum(a.map(x => ((x - m) / s) ** 3)) / n;
  }

  function describe(a) {
    const q1 = quantile(a, 0.25), q3 = quantile(a, 0.75), iqr = q3 - q1;
    const lo = q1 - 1.5 * iqr, hi = q3 + 1.5 * iqr;
    return {
      n: a.length, min: Math.min(...a), q1, median: median(a), mean: mean(a), q3, max: Math.max(...a),
      sd: sd(a), iqr, skew: skewness(a), lowFence: lo, highFence: hi,
      outliers: a.filter(x => x < lo || x > hi).length,
    };
  }

  // Rangs moyens (ex aequo) et terme de correction des ex aequo sum(t^3 - t)
  function ranks(values) {
    const idx = values.map((v, i) => [v, i]).sort((x, y) => x[0] - y[0]);
    const r = new Array(values.length);
    let ties = 0;
    for (let i = 0; i < idx.length;) {
      let j = i;
      while (j + 1 < idx.length && idx[j + 1][0] === idx[i][0]) j++;
      const avg = (i + j) / 2 + 1, t = j - i + 1;
      for (let k = i; k <= j; k++) r[idx[k][1]] = avg;
      if (t > 1) ties += t ** 3 - t;
      i = j + 1;
    }
    return { r, ties };
  }

  const pNormal2 = z => 2 * (1 - jStat.normal.cdf(Math.abs(z), 0, 1));
  const pChi2 = (x, df) => 1 - jStat.chisquare.cdf(x, df);
  const pF = (x, d1, d2) => 1 - jStat.centralF.cdf(x, d1, d2);
  const pT2 = (t, df) => 2 * (1 - jStat.studentt.cdf(Math.abs(t), df));

  // Mann-Whitney (approximation normale, correction des ex aequo).
  // Effet : corrélation rang-bisériale r = 1 - 2U/(n1 n2) ; > 0 si a tend à être plus grand que b.
  function mannWhitney(a, b) {
    const n1 = a.length, n2 = b.length, N = n1 + n2;
    const { r, ties } = ranks([...a, ...b]);
    const R1 = sum(r.slice(0, n1));
    const U1 = R1 - n1 * (n1 + 1) / 2;
    const mu = n1 * n2 / 2;
    const sigma = Math.sqrt(n1 * n2 / 12 * ((N + 1) - ties / (N * (N - 1))));
    const z = (U1 - mu) / sigma;
    return { test: "Mann-Whitney", U: U1, z, p: pNormal2(z), r: 2 * U1 / (n1 * n2) - 1, n1, n2 };
  }

  // Kruskal-Wallis. Effet : eta² basé sur H = (H - k + 1) / (N - k)
  function kruskal(groups) {
    const all = groups.flat(), N = all.length, k = groups.length;
    const { r, ties } = ranks(all);
    let H = 0, off = 0;
    for (const g of groups) { const Rg = sum(r.slice(off, off + g.length)); H += Rg ** 2 / g.length; off += g.length; }
    H = 12 / (N * (N + 1)) * H - 3 * (N + 1);
    H /= 1 - ties / (N ** 3 - N);
    const df = k - 1;
    return { test: "Kruskal-Wallis", H, df, p: pChi2(H, df), eta2: Math.max(0, (H - k + 1) / (N - k)), N };
  }

  // t de Welch. Effet : d de Cohen (écart-type poolé)
  function welchT(a, b) {
    const m1 = mean(a), m2 = mean(b), v1 = variance(a), v2 = variance(b), n1 = a.length, n2 = b.length;
    const se = Math.sqrt(v1 / n1 + v2 / n2), t = (m1 - m2) / se;
    const df = (v1 / n1 + v2 / n2) ** 2 / ((v1 / n1) ** 2 / (n1 - 1) + (v2 / n2) ** 2 / (n2 - 1));
    const sp = Math.sqrt(((n1 - 1) * v1 + (n2 - 1) * v2) / (n1 + n2 - 2));
    return { test: "t de Welch", t, df, p: pT2(t, df), d: (m1 - m2) / sp };
  }

  // ANOVA de Welch (variances inégales). Effet : eta² = SCinter / SCtotale
  function welchAnova(groups) {
    const k = groups.length;
    const n = groups.map(g => g.length), m = groups.map(mean), v = groups.map(variance);
    const w = n.map((ni, i) => ni / v[i]), W = sum(w);
    const mw = sum(w.map((wi, i) => wi * m[i])) / W;
    const A = sum(w.map((wi, i) => wi * (m[i] - mw) ** 2)) / (k - 1);
    const tmp = sum(w.map((wi, i) => (1 - wi / W) ** 2 / (n[i] - 1)));
    const B = 1 + 2 * (k - 2) / (k ** 2 - 1) * tmp;
    const F = A / B, df1 = k - 1, df2 = (k ** 2 - 1) / (3 * tmp);
    const all = groups.flat(), gm = mean(all);
    const ssb = sum(groups.map((g, i) => g.length * (m[i] - gm) ** 2));
    const sst = sum(all.map(x => (x - gm) ** 2));
    return { test: "ANOVA de Welch", F, df1, df2, p: pF(F, df1, df2), eta2: ssb / sst };
  }

  // Khi² d'indépendance sur un tableau de contingence (lignes x colonnes). Effet : V de Cramér
  function chi2(table) {
    const R = table.length, C = table[0].length;
    const rowT = table.map(sum), colT = table[0].map((_, j) => sum(table.map(r => r[j]))), N = sum(rowT);
    let x2 = 0, minExp = Infinity;
    const expected = table.map((row, i) => row.map((o, j) => {
      const e = rowT[i] * colT[j] / N; minExp = Math.min(minExp, e); x2 += (o - e) ** 2 / e; return e;
    }));
    const df = (R - 1) * (C - 1);
    return { test: "Khi² d'indépendance", chi2: x2, df, p: pChi2(x2, df), V: Math.sqrt(x2 / (N * (Math.min(R, C) - 1))),
      N, minExpected: minExp, expected, dfStar: Math.min(R, C) - 1 };
  }

  function pearson(x, y) {
    const mx = mean(x), my = mean(y);
    let sxy = 0, sxx = 0, syy = 0;
    for (let i = 0; i < x.length; i++) { const dx = x[i] - mx, dy = y[i] - my; sxy += dx * dy; sxx += dx * dx; syy += dy * dy; }
    const r = sxy / Math.sqrt(sxx * syy), n = x.length, t = r * Math.sqrt((n - 2) / (1 - r * r));
    return { test: "Corrélation de Pearson", r, n, p: pT2(t, n - 2), r2: r * r };
  }

  // Spearman = Pearson sur les rangs (p-value : approximation t à n-2 ddl)
  function spearman(x, y) {
    const res = pearson(ranks(x).r, ranks(y).r);
    return { ...res, test: "Corrélation de Spearman", rho: res.r };
  }

  // Résolution d'un système linéaire symétrique (Gauss-Jordan avec pivot) et inversion
  function invert(M) {
    const n = M.length, A = M.map((row, i) => [...row, ...row.map((_, j) => (i === j ? 1 : 0))]);
    for (let c = 0; c < n; c++) {
      let p = c;
      for (let r = c + 1; r < n; r++) if (Math.abs(A[r][c]) > Math.abs(A[p][c])) p = r;
      if (Math.abs(A[p][c]) < 1e-12) throw new Error("Matrice singulière (variables colinéaires)");
      [A[c], A[p]] = [A[p], A[c]];
      const piv = A[c][c];
      for (let j = 0; j < 2 * n; j++) A[c][j] /= piv;
      for (let r = 0; r < n; r++) if (r !== c) { const f = A[r][c]; if (f) for (let j = 0; j < 2 * n; j++) A[r][j] -= f * A[c][j]; }
    }
    return A.map(row => row.slice(n));
  }

  // Moindres carrés ordinaires. X : lignes d'observations (sans constante si absorbée par les effets fixes)
  function ols(X, y, names, { intercept = true, absorbedDf = 0 } = {}) {
    const Z = intercept ? X.map(r => [1, ...r]) : X, nm = intercept ? ["Constante", ...names] : names;
    const n = Z.length, k = Z[0].length;
    const XtX = Array.from({ length: k }, (_, i) => Array.from({ length: k }, (_, j) => { let s = 0; for (let r = 0; r < n; r++) s += Z[r][i] * Z[r][j]; return s; }));
    const Xty = Array.from({ length: k }, (_, i) => { let s = 0; for (let r = 0; r < n; r++) s += Z[r][i] * y[r]; return s; });
    const inv = invert(XtX);
    const b = inv.map(row => sum(row.map((v, j) => v * Xty[j])));
    const fit = Z.map(r => sum(r.map((v, j) => v * b[j])));
    const res = y.map((v, i) => v - fit[i]);
    const sse = sum(res.map(e => e * e)), my = mean(y), sst = sum(y.map(v => (v - my) ** 2));
    const dfRes = n - k - absorbedDf, s2 = sse / dfRes;
    const coefs = b.map((v, j) => { const se = Math.sqrt(s2 * inv[j][j]), t = v / se; return { name: nm[j], b: v, se, t, p: pT2(t, dfRes) }; });
    const r2 = 1 - sse / sst;
    const kEff = k - (intercept ? 1 : 0) + absorbedDf;
    return { coefs, r2, adjR2: 1 - (1 - r2) * (n - 1) / (n - kEff - 1), n, dfRes };
  }

  // Régression logistique (IRLS). Renvoie les rapports de cotes et leurs IC à 95 %
  function logistic(X, y, names) {
    const Z = X.map(r => [1, ...r]), nm = ["Constante", ...names], n = Z.length, k = Z[0].length;
    let b = new Array(k).fill(0), inv;
    for (let it = 0; it < 50; it++) {
      const eta = Z.map(r => sum(r.map((v, j) => v * b[j])));
      const mu = eta.map(e => 1 / (1 + Math.exp(-e)));
      const w = mu.map(m => Math.max(m * (1 - m), 1e-10));
      const H = Array.from({ length: k }, (_, i) => Array.from({ length: k }, (_, j) => { let s = 0; for (let r = 0; r < n; r++) s += Z[r][i] * w[r] * Z[r][j]; return s; }));
      const g = Array.from({ length: k }, (_, i) => { let s = 0; for (let r = 0; r < n; r++) s += Z[r][i] * (y[r] - mu[r]); return s; });
      inv = invert(H);
      const step = inv.map(row => sum(row.map((v, j) => v * g[j])));
      b = b.map((v, j) => v + step[j]);
      if (Math.max(...step.map(Math.abs)) < 1e-8) break;
    }
    const eta = Z.map(r => sum(r.map((v, j) => v * b[j])));
    const ll = sum(eta.map((e, i) => y[i] * e - Math.log(1 + Math.exp(e))));
    const p0 = mean(y), ll0 = n * (p0 * Math.log(p0) + (1 - p0) * Math.log(1 - p0));
    const coefs = b.map((v, j) => {
      const se = Math.sqrt(inv[j][j]), z = v / se;
      return { name: nm[j], b: v, se, z, p: pNormal2(z), or: Math.exp(v), lo: Math.exp(v - 1.96 * se), hi: Math.exp(v + 1.96 * se) };
    });
    return { coefs, n, mcFaddenR2: 1 - ll / ll0, lr: 2 * (ll - ll0), lrDf: k - 1, lrP: pChi2(2 * (ll - ll0), k - 1) };
  }

  // Lecture de l'ampleur d'un effet selon les seuils usuels de Cohen
  function magnitude(kind, v, dfStar = 1) {
    const a = Math.abs(v);
    const th = {
      d: [0.2, 0.5, 0.8], r: [0.1, 0.3, 0.5], eta2: [0.01, 0.06, 0.14],
      V: [0.1, 0.3, 0.5].map(x => x / Math.sqrt(dfStar)),
    }[kind];
    return a < th[0] ? "négligeable" : a < th[1] ? "faible" : a < th[2] ? "moyen" : "fort";
  }

  global.Stats = { sum, mean, variance, sd, quantile, median, skewness, describe, ranks, mannWhitney, kruskal,
    welchT, welchAnova, chi2, pearson, spearman, ols, logistic, magnitude };
})(window);
