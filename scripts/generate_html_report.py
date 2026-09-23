"""交付物 A：自包含 HTML 报告生成器（stats / CTT / IRT 三分支）。

设计目标与边界（为什么这么写）：
- 绝对自包含：整份 HTML 无任何 http(s) 外链（连 SVG 的 xmlns 都省略——HTML5 内联 SVG
  不需要它，省掉才能保证 grep http == 0）；图片以 data:image/png;base64 内嵌；
  动效全部用 CSS @keyframes + animation-delay 内联触发，不操作 DOM。
- 中文措辞、表格匹配规则、数值格式全部直接 import generate_stats_report 复用
  （present_methods / build_registry / method_tables / failed_methods_note / fmt），
  不重新发明结论句；SPSS 菜单路径镜像自 scripts/stats_common.R 的 STATS_METHODS。
- 图表手写内联 SVG，数字只来自结果目录里的 CSV；缺数据就跳过并留一行说明，绝不编造。
- 写文件一次性落盘（先写 .tmp 再 os.replace），失败不会留下半截 html。
CLI 契约：python -X utf8 scripts/generate_html_report.py --result-dir-utf8-base64 <b64>
成功打印 HTML_REPORT_OK 并退出 0。
"""
from __future__ import annotations

import argparse
import base64
import glob
import html
import json
import math
import os
import sys
import traceback
from pathlib import Path

import pandas as pd

# 复用 stats 分支 Word 报告的权威实现：措辞、表格匹配、fmt 数值格式。
# 必须先把自己的目录放进 sys.path，GUI 从任意 CWD 调用时也能 import 到。
sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_stats_report as gsr  # noqa: E402  (依赖 python-docx，环境已具备)

# ── SPSS 菜单路径目录（镜像 scripts/stats_common.R 的 STATS_METHODS，逐字照抄）──
# generate_stats_report.py 本身没有这份目录（它在 R 侧），所以这里按权威 R 源镜像；
# 取不到的方法宁可留空也不编造。
STATS_METHODS: dict[str, tuple[str, str]] = {
    "datacheck": ("数据准备与异常值筛查（建议先做）", "分析 > 描述统计 > 探索（极端值表/箱线图）+ 分析 > 缺失值分析"),
    "descriptives": ("描述统计", "分析 > 描述统计 > 描述/探索"),
    "normality": ("正态性与方差齐性检验", "分析 > 描述统计 > 探索 + 分析 > 比较均值 > 独立样本T检验（Levene行）"),
    "one_sample_t": ("单样本t检验", "分析 > 比较均值 > 单样本T检验"),
    "independent_t": ("独立样本t检验", "分析 > 比较均值 > 独立样本T检验"),
    "paired_t": ("配对样本t检验", "分析 > 比较均值 > 配对样本T检验"),
    "one_way_anova": ("单因素方差分析", "分析 > 比较均值 > 单因素ANOVA"),
    "two_way_anova": ("两因素方差分析", "分析 > 一般线性模型 > 单变量"),
    "rm_anova": ("重复测量方差分析", "分析 > 一般线性模型 > 重复测量"),
    "mixed_anova": ("混合设计方差分析", "分析 > 一般线性模型 > 重复测量（含被试间因子）"),
    "ancova": ("协方差分析", "分析 > 一般线性模型 > 单变量（含协变量）"),
    "correlation": ("相关分析（含偏相关）", "分析 > 相关 > 双变量 / 偏相关"),
    "regression": ("多元线性回归", "分析 > 回归 > 线性"),
    "chi_square_gof": ("卡方适合度检验", "分析 > 非参数检验 > 旧对话框 > 卡方"),
    "chi_square_independence": ("卡方独立性检验", "分析 > 描述统计 > 交叉表（卡方）"),
    "mann_whitney": ("Mann-Whitney U检验", "分析 > 非参数检验 > 旧对话框 > 2个独立样本"),
    "wilcoxon_signed": ("Wilcoxon符号秩检验", "分析 > 非参数检验 > 旧对话框 > 2个相关样本"),
    "kruskal_wallis": ("Kruskal-Wallis H检验", "分析 > 非参数检验 > 旧对话框 > K个独立样本"),
    "friedman": ("Friedman检验", "分析 > 非参数检验 > 旧对话框 > K个相关样本"),
    "mediation": ("中介效应分析", "分析 > 回归 > PROCESS（Model 4，含Bootstrap）"),
    "moderation": ("调节效应分析", "分析 > 回归 > PROCESS（Model 1，简单斜率）"),
    "power": ("统计功效与样本量", "对应 G*Power（pwr 包）"),
}

# 热力图里要排除的“非因子载荷”数值列（防止 communality/suggest_delete 混进因子格）
HEAT_EXCLUDE = {
    "communality", "communality", "h2", "primary_loading", "suggest_delete",
    "ss_loading", "ss_loadings", "proportion", "cumulative", "proportion_var",
    "cumulative_var", "eigenvalue", "uniqueness", "complexity", "n", "n_items",
}
PAL = ["#2b6cb0", "#c05621", "#2f855a", "#b2182b", "#6b46c1", "#0f766e", "#b7791f", "#5c6b7a"]


# ── 分支识别与输出文件名 ─────────────────────────────────────────────
def detect_branch(folder: Path) -> str | None:
    """按目录里的权威产物判断分支；顺序=优先级。未识别返回 None（调用方报错退出）。"""
    if ((folder / "stats_report_zh.md").exists() or (folder / "stats_report_zh.docx").exists()
            or glob.glob(str(folder / "00_prep_*.csv"))):
        return "stats"
    if (folder / "01_cleaning_summary.csv").exists() or (folder / "ctt_report_zh.docx").exists():
        return "ctt"
    irt_marks = ("*_model_comparison.csv", "*_item_parameters.csv",
                 "*_ability_estimates.csv", "*_ability_summary.csv", "*_item_fit.csv")
    if any(glob.glob(str(folder / p)) for p in irt_marks):
        return "irt"
    return None


def read_csv_relaxed(path) -> pd.DataFrame:
    """容错读 CSV：utf-8-sig 兼容 BOM 与无 BOM，再退 gbk；全失败按 utf-8 替换字符。"""
    p = Path(path)
    if not p.exists():
        return pd.DataFrame()
    for enc in ("utf-8-sig", "gbk"):
        try:
            return pd.read_csv(p, encoding=enc)
        except UnicodeDecodeError:
            continue
        except pd.errors.EmptyDataError:
            return pd.DataFrame()
    return pd.read_csv(p, encoding="utf-8-sig", encoding_errors="replace")


def load_manifest(folder: Path) -> dict:
    p = folder / "run_manifest.json"
    if not p.exists():
        return {}
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return {}


def esc(s) -> str:
    return html.escape(str(s), quote=True)


def to_f(v):
    """尽力转 float，失败/缺失返回 None（供画图前的守卫判断）。"""
    try:
        f = float(v)
        return None if pd.isna(f) else f
    except (TypeError, ValueError):
        return None


# ── 通用小工具：坐标轴刻度 / 折线长度 / 取色 ────────────────────────
def nice_ticks(lo: float, hi: float, n: int = 5) -> list[float]:
    if not math.isfinite(lo) or not math.isfinite(hi) or hi <= lo:
        return [lo]
    step0 = (hi - lo) / max(1, n)
    mag = 10 ** math.floor(math.log10(step0))
    step = next(m * mag for m in (1, 2, 2.5, 5, 10) if step0 <= m * mag)
    out, t = [], math.floor(lo / step) * step
    while t <= hi + 1e-9:
        if t >= lo - 1e-9:
            out.append(round(t, 10))
        t += step
    return out


def tick_txt(t: float) -> str:
    return f"{t:.10g}"


def path_len(pts) -> float:
    return sum(math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1])
               for i in range(len(pts) - 1))


def _lerp(a, b, t):
    return a + (b - a) * t


def heat_color(v: float) -> tuple[str, str]:
    """载荷配色：蓝(负)-白(0)-红(正)；返回 (fill, 文本色)（按亮度选黑/白保证可读）。"""
    t = max(-1.0, min(1.0, v))
    mid = (244, 246, 249)
    if t < 0:
        c0, c1, k = (33, 102, 172), mid, -t
    else:
        c0, c1, k = mid, (178, 24, 43), t
    rgb = tuple(round(_lerp(c0[i], c1[i], k)) for i in range(3))
    lum = 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]
    return "rgb(%d,%d,%d)" % rgb, ("#ffffff" if lum < 140 else "#1c2733")


def trunc(s, n: int) -> str:
    s = str(s)
    return s if len(s) <= n else s[: max(1, n - 1)] + "…"


# ── 被试级明细的编号掩码（隐私）────────────────────────────────────────────
# HTML 报告会被转发、贴到网上、当附件提交；"逐被试"表格里若带着原始编号
# （participant_id / 学号 / ID 列），分享报告就等于分享可识别到个体的数据。
# 这里把编号列替换为有序伪编号（#1、#2…，行序不变），原始值仍保留在结果目录的 CSV 里。
# 注意：仅掩码"标识列"，缺失率、各项标记等分析信息一律照原样保留。
PERSON_ID_COLS = {
    "participant_id", "participant", "id", "subject", "subject_id", "student", "student_id",
    "学号", "编号", "姓名", "被试", "被试编号", "姓名/编号",
}

def mask_person_ids(df: pd.DataFrame) -> pd.DataFrame:
    """把被试级表格中的标识列换成有序伪编号；不改动其它任何列。"""
    if df is None or df.empty:
        return df
    out = df.copy()
    for c in out.columns:
        if str(c).strip().lower() in PERSON_ID_COLS:
            out[c] = [f"#{i + 1}" for i in range(len(out))]
    return out

PERSON_TABLE_NOTE = ("本表为被试级明细：标识列已用有序伪编号（#1、#2…）替换，行序与原表一致；"
                     "原始编号请查看结果目录里的同名 CSV。对外分享本报告前，请确认是否仍需保留本表。")


def svg_text(x, y, s, cls="axt", anchor="middle", extra="") -> str:
    return f'<text class="{cls}" x="{x:.1f}" y="{y:.1f}" text-anchor="{anchor}"{extra}>{esc(s)}</text>'


# ── CSS / JS（内联、无外链；深浅色跟随系统）──────────────────────────
CSS = """*{box-sizing:border-box}
html{scroll-behavior:smooth}
:root{--bg:#f5f6f8;--card:#ffffff;--ink:#1c2733;--ink-soft:#5b6b7b;--line:#d8dee6;
--accent:#2b6cb0;--accent2:#c05621;--th-bg:#eef2f6;--z-hit:#c53030;--iqr-only:#2b6cb0;--ok:#2f855a}
@media (prefers-color-scheme: dark){:root{--bg:#12161b;--card:#1c222a;--ink:#e2e8f0;
--ink-soft:#9fb0c0;--line:#39424d;--accent:#63b3ed;--accent2:#f6ad55;--th-bg:#232b35;
--z-hit:#fc8181;--iqr-only:#63b3ed;--ok:#68d391}}
body{margin:0;background:var(--bg);color:var(--ink);line-height:1.75;
font-family:"Microsoft YaHei","PingFang SC","Noto Sans CJK SC","Segoe UI",sans-serif;font-size:15px}
.nav{position:fixed;top:0;left:0;bottom:0;width:232px;overflow-y:auto;background:var(--card);
border-right:1px solid var(--line);padding:16px 12px 30px;z-index:5}
.brand{font-weight:700;color:var(--accent);font-size:1.02rem;margin:2px 6px 4px}
.brandsub{color:var(--ink-soft);font-size:.72rem;margin:0 6px 12px}
.navlist a{display:block;color:var(--ink-soft);text-decoration:none;font-size:.82rem;
padding:5px 8px;border-left:3px solid transparent;border-radius:0 4px 4px 0;overflow:hidden;
text-overflow:ellipsis;white-space:nowrap}
.navlist a:hover{color:var(--accent);background:rgba(43,108,176,.08)}
.navlist a.active{color:var(--accent);border-left-color:var(--accent);background:rgba(43,108,176,.10)}
main{margin-left:248px;max-width:1040px;padding:30px 36px 70px}
@media (max-width:920px){
.nav{position:static;width:auto;bottom:auto;max-height:40vh;padding:8px 10px}
.brand{display:inline-block;margin-right:10px}.brandsub{display:none}
.navlist{display:flex;gap:2px;overflow-x:auto}
.navlist a{border-left:none;border-bottom:3px solid transparent;white-space:nowrap;padding:5px 8px}
.navlist a.active{border-left:none;border-bottom-color:var(--accent)}
main{margin-left:0;padding:18px 14px 50px}}
.rhead h1{font-size:1.45rem;margin:0 0 4px}
.subtitle{color:var(--ink-soft);font-size:.86rem;margin:0 0 8px}
section{margin:40px 0;scroll-margin-top:12px}
h2{font-size:1.2rem;border-left:4px solid var(--accent);padding-left:10px;margin:0 0 10px}
h3{font-size:1.02rem;margin:18px 0 6px}
.spss{background:rgba(43,108,176,.08);border-left:3px solid var(--accent);color:var(--ink);
padding:6px 10px;border-radius:0 6px 6px 0;font-size:.85rem;margin:0 0 12px}
.spss b{color:var(--accent)}
p{margin:.6em 0}
.tcap{font-weight:600;margin:16px 0 6px;font-size:.92rem}
.tnote{color:var(--ink-soft);font-size:.8rem;margin:4px 0 10px}
.tblwrap{overflow-x:auto;background:var(--card);border-top:2px solid var(--ink);
border-bottom:2px solid var(--ink);border-radius:4px}
.tblwrap.empty{padding:8px 12px;color:var(--ink-soft);font-size:.85rem}
table.tline{border-collapse:collapse;width:100%;font-size:.83rem;white-space:nowrap}
.tline thead th{border-bottom:1px solid var(--ink);background:var(--th-bg);font-weight:600;
padding:6px 10px;text-align:right}
.tline thead th:first-child{text-align:left}
.tline tbody td{padding:5px 10px}
.tline th:not(:first-child),.tline td:not(:first-child){text-align:right;font-variant-numeric:tabular-nums}
.tline th:first-child,.tline td:first-child{position:sticky;left:0;background:var(--card);z-index:1;
box-shadow:2px 0 0 var(--line)}
.tline thead th:first-child{background:var(--th-bg);z-index:2}
.tline tbody tr{animation:rowin .45s ease-out both}
figure.fig{margin:18px 0;text-align:center}
figure.fig img{max-width:100%;height:auto;border:1px solid var(--line);border-radius:6px}
figcaption{font-size:.8rem;color:var(--ink-soft);margin-top:6px}
svg.chart{max-width:100%;height:auto;background:var(--card);border:1px solid var(--line);border-radius:6px}
svg.chart text{font-family:inherit}
.axt{font-size:10px;fill:var(--ink-soft)}
.axl{font-size:11px;fill:var(--ink-soft);font-weight:600}
.axs{stroke:var(--ink-soft);stroke-width:1}
.grid{stroke:var(--line);stroke-width:1;stroke-dasharray:2 3}
.hflow{display:flex;align-items:stretch;gap:6px;flex-wrap:wrap;margin:14px 0 6px}
.hstep{flex:1;min-width:132px;background:var(--card);border:1px solid var(--line);
border-radius:10px;padding:12px 10px;text-align:center}
.hstep.final{border-color:var(--accent);box-shadow:0 0 0 2px rgba(43,108,176,.18)}
.harrow{align-self:center;color:var(--ink-soft);font-size:1.35rem;padding:0 2px}
.hlabel{font-size:.78rem;color:var(--ink-soft)}
.hsub{font-size:.7rem;color:var(--ink-soft);margin-top:2px}
.hval{font-size:1.9rem;font-weight:700;color:var(--accent);font-variant-numeric:tabular-nums}
.rnum{display:inline-flex;overflow:hidden;height:1.15em}
.dcol{display:inline-block;overflow:hidden;height:1.15em}
.dstrip{display:flex;flex-direction:column;animation:roll 1.1s cubic-bezier(.2,.7,.2,1) both}
.dstrip span{height:1.15em;line-height:1.15em;text-align:center}
.bar{transform-box:fill-box;transform-origin:center bottom;animation:grow .85s cubic-bezier(.2,.7,.2,1) both}
.draw{stroke-dasharray:var(--len);stroke-dashoffset:var(--len);animation:draw 1.5s ease-out forwards}
.fadein{opacity:0;animation:cellin .5s ease-out forwards}
.pulse{animation:pulse 2.6s ease-in-out 1.8s infinite}
.kv{border-collapse:collapse;font-size:.85rem;margin:8px 0}
.kv th,.kv td{padding:5px 12px 5px 0;text-align:left;vertical-align:top}
.kv th{color:var(--ink-soft);font-weight:600;white-space:nowrap}
.note{color:var(--ink-soft);font-size:.82rem}
.skipnote{color:var(--ink-soft);font-size:.82rem;border:1px dashed var(--line);
border-radius:6px;padding:6px 10px;margin:10px 0}
@keyframes rowin{from{opacity:0;transform:translateY(5px)}}
@keyframes grow{from{transform:scaleY(0)}}
@keyframes draw{to{stroke-dashoffset:0}}
@keyframes cellin{from{opacity:0}to{opacity:1}}
@keyframes roll{from{transform:translateY(0)}to{transform:translateY(var(--ty))}}
@keyframes pulse{0%,100%{opacity:.25}50%{opacity:1}}
@media (prefers-reduced-motion: reduce){*{animation:none!important;transition:none!important}}"""

# 内联 IntersectionObserver（约 15 行原生 JS）：滚动时高亮左侧导航当前节。
NAV_JS = """(function(){
"use strict";
var links=[].slice.call(document.querySelectorAll(".navlist a"));
if(!links.length||!("IntersectionObserver" in window))return;
var io=new IntersectionObserver(function(es){
  es.forEach(function(e){
    if(e.isIntersecting){
      links.forEach(function(a){a.classList.toggle("active",a.getAttribute("href")==="#"+e.target.id);});
    }
  });
},{rootMargin:"-15% 0px -70% 0px"});
[].slice.call(document.querySelectorAll("main section[id]")).forEach(function(s){io.observe(s);});
})();"""


def assemble_page(title: str, subtitle: str, nav: list[tuple[str, str]], body: str) -> str:
    nav_html = "".join(f'<a href="#{esc(sid)}">{esc(st)}</a>' for sid, st in nav)
    return (
        "<!DOCTYPE html>\n<html lang=\"zh-CN\">\n<head>\n"
        '<meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
        f"<title>{esc(title)}</title>\n<style>{CSS}</style>\n</head>\n<body>\n"
        f'<nav class="nav" aria-label="报告导航"><div class="brand">Psychostat</div>'
        f'<div class="brandsub">自包含 HTML 报告（离线可读）</div>'
        f'<div class="navlist">{nav_html}</div></nav>\n<main>\n'
        f'<header class="rhead"><h1>{esc(title)}</h1><p class="subtitle">{esc(subtitle)}</p></header>\n'
        f"{body}\n</main>\n<script>{NAV_JS}</script>\n</body>\n</html>\n"
    )


def section_html(sid: str, heading: str, inner: str) -> str:
    return f'<section id="{esc(sid)}"><h2>{esc(heading)}</h2>{inner}</section>'


# ── 三线表（顶线/表头下线/底线；首列冻结；行内 animation-delay 逐行淡入）──
def table_html(df: pd.DataFrame, title: str, p_matrix: bool = False,
               max_rows: int = 200, note: str | None = None) -> str:
    out = [f'<div class="tcap">{esc(title)}</div>']
    if df is None or df.empty or len(df.columns) == 0:
        out.append('<div class="tblwrap empty">本表没有可用数据。</div>')
        return "".join(out)
    if len(df) > max_rows:  # 与 Word 生成器一致的截断保护，防止超宽表撑爆页面
        out.append(f'<div class="tnote">表格行数超过上限，仅显示前 {max_rows} 行（总行数 {len(df)}）。</div>')
        df = df.head(max_rows)
    p_flags = [p_matrix or gsr.is_p_col(c) for c in df.columns]
    int_flags = [(not pf) and (gsr.is_int_col(c) or gsr.col_all_int(df[c]))
                 for c, pf in zip(df.columns, p_flags)]
    thead = "".join(f"<th>{esc(str(c))}</th>" for c in df.columns)
    rows = []
    for i, (_, row) in enumerate(df.iterrows()):
        tds = "".join(
            f"<td>{esc(gsr.fmt(v, integer=int_flags[j], p_col=p_flags[j]))}</td>"
            for j, v in enumerate(row))
        # animation-delay 直接写内联 style（不依赖 JS）
        rows.append(f'<tr style="animation-delay:{i * 0.03:.2f}s">{tds}</tr>')
    out.append('<div class="tblwrap"><table class="tline"><thead><tr>' + thead +
               "</tr></thead><tbody>" + "".join(rows) + "</tbody></table></div>")
    if note:
        out.append(f'<div class="tnote">注：{esc(note)}</div>')
    return "".join(out)


def png_figure(folder: Path, name: str, caption: str, num: int | None = None) -> str:
    """目录里已有的 PNG 诊断图：base64 内嵌保持自包含。"""
    p = folder / name
    if not p.exists() or p.stat().st_size == 0:
        return ""
    b64 = base64.b64encode(p.read_bytes()).decode("ascii")
    label = f"图{num} " if num is not None else ""
    return (f'<figure class="fig"><img src="data:image/png;base64,{b64}" '
            f'alt="{esc(caption)}"><figcaption>{esc(label + caption)}</figcaption></figure>')


def svg_figure(svg: str, caption: str, num: int | None = None) -> str:
    label = f"图{num} " if num is not None else ""
    return f'<figure class="fig">{svg}<figcaption>{esc(label + caption)}</figcaption></figure>'


def draw_path(pts, color: str, width: float = 2.0, delay: float = 0.0,
              opacity: float = 1.0, dash: str = "") -> str:
    """折线（stroke-dasharray 描出动画）；长度在 Python 侧算好写进 --len。"""
    if len(pts) < 2:
        return ""
    L = path_len(pts)
    d = "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in pts)
    extra = f' stroke-dasharray="{dash}"' if dash else ""
    return (f'<path class="draw" d="{d}" fill="none" stroke="{color}" stroke-width="{width}"'
            f' stroke-opacity="{opacity}"{extra} style="--len:{L:.0f};animation-delay:{delay:.2f}s"/>')


def rolling_number(value: int, delay_ms: int = 0) -> str:
    """纯 CSS 数字滚动：每十进制位一条 0-9 数字条，translateY 到目标位。"""
    digits = str(int(value))
    cols = []
    for i, ch in enumerate(digits):
        strip = "".join(f"<span>{k}</span>" for k in range(10))
        ty = -int(ch)  # 单位 em（.dstrip span 高 1.15em）
        cols.append(f'<span class="dcol"><span class="dstrip" '
                    f'style="--ty:{ty * 1.15}em;animation-delay:{delay_ms + i * 90}ms">{strip}</span></span>')
    return f'<span class="rnum" role="img" aria-label="{value}">{"".join(cols)}</span>'


# ═══════════════════════ SVG 图表（数字只来自 CSV）═══════════════════════
def boxplot_svg(folder: Path) -> tuple[str, str]:
    """异常值箱线图：q1/q3/fence/min/max 画箱与须；outliers.csv 的点按规则分色。"""
    os_ = read_csv_relaxed(folder / "00_prep_outlier_summary.csv")
    if os_.empty:
        return "", ""
    outl = read_csv_relaxed(folder / "00_prep_outliers.csv")
    need = {"variable", "q1", "q3", "lower_fence", "upper_fence", "min", "max"}
    if not need <= set(os_.columns):
        return "", ""
    os_ = os_.head(8)  # 版面保护
    W, H, ml, mr, mt, mb = 720, 350, 60, 16, 44, 66
    pw, ph = W - ml - mr, H - mt - mb
    lo = min(min(os_["min"].min(), os_["lower_fence"].min()),
             outl["value"].min() if (not outl.empty and "value" in outl) else math.inf)
    hi = max(max(os_["max"].max(), os_["upper_fence"].max()),
             outl["value"].max() if (not outl.empty and "value" in outl) else -math.inf)
    pad = (hi - lo) * 0.06 or 1.0
    lo, hi = lo - pad, hi + pad

    def Y(v):
        return mt + ph * (1 - (v - lo) / (hi - lo))

    bw = pw / len(os_)
    parts = []
    for tk in nice_ticks(lo, hi, 6):
        y = Y(tk)
        parts.append(f'<line class="grid" x1="{ml}" y1="{y:.1f}" x2="{W - mr}" y2="{y:.1f}"/>')
        parts.append(svg_text(ml - 6, y + 3.5, tick_txt(tk), anchor="end"))
    # 须端只画到 fence 夹紧的位置：CSV 没给“最大非离群值”，画到围栏是保守近似（图注说明）
    for i, (_, r) in enumerate(os_.iterrows()):
        cx = ml + bw * (i + 0.5)
        wlo = max(float(r["min"]), float(r["lower_fence"]))
        whi = min(float(r["max"]), float(r["upper_fence"]))
        yq1, yq3 = Y(float(r["q1"])), Y(float(r["q3"]))
        bwid = bw * 0.34
        parts.append(f'<line class="axs" x1="{cx:.1f}" y1="{Y(wlo):.1f}" x2="{cx:.1f}" y2="{Y(whi):.1f}"/>')
        for yv in (Y(wlo), Y(whi)):
            parts.append(f'<line class="axs" x1="{cx - bwid / 2:.1f}" y1="{yv:.1f}" x2="{cx + bwid / 2:.1f}" y2="{yv:.1f}"/>')
        parts.append(f'<rect class="fadein" x="{cx - bwid / 2:.1f}" y="{yq3:.1f}" width="{bwid:.1f}" '
                     f'height="{max(1.0, yq1 - yq3):.1f}" rx="2" fill="var(--accent)" fill-opacity=".28" '
                     f'stroke="var(--accent)" stroke-width="1.2" style="animation-delay:{0.15 + i * 0.12:.2f}s"/>')
        parts.append(svg_text(cx, mt + ph + 34, trunc(r["variable"], 9), extra=' transform="rotate(-22 %.1f %.1f)"' % (cx, mt + ph + 34)))
    # 离群点分色：reason 含 "Z" → Z 规则命中（红）；否则仅 IQR（蓝）
    if not outl.empty and {"variable", "value"} <= set(outl.columns):
        for k, (_, r) in enumerate(outl.iterrows()):
            var, val = str(r["variable"]), to_f(r["value"])
            if val is None:
                continue
            i = next((j for j, (_, q) in enumerate(os_.iterrows()) if str(q["variable"]) == var), None)
            if i is None:
                continue
            cx = ml + bw * (i + 0.5) + (k % 3 - 1) * 7
            cls = "z" if "Z" in str(r.get("reason", "")) else "iqr"
            color = "var(--z-hit)" if cls == "z" else "var(--iqr-only)"
            parts.append(f'<circle class="fadein" cx="{cx:.1f}" cy="{Y(val):.1f}" r="4.4" '
                         f'fill="{color}" style="animation-delay:{0.5 + k * 0.1:.2f}s"/>')
    parts.append(f'<line class="axs" x1="{ml}" y1="{mt + ph}" x2="{W - mr}" y2="{mt + ph}"/>')
    parts.append(svg_text(ml - 44, mt + ph / 2, "观测值", cls="axl", anchor="middle",
                          extra=' transform="rotate(-90 %d %.1f)"' % (ml - 44, mt + ph / 2)))
    # 图例（两类点分色）
    lx = ml + 6
    parts.append(f'<circle cx="{lx}" cy="{mt - 16}" r="4.4" fill="var(--z-hit)"/>' + svg_text(lx + 8, mt - 12.5, "Z 规则命中", anchor="start"))
    parts.append(f'<circle cx="{lx + 92}" cy="{mt - 16}" r="4.4" fill="var(--iqr-only)"/>' + svg_text(lx + 100, mt - 12.5, "仅 1.5×IQR 命中", anchor="start"))
    svg = (f'<svg class="chart" viewBox="0 0 {W} {H}" role="img" aria-label="异常值箱线图">'
           + "".join(parts) + "</svg>")
    n_z = int(pd.to_numeric(os_.get("n_z"), errors="coerce").fillna(0).sum()) if "n_z" in os_ else 0
    n_iqr = int(pd.to_numeric(os_.get("n_iqr"), errors="coerce").fillna(0).sum()) if "n_iqr" in os_ else 0
    cap = (f"异常值箱线图（SVG，数据：00_prep_outlier_summary.csv 与 00_prep_outliers.csv；"
           f"按 |Z| 命中 {n_z} 个、按 1.5×IQR 命中 {n_iqr} 个个案次）。"
           f"箱体为 Q1–Q3，须端画到围栏（1.5×IQR 上下限）处——CSV 未提供“最大非离群值”，"
           f"这是保守画法；红点为 Z 规则命中，蓝点为仅 IQR 规则命中。")
    return svg, cap


def _collect_desc_rows(folder: Path) -> list[dict]:
    """收集结果目录里真实的逐变量描述统计（mean/sd/min/max/N），供示意分布取数。"""
    rows = []
    for pth in sorted(glob.glob(str(folder / "??_*_desc.csv"))):
        df = read_csv_relaxed(pth)
        if {"variable", "mean", "sd", "min", "max"} <= set(df.columns):
            for _, r in df.iterrows():
                rows.append({"src": Path(pth).name, **{k: r[k] for k in
                            ("variable", "mean", "sd", "min", "max", *(["N"] if "N" in df.columns else []))}})
    return rows


def _norm_pdf(x, mu, sd):
    return math.exp(-0.5 * ((x - mu) / sd) ** 2) / sd  # 未归一化高度即可（同一 A 缩放）


def imputation_teaching(folder: Path) -> str:
    """均值插补教学动画：叠加的两幅 SVG“直方图”展示分布向中心收缩。
    数据源优先级：真实描述统计 + 真实插补个数；无缺失时为标注“示意”的演示。"""
    desc = _collect_desc_rows(folder)
    if not desc:
        return ""
    mdf = read_csv_relaxed(folder / "00_prep_missing_audit.csv")
    summ = read_csv_relaxed(folder / "00_prep_preparation_summary.csv")
    vals = {}
    if not summ.empty and {"item", "value"} <= set(summ.columns):
        vals = {str(r["item"]): to_f(r["value"]) for _, r in summ.iterrows()}
    n_imp = vals.get("均值插补的缺失值个数")
    n_imp = int(n_imp) if n_imp is not None else None
    # 优先展示“有缺失的变量”；否则第一个变量
    row = desc[0]
    if not mdf.empty and "N_missing" in mdf.columns:
        miss = mdf[pd.to_numeric(mdf["N_missing"], errors="coerce").fillna(0) > 0]
        want = str(miss.iloc[0]["variable"]) if len(miss) else str(mdf.iloc[0]["variable"])
        for r in desc:
            if str(r["variable"]) == want:
                row = r
                break
    mean, sd = to_f(row["mean"]), to_f(row["sd"])
    vmin, vmax = to_f(row["min"]), to_f(row["max"])
    N = to_f(row.get("N")) if row.get("N") is not None else None
    if mean is None or sd is None or vmin is None or vmax is None or not (sd > 0) or vmax <= vmin:
        return ""
    W, H, ml, mr, mt, mb = 720, 310, 56, 16, 30, 52
    pw, ph = W - ml - mr, H - mt - mb
    pad = (vmax - vmin) * 0.06
    lo, hi = vmin - pad, vmax + pad
    nb = 26

    def X(v):
        return ml + pw * (v - lo) / (hi - lo)

    sd2 = None
    if n_imp is not None and n_imp > 0 and N:
        # 均值插补后的真实方差收缩公式：Var' = Var·(1 − n_imp/N)（sd2 由真实数推得）
        sd2 = sd * math.sqrt(max(0.0, 1.0 - n_imp / N))
        if sd2 <= 0 or abs(sd2 - sd) < 1e-12:
            sd2 = None
    def h_of(mu, s):
        return lambda x: _norm_pdf(x, mu, s)
    h1, h2 = h_of(mean, sd), (h_of(mean, sd2) if sd2 else None)
    scale = ph * 0.86 / max(h1(mean), h2(mean) if h2 else 0)
    parts = []
    for tk in [vmin, mean, vmax]:
        parts.append(f'<line class="grid" x1="{X(tk):.1f}" y1="{mt}" x2="{X(tk):.1f}" y2="{mt + ph}"/>')
        parts.append(svg_text(X(tk), mt + ph + 16, gsr.num(tk)))
    for i in range(nb):
        x0 = lo + (hi - lo) * i / nb
        x1_ = lo + (hi - lo) * (i + 1) / nb
        c = (x0 + x1_) / 2
        hgt = h1(c) * scale
        if hgt < 1:
            continue
        bx, bw2 = X(x0) + 1, (X(x1_) - X(x0)) - 2
        parts.append(f'<rect class="bar" x="{bx:.1f}" y="{mt + ph - hgt:.1f}" width="{bw2:.1f}" '
                     f'height="{hgt:.1f}" fill="var(--accent)" fill-opacity=".45" '
                     f'style="animation-delay:{i * 0.02:.2f}s"/>')
    # 插补前轮廓（描出动画）
    pts = [(X(lo + (hi - lo) * k / 200), mt + ph - h1(lo + (hi - lo) * k / 200) * scale) for k in range(201)]
    parts.append(draw_path(pts, "var(--accent)", 2.2, 0.35))
    if h2:  # 插补后分布：向中心收缩、峰更高（面积守恒）
        pts2 = [(X(lo + (hi - lo) * k / 200), mt + ph - h2(lo + (hi - lo) * k / 200) * scale) for k in range(201)]
        parts.append(draw_path(pts2, "var(--accent2)", 2.4, 1.3, dash="6 4"))
    # 均值处的“插补脉冲”标记
    mx = X(mean)
    parts.append(f'<line class="pulse" x1="{mx:.1f}" y1="{mt + 6}" x2="{mx:.1f}" y2="{mt + ph}" '
                 f'stroke="var(--accent2)" stroke-width="1.4" stroke-dasharray="5 4"/>')
    parts.append(f'<path class="fadein" d="M{mx:.1f} {mt + 18:.1f} L{mx - 7:.1f} {mt + 6:.1f} L{mx + 7:.1f} {mt + 6:.1f} z" '
                 f'fill="var(--accent2)" style="animation-delay:1.4s"/>')
    parts.append(svg_text(min(mx + 10, W - mr - 4), mt + 18,
                          f"插补位置 M = {gsr.num(mean)}｜本次插补 n = {n_imp if n_imp is not None else 'NA'}",
                          anchor="end" if mx > W * 0.6 else "start"))
    parts.append(f'<line class="axs" x1="{ml}" y1="{mt + ph}" x2="{W - mr}" y2="{mt + ph}"/>')
    parts.append(svg_text(ml - 40, mt + ph / 2, "示意频数", cls="axl",
                          extra=' transform="rotate(-90 %d %.1f)"' % (ml - 40, mt + ph / 2)))
    svg = (f'<svg class="chart" viewBox="0 0 {W} {H}" role="img" aria-label="均值插补教学示意">'
           + "".join(parts) + "</svg>")
    src_note = (f"真实数据来源：{row['src']}（{row['variable']}：N = {int(N) if N else 'NA'}，"
                f"M = {gsr.num(mean)}，SD = {gsr.num(sd)}，范围 [{gsr.num(vmin)}, {gsr.num(vmax)}]）")
    if n_imp == 0 or n_imp is None:
        cap = ("均值插补教学示意（标注“示意”）：本次运行无缺失/插补（插补个数 = "
               f"{n_imp if n_imp is not None else 'NA'}），动画为说明性演示——"
               f"蓝色条为按真实描述统计绘制的示意分布，虚线脉冲标出均值插补的落点。"
               f"若发生均值插补，插补值将全部堆在均值处，使分布向中心收缩、方差缩小。{src_note}。")
    else:
        cap = (f"均值插补前后叠加对比（示意曲线 + 真实计数）：蓝色实线为插补前分布；"
               f"橙色虚线为插补后分布（按方差收缩公式 SD′ = SD·√(1 − n/N) = {gsr.num(sd2)}，"
               f"由真实 n = {n_imp} 与 N = {int(N)} 算得）；均值处脉冲为插补值落点。{src_note}。")
    return svg_figure(svg, cap)


def health_card(folder: Path) -> str:
    """数据健康卡：原始 N → 插补 → 删除 → 最终 N（横向流程条 + 纯 CSS 数字滚动）。"""
    summ = read_csv_relaxed(folder / "00_prep_preparation_summary.csv")
    if summ.empty or not {"item", "value"} <= set(summ.columns):
        return ""
    vals = {str(r["item"]): to_f(r["value"]) for _, r in summ.iterrows()}
    keys = [("原始 N", "原始个案数", "读取到的原始行数"),
            ("均值插补（个缺失值）", "均值插补的缺失值个数", "在均值处替换的缺失值"),
            ("按 |Z| 规则删除（例）", "按 |Z| 规则删除的个案数", "删除的异常个案"),
            ("最终 N", "最终个案数", "后续分析实际使用的样本量")]
    steps = []
    for i, (label, key, sub) in enumerate(keys):
        v = vals.get(key)
        if v is None:
            continue
        v = int(round(v))
        fin = ' final' if key == "最终个案数" else ""
        steps.append(f'<div class="hstep{fin}"><div class="hlabel">{esc(label)}</div>'
                     f'<div class="hval">{rolling_number(v, delay_ms=150 + i * 220)}</div>'
                     f'<div class="hsub">{esc(sub)}</div></div>')
    if len(steps) < 2:
        return ""
    flow = '<div class="harrow" aria-hidden="true">→</div>'.join(steps)
    extra = ""
    lw = read_csv_relaxed(folder / "00_prep_listwise_impact.csv")
    if not lw.empty and {"N_total", "N_complete_cases", "N_would_drop", "pct_would_drop"} <= set(lw.columns):
        r = lw.iloc[0]
        extra = (f'<p class="note">整列删除（listwise）影响（00_prep_listwise_impact.csv）：'
                 f'总 N = {int(r["N_total"])}，完整个案 = {int(r["N_complete_cases"])}，'
                 f'若按 listwise 将损失 {int(r["N_would_drop"])} 例（{gsr.num(to_f(r["pct_would_drop"]))}%）。</p>')
    return f'<div class="hflow">{flow}</div>{extra}'


def scree_svg(df: pd.DataFrame) -> tuple[str, str]:
    """碎石图：需要“特征值”数值列（如 IRT 的 eifa_eigenvalues.csv）。"""
    if df is None or df.empty:
        return "", ""
    low = {str(c).lower(): c for c in df.columns}
    yc = next((low[k] for k in ("eigenvalue", "eigen", "eigenvalues") if k in low), None)
    xc = next((low[k] for k in ("component", "factor", "pc", "number", "n") if k in low), None)
    if yc is None:
        return "", ""
    ys = [to_f(v) for v in df[yc]]
    if any(v is None or not math.isfinite(v) for v in ys):
        return "", ""
    xs = list(range(1, len(ys) + 1)) if xc is None else [to_f(v) or i for i, v in enumerate(df[xc], 1)]
    W, H, ml, mr, mt, mb = 720, 300, 58, 16, 26, 46
    pw, ph = W - ml - mr, H - mt - mb
    lo, hi = 0.0, max(ys + [1.0]) * 1.08
    def X(v):
        return ml + pw * (v - xs[0]) / max(1e-9, (xs[-1] - xs[0]) or 1)
    def Y(v):
        return mt + ph * (1 - (v - lo) / (hi - lo))
    parts = []
    for tk in nice_ticks(lo, hi, 5):
        parts.append(f'<line class="grid" x1="{ml}" y1="{Y(tk):.1f}" x2="{W - mr}" y2="{Y(tk):.1f}"/>')
        parts.append(svg_text(ml - 6, Y(tk) + 3.5, tick_txt(tk), anchor="end"))
    if hi >= 1:
        parts.append(f'<line x1="{ml}" y1="{Y(1):.1f}" x2="{W - mr}" y2="{Y(1):.1f}" '
                     f'stroke="var(--z-hit)" stroke-width="1.2" stroke-dasharray="5 4"/>')
        parts.append(svg_text(W - mr - 2, Y(1) - 4, "特征值 = 1", anchor="end"))
    pts = [(X(x), Y(y)) for x, y in zip(xs, ys)]
    parts.append(draw_path(pts, "var(--accent)", 2.2))
    for i, (x, y) in enumerate(pts):
        parts.append(f'<circle class="fadein" cx="{x:.1f}" cy="{y:.1f}" r="3.6" fill="var(--accent)" '
                     f'style="animation-delay:{0.4 + i * 0.06:.2f}s"/>')
    for x, y in zip(xs, ys):
        parts.append(svg_text(X(x), mt + ph + 15, tick_txt(x)))
    parts.append(f'<line class="axs" x1="{ml}" y1="{mt + ph}" x2="{W - mr}" y2="{mt + ph}"/>')
    parts.append(svg_text(W / 2, H - 6, "成分序号", cls="axl"))
    parts.append(svg_text(ml - 42, mt + ph / 2, "特征值", cls="axl",
                          extra=' transform="rotate(-90 %d %.1f)"' % (ml - 42, mt + ph / 2)))
    svg = f'<svg class="chart" viewBox="0 0 {W} {H}" role="img" aria-label="碎石图">' + "".join(parts) + "</svg>"
    return svg, "碎石图（SVG，Kaiser 准则参考线 = 1）：曲线趋平处即为建议保留的因子数。"


def loading_matrix(df: pd.DataFrame):
    """从载荷表提取 (items, factors, values)；支持宽表（item + F1..Fk）与长表（factor/item/loading）。"""
    if df is None or df.empty:
        return None
    low = {str(c).lower(): c for c in df.columns}
    if {"factor", "item"} <= set(low) and ("standardized_loading" in low or "loading" in low):
        vc = low.get("standardized_loading") or low.get("loading")
        piv = df.pivot_table(index=low["item"], columns=low["factor"], values=vc, aggfunc="first")
        return list(piv.index), list(piv.columns), piv
    if len(df.columns) < 2:
        return None
    label = df.columns[0]
    cols = [c for c in df.columns[1:]
            if pd.api.types.is_numeric_dtype(df[c]) and not pd.api.types.is_bool_dtype(df[c])
            and str(c).lower() not in HEAT_EXCLUDE]
    if len(cols) < 1 or pd.api.types.is_numeric_dtype(df[label]):
        return None
    return list(df[label].astype(str)), cols, df[cols]
    # 返回 (items, factors, values)


def heatmap_svg(df: pd.DataFrame) -> tuple[str, str]:
    mat = loading_matrix(df)
    if not mat:
        return "", ""
    items, factors, vals = mat
    note_trunc = ""
    if len(items) > 30:
        items, vals, note_trunc = items[:30], vals.head(30), f"（仅显示前 30 行，共 {len(items)} 行）"
    if len(factors) > 12:
        factors, note_trunc = factors[:12], f"{note_trunc}（仅显示前 12 列因子）"
    nr, nc = len(items), len(factors)
    cw, ch, lw_, th = 46, 26, 96, 36
    W, H = lw_ + nc * cw + 14, th + nr * ch + 30
    parts = []
    for j, f in enumerate(factors):
        parts.append(svg_text(lw_ + cw * (j + 0.5), th - 8, trunc(f, 7)))
    for i, it in enumerate(items):
        parts.append(svg_text(lw_ - 6, th + ch * (i + 0.5) + 3.5, trunc(it, 10), anchor="end"))
        for j, f in enumerate(factors):
            v = to_f(vals.iloc[i][f]) if hasattr(vals, "iloc") else None
            if v is None:
                continue
            fill, tc = heat_color(v)
            delay = (i * nc + j) * 0.02
            parts.append(f'<rect class="fadein" x="{lw_ + j * cw + 1}" y="{th + i * ch + 1}" '
                         f'width="{cw - 2}" height="{ch - 2}" rx="2" fill="{fill}" '
                         f'style="animation-delay:{delay:.2f}s"/>')
            parts.append(f'<text class="fadein" x="{lw_ + cw * (j + 0.5)}" y="{th + ch * (i + 0.5) + 3.5}" '
                         f'text-anchor="middle" style="font-size:9px;fill:{tc};animation-delay:{delay + 0.15:.2f}s">{v:.2f}</text>')
    svg = f'<svg class="chart" viewBox="0 0 {W} {H}" role="img" aria-label="因子载荷热图">' + "".join(parts) + "</svg>"
    return svg, ("旋转后因子载荷热图（SVG，蓝色 = 负载荷，红色 = 正载荷，颜色深浅 ∝ |载荷|）" + note_trunc)


def curves_svg(df: pd.DataFrame, xcol: str, ycol: str, gcol: str | None,
               panel_col: str | None, y01: bool, xlab: str, ylab: str,
               max_panels: int = 12) -> tuple[str, str]:
    """ICC / IIF / TIF 曲线：panel_col 存在时画小面板阵列，否则单面板多线。"""
    if df is None or df.empty or xcol not in df.columns or ycol not in df.columns:
        return "", ""
    note = ""
    panels: list[tuple[str, pd.DataFrame]] = []
    if panel_col and panel_col in df.columns:
        items = list(pd.unique(df[panel_col].astype(str)))
        if len(items) > max_panels:
            items, note = items[:max_panels], f"（项目较多，仅绘制前 {max_panels} 个）"
        panels = [(it, df[df[panel_col].astype(str) == it]) for it in items]
        cols_n = 4
        rows_n = math.ceil(len(panels) / cols_n)
        pw, ph, gap = 168, 122, 8
        W, H = 16 + cols_n * (pw + gap), 16 + rows_n * (ph + gap)
        single = False
    else:
        panels = [("", df)]
        W, H, pw, ph = 720, 300, 720 - 58 - 16, 300 - 30 - 44
        single = True
    parts = []
    for pi, (ptitle, sub) in enumerate(panels):
        if single:
            ox, oy, ml, mt = 0, 0, 58, 26
        else:
            ox = 16 + (pi % 4) * (pw + gap)
            oy = 16 + (pi // 4) * (ph + gap)
            ml, mt = 34, 8
        pww, phh = pw - ml - (8 if not single else 16), ph - mt - (26 if not single else 34)
        ys = [to_f(v) for v in sub[ycol]]
        xs = [to_f(v) for v in sub[xcol]]
        pts = [(x, y) for x, y in zip(xs, ys) if x is not None and y is not None]
        if not pts:
            continue
        xlo, xhi = min(p[0] for p in pts), max(p[0] for p in pts)
        yhi = 1.0 if y01 else max(p[1] for p in pts) * 1.06
        if xhi <= xlo:
            xhi = xlo + 1
        def PX(v):
            return ox + ml + pww * (v - xlo) / (xhi - xlo)
        def PY(v):
            return oy + mt + phh * (1 - (v / yhi))
        if not single:
            for tk in (0, 0.5, 1) if y01 else (0, yhi / 2):
                parts.append(f'<line class="grid" x1="{ox + ml}" y1="{PY(tk):.1f}" x2="{ox + ml + pww}" y2="{PY(tk):.1f}"/>')
            parts.append(svg_text(ox + ml - 4, oy + mt + 4, tick_txt(yhi), anchor="end", extra=' style="font-size:8px"'))
        else:
            for tk in nice_ticks(0, yhi, 5):
                parts.append(f'<line class="grid" x1="{ox + ml}" y1="{PY(tk):.1f}" x2="{ox + ml + pww}" y2="{PY(tk):.1f}"/>')
                parts.append(svg_text(ox + ml - 6, PY(tk) + 3.5, tick_txt(tk), anchor="end"))
        groups = [None]
        if gcol and gcol in sub.columns:
            groups = list(pd.unique(sub[gcol].astype(str)))[:8]
        for gi, g in enumerate(groups):
            gsub = sub if g is None else sub[sub[gcol].astype(str) == g]
            gp = [(PX(x), PY(y)) for x, y in zip(gsub[xcol], gsub[ycol])
                  if to_f(x) is not None and to_f(y) is not None]
            if len(gp) > 150:  # 降采样控制 SVG 体积
                gp = gp[:: math.ceil(len(gp) / 150)]
            gp = sorted(gp)
            color = "var(--accent)" if g is None else PAL[gi % len(PAL)]
            parts.append(draw_path(gp, color, 1.7, 0.15 + pi * 0.05 + gi * 0.08))
        parts.append(f'<line class="axs" x1="{ox + ml}" y1="{oy + mt + phh}" x2="{ox + ml + pww}" y2="{oy + mt + phh}"/>')
        if not single:
            parts.append(svg_text(ox + ml + pww / 2, oy + mt + phh + 18, trunc(ptitle, 16)))
        else:
            parts.append(svg_text(ox + ml + pww / 2, oy + mt + phh + 30, xlab, cls="axl"))
            parts.append(svg_text(ox + 20, oy + mt + phh / 2, ylab, cls="axl",
                                  extra=' transform="rotate(-90 %.1f %.1f)"' % (ox + 20, oy + mt + phh / 2)))
    svg = f'<svg class="chart" viewBox="0 0 {W} {H}" role="img" aria-label="{esc(ylab)}">' + "".join(parts) + "</svg>"
    return svg, f"{ylab}（SVG 重绘，横轴 {xlab}）{note}"


def mediation_svg(folder: Path, mid: str) -> str:
    """中介路径图：a / b / c′ 系数画三变量路径（数据：NN_mediation_paths.csv）。"""
    d = gsr.g1(folder, f"{mid}_paths")
    if d.empty or "path" not in d.columns:
        return ""
    def row_of(pred):
        hits = [r for _, r in d.iterrows() if pred(str(r["path"]))]
        return hits[0] if hits else None
    ra = row_of(lambda s: s.startswith("a "))
    rb = row_of(lambda s: s.startswith("b "))
    rc = row_of(lambda s: s.startswith("直接效应"))
    rt = row_of(lambda s: s.startswith("总效应"))
    if not (ra is not None and rb is not None and rc is not None):
        return ""
    names = {"X": "X", "M": "M", "Y": "Y"}
    cs = folder / "config_snapshot.json"
    if cs.exists():
        try:
            v = json.loads(cs.read_text(encoding="utf-8")).get("variables", {})
            names = {"X": v.get("x") or "X", "M": v.get("m") or "M", "Y": v.get("y") or "Y"}
        except Exception:
            pass
    W, H = 720, 330
    defs = ('<defs><marker id="arr" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" '
            'markerHeight="7" orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10 z" fill="#718096"/></marker></defs>')

    def coef(r):
        b, p = to_f(r.get("B")), to_f(r.get("p"))
        return f"{gsr.num(b, 3)}" + (f"（{gsr.result_report(p)}）" if p is not None else "")

    parts = [defs]
    boxes = {"X": (70, 196), "M": (300, 66), "Y": (530, 196)}
    for key, (bx, by) in boxes.items():
        parts.append(f'<g class="fadein" style="animation-delay:.1s"><rect x="{bx}" y="{by}" width="120" height="44" '
                     f'rx="8" fill="var(--card)" stroke="var(--accent)" stroke-width="1.4"/>'
                     + svg_text(bx + 60, by + 27, trunc(names[key], 10), cls="axl") + "</g>")
    arrows = [
        ((190, 196), (300, 110), ra, "a"),
        ((420, 110), (530, 196), rb, "b"),
        ((190, 218), (530, 218), rc, "c′"),
    ]
    for i, ((x0, y0), (x1, y1), r, lab) in enumerate(arrows):
        parts.append(f'<path class="draw" d="M{x0} {y0} L{x1} {y1}" fill="none" stroke="#718096" '
                     f'stroke-width="1.6" marker-end="url(#arr)" style="--len:{math.hypot(x1 - x0, y1 - y0):.0f};'
                     f'animation-delay:{0.5 + i * 0.35:.2f}s"/>')
        mx, my = (x0 + x1) / 2, (y0 + y1) / 2
        dy = -10 if lab != "c′" else 20
        parts.append(svg_text(mx, my + dy, f"{lab} = {coef(r)}"))
    lines = []
    if rt is not None:
        lines.append(f"总效应 c = {coef(rt)}")
    rab = row_of(lambda s: s.startswith("间接效应"))
    if rab is not None:
        lines.append(f"间接效应 ab = {gsr.num(to_f(rab.get('B')), 3)}")
    if lines:
        parts.append(svg_text(W / 2, H - 34, "；".join(lines)))
    parts.append(svg_text(W / 2, H - 14, "系数格式：B（p）；数据来自中介路径系数表", cls="axt"))
    svg = f'<svg class="chart" viewBox="0 0 {W} {H}" role="img" aria-label="中介路径图">' + "".join(parts) + "</svg>"
    return svg_figure(svg, "中介路径图（SVG，系数与 p 值来自 NN_mediation_paths.csv；c′ 上方间接效应见底部标注）")


def _first_num_col(df: pd.DataFrame) -> str | None:
    n = len(df)
    for c in df.columns:
        if "id" in str(c).lower():
            continue
        s = df[c]
        if not pd.api.types.is_numeric_dtype(s) or pd.api.types.is_bool_dtype(s):
            continue
        nu = s.nunique(dropna=True)
        if nu < 6:
            continue
        if nu == n and n > 10 and (s.dropna() % 1 == 0).all():
            continue  # 逐行唯一的整数列多半是编号，不是测量变量
        return c
    return None


def histogram_svg_data(series: pd.Series, label: str, src: str) -> str:
    """真实数据直方图（柱从 0 生长）：bins 内计数全部来自 CSV 数值。"""
    vals = [to_f(v) for v in series]
    vals = [v for v in vals if v is not None]
    if len(vals) < 8:
        return ""
    lo, hi = min(vals), max(vals)
    if hi <= lo:
        return ""
    nb = 18
    cnt = [0] * nb
    for v in vals:
        k = min(nb - 1, int((v - lo) / (hi - lo) * nb))
        cnt[k] += 1
    mean = sum(vals) / len(vals)
    W, H, ml, mr, mt, mb = 720, 300, 58, 16, 26, 46
    pw, ph = W - ml - mr, H - mt - mb
    ymax = max(cnt) * 1.1
    parts = []
    for tk in nice_ticks(0, ymax, 5):
        y = mt + ph * (1 - tk / ymax)
        parts.append(f'<line class="grid" x1="{ml}" y1="{y:.1f}" x2="{W - mr}" y2="{y:.1f}"/>')
        parts.append(svg_text(ml - 6, y + 3.5, tick_txt(int(tk)) if float(tk).is_integer() else tick_txt(tk), anchor="end"))
    bw = pw / nb
    for i, c in enumerate(cnt):
        if c == 0:
            continue
        hgt = ph * c / ymax
        parts.append(f'<rect class="bar" x="{ml + i * bw + 1:.1f}" y="{mt + ph - hgt:.1f}" '
                     f'width="{bw - 2:.1f}" height="{hgt:.1f}" fill="var(--accent)" fill-opacity=".55" '
                     f'style="animation-delay:{i * 0.03:.2f}s"/>')
    ym = mt + ph * (1 - 0.06)
    parts.append(f'<line x1="{ml + pw * (mean - lo) / (hi - lo):.1f}" y1="{mt}" x2="{ml + pw * (mean - lo) / (hi - lo):.1f}" '
                 f'y2="{ym:.1f}" stroke="var(--accent2)" stroke-width="1.3" stroke-dasharray="5 4"/>')
    parts.append(f'<line class="axs" x1="{ml}" y1="{mt + ph}" x2="{W - mr}" y2="{mt + ph}"/>')
    for v, anchor in ((lo, "start"), (mean, "middle"), (hi, "end")):
        parts.append(svg_text(ml + pw * (v - lo) / (hi - lo), mt + ph + 16,
                              ("M = " if v == mean and abs(v - mean) < 1e-12 else "") + gsr.num(v), anchor=anchor))
    parts.append(svg_text(W / 2, H - 6, f"{trunc(label, 24)}（N = {len(vals)}）", cls="axl"))
    parts.append(svg_text(ml - 42, mt + ph / 2, "频数", cls="axl",
                          extra=' transform="rotate(-90 %d %.1f)"' % (ml - 42, mt + ph / 2)))
    svg = f'<svg class="chart" viewBox="0 0 {W} {H}" role="img" aria-label="直方图">' + "".join(parts) + "</svg>"
    return svg_figure(svg, f"直方图（SVG，真实数据：{src} 的 {label} 列，N = {len(vals)}，18 个等距分组；橙色虚线为均值）")


def histogram_svg_desc(row: dict, src: str) -> str:
    """无逐行数据时的示意直方图：形状按真实 M/SD 生成并明确标注“示意”。"""
    mean, sd = to_f(row.get("mean")), to_f(row.get("sd"))
    vmin, vmax = to_f(row.get("min")), to_f(row.get("max"))
    if mean is None or sd is None or vmin is None or vmax is None or not (sd > 0) or vmax <= vmin:
        return ""
    W, H, ml, mr, mt, mb = 720, 280, 56, 16, 26, 48
    pw, ph = W - ml - mr, H - mt - mb
    pad = (vmax - vmin) * 0.06
    lo, hi = vmin - pad, vmax + pad
    nb = 22
    scale = ph * 0.86 / _norm_pdf(mean, mean, sd)
    parts = []
    for tk in (vmin, mean, vmax):
        parts.append(f'<line class="grid" x1="{ml + pw * (tk - lo) / (hi - lo):.1f}" y1="{mt}" '
                     f'x2="{ml + pw * (tk - lo) / (hi - lo):.1f}" y2="{mt + ph}"/>')
        parts.append(svg_text(ml + pw * (tk - lo) / (hi - lo), mt + ph + 16, gsr.num(tk)))
    for i in range(nb):
        c = lo + (hi - lo) * (i + 0.5) / nb
        hgt = _norm_pdf(c, mean, sd) * scale
        if hgt < 1:
            continue
        bx = ml + pw * (i / nb)
        parts.append(f'<rect class="bar" x="{bx + 1:.1f}" y="{mt + ph - hgt:.1f}" width="{pw / nb - 2:.1f}" '
                     f'height="{hgt:.1f}" fill="var(--accent)" fill-opacity=".45" '
                     f'style="animation-delay:{i * 0.025:.2f}s"/>')
    parts.append(f'<line class="axs" x1="{ml}" y1="{mt + ph}" x2="{W - mr}" y2="{mt + ph}"/>')
    parts.append(svg_text(W / 2, H - 6, f"{trunc(row['variable'], 22)}（示意：按真实 M/SD 绘制，非逐行数据）", cls="axl"))
    svg = f'<svg class="chart" viewBox="0 0 {W} {H}" role="img" aria-label="示意直方图">' + "".join(parts) + "</svg>"
    return svg_figure(svg, ("示意直方图（SVG）：结果目录未含该变量的逐行数据（NN_方法_data.csv），"
                            f"柱形按真实描述统计（M = {gsr.num(mean)}，SD = {gsr.num(sd)}，"
                            f"范围 [{gsr.num(vmin)}, {gsr.num(vmax)}]，来源 {src}）绘制，仅展示分布形态。"))


# ── 页脚：复现与运行环境（读 run_manifest.json，字段缺失留空）─────────
def repro_section(folder: Path, branch: str) -> str:
    m = load_manifest(folder)
    ver = m.get("psychostat_version") or m.get("version") or m.get("app_version") or ""
    rows = [
        ("软件版本", str(ver) if ver else "—（run_manifest.json 未记录）"),
        ("R 版本", str(m.get("r_version", "")) or "—"),
        ("运行时间", str(m.get("timestamp", "")) or "—"),
        ("随机种子", str(m.get("seed", "")) if m.get("seed") is not None else "—"),
        ("操作系统", str(m.get("os", "")) or "—"),
        ("结果目录", str(folder.resolve())),
    ]
    if branch == "stats":
        repro = ("把各模块的 NN_方法_data.csv（UTF-8-BOM 编码）导入 SPSS（文件 > 导入数据 > CSV），"
                 "按每节给出的\u201cSPSS 菜单路径\u201d点击运行，统计量应与本报告各表一致"
                 "（t/F/χ²/H 等在小数点后 2-3 位完全一致）。")
    elif branch == "ctt":
        repro = ("清洗后的题目数据见 01_cleaned_items.csv；逐项分析参数与路线（EFA/CFA）记录在 "
                 "run_log.txt 与配置快照中。报告中的自动阈值仅用于初筛，复现与删题决策请结合理论。")
    else:
        repro = ("数据来源、项目列、模型、估计器与输出设置均保存在 config_snapshot.yaml 中；"
                 "逐人能力估计见 *_ability_estimates.csv，以支持可复现性。")
    kv = "".join(f"<tr><th>{esc(k)}</th><td>{esc(v)}</td></tr>" for k, v in rows)
    return (
        '<table class="kv"><tbody>' + kv + "</tbody></table>"
        f"<p>复现说明：{esc(repro)}</p>"
        "<p class=\"note\">本文件为自包含 HTML（无外链、图片内嵌），可离线打开与归档；"
        "由 scripts/generate_html_report.py 自动生成，数值均来自结果目录的 CSV 产物。</p>"
    )


# ═══════════════════════ stats 分支 ═══════════════════════
def build_stats(folder: Path) -> str:
    reg = gsr.build_registry()
    methods = gsr.present_methods(folder)
    if not methods:
        raise RuntimeError("结果目录中未发现任何方法产物（NN_方法_*.csv）与数据准备产物（00_prep_*.csv）。")
    nav: list[tuple[str, str]] = []
    secs: list[str] = []
    names = "、".join(f"{m[1]}" for m in methods)
    summary_paras = [
        f"本报告基于 {len(methods)} 个统计模块自动生成：{names}。各模块的数据文件（NN_方法_data.csv，UTF-8-BOM）可直接导入SPSS复现；"
        "每节先给文字说明（这个方法做什么、数据长什么样、结果如何、结论是什么），随后附上该方法产生的全部表格与图形。",
        "自动生成初稿｜每节含文字说明（方法—数据—结果—结论）与全部结果表（三线表）；请核对后用于正式报告。统计实现与IBM SPSS默认参数一致。",
    ]
    fail_note = gsr.failed_methods_note(folder, zh=True)
    if fail_note:
        summary_paras.append(fail_note)
    nav.append(("sec-summary", "摘要"))
    secs.append(section_html("sec-summary", "摘要", "".join(f"<p>{esc(p)}</p>" for p in summary_paras)))
    no = 0  # 表/图共用同一计数器（与 Word 生成器一致）
    for idx, mid in methods:
        label = STATS_METHODS.get(mid, (mid, ""))[0]
        spss = STATS_METHODS.get(mid, ("", ""))[1]
        sid = "sec-0" if mid == "datacheck" else f"sec-{idx}-{mid}"
        if mid == "datacheck":
            title = "第 0 节 数据准备（数据健康与异常值筛查）"
            nav_label = "第 0 节 数据准备"
        else:
            title = f"{idx}. {label}（{mid}）"
            nav_label = f"{idx}. {label}"
        nav.append((sid, nav_label))
        inner: list[str] = []
        if spss:
            inner.append(f'<div class="spss"><b>SPSS 菜单路径：</b>{esc(spss)}</div>')
        zh_paras, _ = reg[mid](folder)
        inner.extend(f"<p>{esc(p)}</p>" for p in zh_paras if p)
        if mid == "datacheck":
            hc = health_card(folder)
            if hc:
                inner.append('<h3>数据健康卡（原始 N → 插补 → 删除 → 最终 N）</h3>' + hc)
            else:
                inner.append('<div class="skipnote">未找到 00_prep_preparation_summary.csv，数据健康卡 skipped。</div>')
            imp = imputation_teaching(folder)
            if imp:
                inner.append("<h3>均值插补教学动画（分布向中心收缩）</h3>" + imp)
            else:
                inner.append('<div class="skipnote">结果目录缺少描述统计或插补计数 CSV，均值插补教学动画 skipped。</div>')
        # 全部结果表（匹配规则与 Word 生成器完全一致；*_data.csv 不进正文）
        for pth, (cz, _) in gsr.method_tables(folder, mid):
            no += 1
            inner.append(table_html(read_csv_relaxed(pth), f"表{no} {cz}（{mid}）",
                                    p_matrix=("matrix_p_" in pth.stem), max_rows=gsr.MAX_TABLE_ROWS))
        # 方法专属 SVG（重绘图不占 Word 报告的图表编号，放在对应 PNG 之前）
        if mid == "datacheck":
            svg, cap = boxplot_svg(folder)
            if svg:
                inner.append("<h3>异常值箱线图（按规则分色）</h3>" + svg_figure(svg, cap))
            else:
                inner.append('<div class="skipnote">缺少 00_prep_outlier_summary.csv（或必要列），箱线图 SVG skipped。</div>')
        if mid == "mediation":
            msvg = mediation_svg(folder, mid)
            if msvg:
                inner.append("<h3>中介路径图</h3>" + msvg)
        # 直方图：优先逐行真实数据，其次真实描述统计（标注“示意”）。
        # datacheck 节已有“均值插补教学动画”，不再重复画同源的示意直方图。
        data_csvs = sorted(glob.glob(str(folder / f"??_{mid}_data.csv")))
        hist = ""
        if data_csvs:
            ddf = read_csv_relaxed(data_csvs[0])
            col = _first_num_col(ddf) if not ddf.empty else None
            if col:
                hist = histogram_svg_data(ddf[col], col, Path(data_csvs[0]).name)
        elif mid != "datacheck":
            desc = _collect_desc_rows(folder)
            if desc:
                hist = histogram_svg_desc(desc[0], desc[0]["src"])
        if hist:
            inner.append(hist)  # SVG 重绘图：不占表/图编号，编号留给表格与 PNG（与 Word 生成器一致）
        # 已有 PNG 诊断图（base64 内嵌），SVG 优先放在其前。
        # 额外补抓 00_prep_boxplots.png（复数）——Word 生成器的 FIG_SUFFIXES 只匹配单数
        # boxplot，会漏掉管线实际文件名；本生成器按规格要求内嵌目录里已有的诊断 PNG。
        embedded: set[str] = set()
        if mid == "datacheck":
            for hit in sorted(glob.glob(str(folder / "00_prep_boxplot*.png"))):
                no += 1
                embedded.add(Path(hit).name)
                inner.append(png_figure(folder, Path(hit).name, "箱线图（datacheck）", no))
        for sfx, (fz, _) in gsr.FIG_SUFFIXES.items():
            fig_pat = f"00_prep_{sfx}.png" if mid == "datacheck" else f"??_{mid}_{sfx}.png"
            for hit in sorted(glob.glob(str(folder / fig_pat))):
                if Path(hit).name in embedded:
                    continue
                no += 1
                embedded.add(Path(hit).name)
                inner.append(png_figure(folder, Path(hit).name, f"{fz}（{mid}）", no))
        secs.append(section_html(sid, title, "".join(inner)))
    nav.append(("sec-repro", "复现与运行环境"))
    secs.append(section_html("sec-repro", "复现与运行环境", repro_section(folder, "stats")))
    return assemble_page("Psychostat 心理统计分析报告",
                         "自包含 HTML 版｜自动生成初稿，请核对后用于正式报告",
                         nav, "\n".join(secs))


# ═══════════════════════ CTT 分支（结构与措辞镜像 generate_ctt_report.py）═══════════════════════
CTT_SUBTITLE = "自动生成初稿｜请结合量表理论、内容效度与独立样本复核后用于正式报告。"
CTT_CLEAN_RULE = ("规则：个体缺失率 <5% 采用题目中位数插补；>20% 剔除；5%–20% 不自动决定，须在配置中明确选择 listwise 或 median_impute。"
                  "反向题按 k + 1 − 原始得分换算。注意力题、过短作答时间、直线作答和总分极端值均保留审计记录。")
CTT_ITEM_NOTE = ("使用总分前后 27% 极端组进行独立样本 t 检验。CR 决断值主列（CR_t、df、p）采用合并方差 t 检验"
                 "（df = n高 + n低 − 2，与 SPSS/教材决断值口径一致）；Welch 校正结果另见 CR_t_welch、df_welch 列。"
                 "建议保留 CR > 3 且 p < .05、并且校正后题总相关（CITC）>.30 的题目；自动建议不应取代内容效度审查。")
CTT_REL_NOTE = ("Cronbach’s α > .70 视为可接受；若删除某题后 α 上升 > .05，工具给出删题建议。alpha_ci_lower/alpha_ci_upper 为 α 的 95% 正态近似置信区间；"
                "omega 为单因子 McDonald’s ω（计算失败或题目不足时为 NA）。若提供校标变量，将检验相关方向和显著性；"
                "若提供已知组变量，将进行 Welch t 检验或单因素方差分析并报告效应量。")
CTT_EFA_NOTE = ("EFA 的前提通常为 KMO > .60 且 Bartlett 球形检验 p < .05（本工具在未达标时给出警告并继续分析，提醒解读需谨慎）。"
                "因子数默认采用平行分析确定（以碎石图辅助判断，可由配置显式指定）；本流程使用配置的 Varimax 或 Promax 旋转。"
                "主载荷<.40、交叉载荷、共同度<.20 或因子题数不足的题目仅作“建议删除”标注，不会自动删除——是否删题由研究者结合理论决定。累计方差应超过 50%。")
CTT_CFA_NOTE = ("CFA 判断标准为 χ²/df<5、CFI/TLI>.90、RMSEA<.08、SRMR<.08；聚合效度要求标准化载荷>.50、CR>.70、AVE>.50；"
                "区分效度要求因子相关<.85 且 AVE 平方根大于因子间相关。本次若直接以同一样本 EFA 结构进行 CFA，"
                "结果仅为探索性内部验证；正式验证应使用独立样本或预先指定模型。")
CTT_LIMIT = ("自动阈值仅用于初筛。删题前应复核理论涵义、内容覆盖和题目措辞；不要仅因统计阈值而删除核心内容。"
             "缺失的机制（MCAR/MAR/MNAR）、样本量、Likert 数据的有序性质及模型识别均会影响结果。"
             "若 EFA 和 CFA 使用同一批数据，不能作为严格的验证性证据。")
CTT_SOURCE = "来源说明：本报告的表格、统计量和图形来自 Psychostat 的 R 分析输出；报告语言为自动生成草稿。"


def build_ctt(folder: Path) -> str:
    t = {k: read_csv_relaxed(folder / f"{k}.csv") for k in [
        "01_cleaning_summary", "01_case_cleaning_audit", "02_item_analysis", "03_reliability",
        "03_alpha_if_deleted", "03_criterion_validity", "03_known_group_validity",
        "04_efa_diagnostics", "04_efa_rotated_loadings", "04_efa_variance",
        "04_efa_deletion_history", "04_efa_item_dimension_mapping", "05_cfa_fit",
        "05_cfa_loadings", "05_cfa_convergent_validity", "05_cfa_discriminant_validity",
        "05_cfa_factor_correlations", "05_fornell_larcker", "06_cfa_modification_indices"]}
    nav, secs = [], []
    no_tab = 0
    no_fig = 0

    def add_section(sid, title, inner):
        nav.append((sid, title))
        secs.append(section_html(sid, title, inner))

    def tbl(df, title, note=None, max_rows=50):
        nonlocal no_tab
        no_tab += 1
        return table_html(df, f"表{no_tab} {title}", max_rows=max_rows, note=note)

    def fig_png(name, caption):
        nonlocal no_fig
        no_fig += 1
        return png_figure(folder, name, caption, no_fig)

    def fig_svg(pair, fallback_note=""):
        # SVG 是“重绘图”，不占用 Word 报告的图号（PNG 编号与 Word 生成器保持一致）
        svg, cap = pair
        if svg:
            return svg_figure(svg, cap)
        return f'<div class="skipnote">{esc(fallback_note)}</div>'

    # 摘要（动态句与 Word 生成器一致）
    abs_paras = []
    if not t["01_cleaning_summary"].empty:
        r = t["01_cleaning_summary"].iloc[0]
        abs_paras.append(f"本分析对 {int(r.raw_n)} 名被试的量表数据进行了预设的 CTT 流程：数据清洗、项目分析、信效度检验、"
                         "探索性因子分析（EFA）和验证性因子分析（CFA）。清洗后保留 "
                         f"{int(r.retained_n)} 名被试；以下自动输出仅作为量表修订的量化证据，不能替代题目内容与理论判断。")
    add_section("sec-summary", "摘要", "".join(f"<p>{esc(p)}</p>" for p in abs_paras))

    inner = [f"<p>{esc(CTT_CLEAN_RULE)}</p>"]
    if not t["01_case_cleaning_audit"].empty:
        inner.append(tbl(mask_person_ids(t["01_case_cleaning_audit"]),
                         "逐被试清洗审计（01_case_cleaning_audit.csv）",
                         note=PERSON_TABLE_NOTE, max_rows=200))
    inner.append(tbl(t["01_cleaning_summary"], "数据清洗汇总"))
    add_section("sec-1", "1. 数据清洗与质量控制", "".join(inner))

    add_section("sec-2", "2. 项目分析",
                f"<p>{esc(CTT_ITEM_NOTE)}</p>" + tbl(t["02_item_analysis"], "项目区分度与 CITC", max_rows=50))

    inner = [f"<p>{esc(CTT_REL_NOTE)}</p>", tbl(t["03_reliability"], "Cronbach’s α")]
    if (not t["03_reliability"].empty and "source" in t["03_reliability"].columns
            and t["03_reliability"]["source"].astype(str).str.contains("EFA-derived", na=False).any()):
        inner.append("<p>注意：分量表维度来自同一批数据的 EFA，其 α 偏乐观，应在独立样本验证后再报告。</p>")
    inner.append(tbl(t["03_alpha_if_deleted"], "删除项目后的 α"))
    inner.append(tbl(t["03_criterion_validity"], "校标关联效度"))
    inner.append(tbl(t["03_known_group_validity"], "已知组效度"))
    add_section("sec-3", "3. 信度与外部效度", "".join(inner))

    inner = [f"<p>{esc(CTT_EFA_NOTE)}</p>",
             tbl(t["04_efa_diagnostics"], "EFA 前提检验"),
             tbl(t["04_efa_variance"], "EFA 方差解释"),
             tbl(t["04_efa_deletion_history"], "EFA 建议删除题目标注（仅标注，未自动删除）")]
    # 碎石图：CTT 管线未把特征值写入 CSV（04_efa_variance.csv 无特征值列）→ SVG 跳过并说明
    scree_available = scree_svg(t["04_efa_variance"])[0] != ""
    if scree_available:
        inner.append(fig_svg(scree_svg(t["04_efa_variance"])))
    else:
        inner.append('<div class="skipnote">CTT 结果目录未导出特征值 CSV（04_efa_variance.csv 无特征值列），'
                     'SVG 碎石图 skipped；下图 PNG 碎石图为管线真实绘图。</div>')
    inner.append(fig_png("efa_scree_plot.png", "碎石图。虚线表示特征值 1。"))
    inner.append(fig_svg(heatmap_svg(t["04_efa_rotated_loadings"]),
                         "旋转后载荷宽表缺失，载荷热图 SVG skipped。"))
    inner.append(fig_png("efa_loading_heatmap.png", "旋转后因子载荷热图。"))
    inner.append(tbl(t["04_efa_rotated_loadings"], "旋转后因子载荷", max_rows=50))
    if not t["04_efa_item_dimension_mapping"].empty:
        inner.append(tbl(t["04_efa_item_dimension_mapping"], "题目-维度映射（04_efa_item_dimension_mapping.csv）"))
    add_section("sec-4", "4. 探索性因子分析（EFA）", "".join(inner))

    inner = [f"<p>{esc(CTT_CFA_NOTE)}</p>", tbl(t["05_cfa_fit"], "CFA 拟合指标"),
             fig_svg(heatmap_svg(t["05_cfa_loadings"]), "CFA 载荷表缺失，热图 SVG skipped。"),
             tbl(t["05_cfa_loadings"], "CFA 标准化载荷与显著性（heywood_warning=TRUE 表示该行载荷绝对值>1 或方差估计为负，属不合规解，需谨慎报告）", max_rows=50),
             tbl(t["05_cfa_convergent_validity"], "聚合效度"),
             tbl(t["05_cfa_discriminant_validity"], "区分效度")]
    if not t["05_cfa_factor_correlations"].empty:
        inner.append(tbl(t["05_cfa_factor_correlations"], "因子相关（05_cfa_factor_correlations.csv）"))
    if not t["05_fornell_larcker"].empty:
        inner.append(tbl(t["05_fornell_larcker"], "Fornell-Larcker 准则矩阵（05_fornell_larcker.csv）"))
    if not t["06_cfa_modification_indices"].empty:
        inner.append(tbl(t["06_cfa_modification_indices"], "修正指数（前 20，06_cfa_modification_indices.csv）", max_rows=20))
    inner.append(fig_png("cfa_path_diagram.png", "CFA 标准化路径图。"))
    add_section("sec-5", "5. 验证性因子分析（CFA）", "".join(inner))

    par = []
    if not t["03_reliability"].empty:
        alpha_total = t["03_reliability"].iloc[0].get("alpha", float("nan"))
        par.append(f"量表总分的内部一致性为 Cronbach’s α = {gsr.fmt(to_f(alpha_total))}。项目分析按总分前后 27% 的极端组进行"
                   "（CR 决断值为合并方差 t 检验，df = n高 + n低 − 2），题目保留建议同时依据 CR > 3、p < .05 与 CITC > .30。")
    if not t["04_efa_diagnostics"].empty:
        d = t["04_efa_diagnostics"].iloc[0]
        par.append(f"EFA 前提检验显示 KMO = {gsr.fmt(to_f(d.get('KMO')))}，Bartlett 球形检验 "
                   f"χ²({gsr.fmt(to_f(d.get('Bartlett_df')))}) = {gsr.fmt(to_f(d.get('Bartlett_chisq')))}, "
                   f"p {gsr.fmt(to_f(d.get('Bartlett_p')))}。")
    if not t["05_cfa_fit"].empty:
        f = t["05_cfa_fit"].iloc[0]
        par.append(f"CFA 的拟合为 χ²({gsr.fmt(to_f(f.get('df')))}) = {gsr.fmt(to_f(f.get('chisq')))}，"
                   f"χ²/df = {gsr.fmt(to_f(f.get('chisq_df')))}，CFI = {gsr.fmt(to_f(f.get('CFI')))}，"
                   f"TLI = {gsr.fmt(to_f(f.get('TLI')))}，RMSEA = {gsr.fmt(to_f(f.get('RMSEA')))}，"
                   f"SRMR = {gsr.fmt(to_f(f.get('SRMR')))}。")
    add_section("sec-6", "6. 结果段落（可编辑初稿）", "".join(f"<p>{esc(p)}</p>" for p in par))
    add_section("sec-7", "7. 解释限制与建议", f"<p>{esc(CTT_LIMIT)}</p><p>{esc(CTT_SOURCE)}</p>")
    add_section("sec-repro", "复现与运行环境", repro_section(folder, "ctt"))
    return assemble_page("Psychostat 经典测量理论（CTT）分析报告", CTT_SUBTITLE, nav, "\n".join(secs))


# ═══════════════════════ IRT 分支（结构与措辞镜像 generate_result_reports.py）═══════════════════════
IRT_MISSING_NOTE = ("缺失单元格数与缺失比例（Missing_cells_before / Missing_pct_before）在剔除整行全缺失被试之前统计；"
                    "All_missing_removed 为剔除的整行全缺失被试数。pairwise 与 none 对模型拟合等价"
                    "（均基于观测反应模式、不做插补），pairwise 仅影响维度启发式中的成对相关（pairwise.complete.obs）。")
IRT_OVERVIEW_NOTE = "Missing_pct 为进入模型分析样本中各项目的缺失百分比。"
IRT_MODELS_NOTE = "AIC、BIC 与 SABIC 越低表示相对拟合越好。"
IRT_PARAMS_NOTE = "阈值参数位于模型潜变量量尺上。"
IRT_FIT_NOTE = "BH 校正后的 p 值用于提示后续核查，而非自动删除项目。"
IRT_THETA_NOTE = "MAP 能力估计位于拟合模型的潜变量量尺上；N_valid 为该维度上有效（非缺失）估计的人数。"
IRT_REL_NOTE = ("边际信度（marginal_rxx）基于模型隐含的误差分布，仅适用于单维模型；"
                "经验信度（empirical_rxx）基于 MAP 能力估计值及其标准误逐维度计算；NA 表示当前模型/估计方式下不可用。")
IRT_CORR_NOTE = "对角线为 1.00。"
IRT_DISCUSSION = ("模型选择反映当前数据与预设比较准则，不能替代理论驱动的结构评估。"
                  "建议进一步评估反向计分、局部独立性、DIF、外部效标及跨样本稳定性。"
                  "能力估计采用 MAP（最大后验）方法，存在向均值收缩（回归均值）的倾向，极端能力会被低估；解读极端组时应结合标准误（SE）。"
                  "表格采用 结果报告风格三线表，图形以 300 dpi PNG 保存。")
IRT_METHOD = "数据来源、项目列、模型、估计器、迭代上限与输出设置均保存在 config_snapshot.yaml 中，以支持可复现性。"
IRT_FIG_CAPS = ["图 1. 项目反应分布。", "图 2. 项目特征曲线（MIRT 为条件切片）。",
                "图 3. 项目信息函数（MIRT 为条件切片）。", "图 4. 测验信息函数（MIRT 为条件切片）。",
                "图 5. MAP 能力估计分布。"]


def build_irt(folder: Path) -> tuple[str, str]:
    matches = sorted(glob.glob(str(folder / "*_model_comparison.csv")))
    if len(matches) != 1:
        raise RuntimeError(f"IRT 结果目录应恰好包含一个 *_model_comparison.csv，实际找到 {len(matches)} 个。")
    prefix = Path(matches[0]).name[:-len("_model_comparison.csv")]

    def rd(suffix):
        return read_csv_relaxed(folder / f"{prefix}_{suffix}.csv")

    models, overview, params = rd("model_comparison"), rd("item_overview"), rd("item_parameters")
    theta, missing = rd("ability_summary"), rd("missingness_summary")
    item_fit, reliability, corr = rd("item_fit"), rd("reliability"), rd("dimension_correlations")
    person_missing, rec = rd("person_missingness"), rd("model_recommendation")
    eifa_cmp, eifa_load, eifa_eig = rd("eifa_dimension_comparison"), rd("eifa_rotated_loadings"), rd("eifa_eigenvalues")
    cifa_load, cifa_sig, cifa_cmp = rd("cifa_loading_matrix"), rd("cifa_loading_significance"), rd("cifa_vs_unidimensional")
    icc_d, iif_d, tif_d = rd("icc_data"), rd("iif_data"), rd("tif_data")

    selected = str(models.iloc[0]["Model"]) if not models.empty else "not available"
    abstract = (f"本报告比较了配置的 IRT 候选模型，并按预设准则选择 {selected}。"
                "报告呈现数据与缺失值描述、模型拟合、项目参数和能力估计。"
                "实质性解释仍应结合量表理论、题目内容和研究设计。")
    nav, secs = [], []
    no_tab = 0

    def add_section(sid, title, inner):
        nav.append((sid, title))
        secs.append(section_html(sid, title, inner))

    def tbl(df, title, note=None, max_rows=200):
        nonlocal no_tab
        no_tab += 1
        return table_html(df, f"表{no_tab} {title}", max_rows=max_rows, note=note)

    add_section("sec-summary", "摘要", f"<p>{esc(abstract)}</p>")
    add_section("sec-method", "方法", f"<p>{esc(IRT_METHOD)}</p>")

    inner = [tbl(missing, "数据与缺失值概览", IRT_MISSING_NOTE)]
    if not person_missing.empty:
        inner.append(tbl(mask_person_ids(person_missing), "逐被试缺失概览（person_missingness.csv）",
                         note=PERSON_TABLE_NOTE, max_rows=100))
    add_item = rd("item_missingness")
    if not add_item.empty:
        inner.append(tbl(add_item, "逐项目缺失概览（item_missingness.csv）"))
    add_section("sec-missing", "数据与缺失值概览", "".join(inner))
    add_section("sec-overview", "项目反应概览", tbl(overview, "项目反应概览", IRT_OVERVIEW_NOTE))

    inner = [tbl(models, "候选模型比较与整体拟合", IRT_MODELS_NOTE)]
    if not rec.empty:
        inner.append(tbl(rec, "模型选择建议（model_recommendation.csv）"))
    if not reliability.empty:
        inner.append(tbl(reliability, "信度估计", IRT_REL_NOTE))
    inner.append(tbl(params, "项目参数", IRT_PARAMS_NOTE))
    if not eifa_cmp.empty:
        inner.append(tbl(eifa_cmp, "探索性维度比较（EIFA）", "按 BIC 排序；较低值表示更优的相对拟合。"))
    if not eifa_load.empty:
        hm = heatmap_svg(eifa_load)
        inner.append(svg_figure(hm[0], hm[1]) if hm[0] else
                     '<div class="skipnote">eifa_rotated_loadings.csv 缺少可用的载荷矩阵，热图 SVG skipped。</div>')
        inner.append(tbl(eifa_load, "旋转后因子载荷（EIFA）", "采用 oblimin 斜交旋转；h2 为共同度。"))
    if not eifa_eig.empty:
        sc = scree_svg(eifa_eig)
        inner.append(svg_figure(sc[0], sc[1] + " 数据：eifa_eigenvalues.csv，基于项目反应相关矩阵，仅作维度探索的辅助证据。")
                     if sc[0] else '<div class="skipnote">eifa_eigenvalues.csv 无特征值列，碎石图 SVG skipped。</div>')
    if not cifa_load.empty:
        hm = heatmap_svg(cifa_load)
        inner.append(svg_figure(hm[0], hm[1]) if hm[0] else
                     '<div class="skipnote">cifa_loading_matrix.csv 缺少可用载荷矩阵，热图 SVG skipped。</div>')
        inner.append(tbl(cifa_load, "约束后因子载荷（CIFA）", "未指定的交叉载荷在模型中固定为零。"))
    if not cifa_sig.empty:
        inner.append(tbl(cifa_sig, "载荷显著性检验（CIFA）", "z = 载荷估计值 / 标准误；p 值为双侧 Wald 近似。"))
    if not cifa_cmp.empty:
        inner.append(tbl(cifa_cmp, "CIFA 与单维模型比较",
                         "Δ 值定义为 CIFA − 单维模型；CFI 增加、RMSEA/AIC/BIC 减少通常支持多维结构。"))
    if not item_fit.empty:
        inner.append(tbl(item_fit, "项目拟合诊断", IRT_FIT_NOTE))
    inner.append(tbl(theta, "能力估计描述统计", IRT_THETA_NOTE))
    if not corr.empty:
        inner.append(tbl(corr, "潜变量维度相关矩阵", IRT_CORR_NOTE))
    add_section("sec-results", "结果", "".join(inner))

    # 图形：SVG 重绘（数据来自 *_icc_data.csv 等）放在对应 PNG 之前
    figs = []
    for suffix, cap in zip(["response_distributions", "icc", "iif", "tif", "theta_distribution"], IRT_FIG_CAPS):
        if suffix == "icc" and not icc_d.empty:
            cv = curves_svg(icc_d, "Theta", "Probability", "Category", "Item", True, "Theta", "项目特征曲线（ICC）")
            figs.append(svg_figure(cv[0], cv[1] + " 数据：icc_data.csv。") if cv[0] else "")
        if suffix == "iif" and not iif_d.empty:
            cv = curves_svg(iif_d, "Theta", "Information", None, "Item", False, "Theta", "项目信息函数（IIF）")
            figs.append(svg_figure(cv[0], cv[1] + " 数据：iif_data.csv。") if cv[0] else "")
        if suffix == "tif" and not tif_d.empty:
            cv = curves_svg(tif_d, "Theta", "Information", "Dimension", None, False, "Theta", "测验信息函数（TIF）")
            figs.append(svg_figure(cv[0], cv[1] + " 数据：tif_data.csv。") if cv[0] else "")
        if suffix == "theta_distribution":
            est = read_csv_relaxed(folder / f"{prefix}_ability_estimates.csv")
            col = _first_num_col(est) if not est.empty else None
            if col:
                figs.append(histogram_svg_data(est[col], col, f"{prefix}_ability_estimates.csv"))
        figs.append(png_figure(folder, f"{prefix}_{suffix}.png", cap))
    add_section("sec-figs", "图形", "".join(f for f in figs if f))
    add_section("sec-discussion", "讨论与限制", f"<p>{esc(IRT_DISCUSSION)}</p>")
    add_section("sec-repro", "复现与运行环境", repro_section(folder, "irt"))
    doc = assemble_page("通用 IRT 自动分析报告", "自包含 HTML 版｜自动生成初稿，请结合理论与设计解读",
                        nav, "\n".join(secs))
    # 启动器与 GUI 按固定名 irt_report_zh.html 查找并自动打开（stats/ctt 同理用固定名）；
    # Word 侧沿用 <prefix>_report_zh.docx 不变，HTML 不镜像其前缀命名。
    return doc, "irt_report_zh.html"


# ── main：CLI 契约 + 原子写盘（失败不留半截 html）────────────────────
def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
    if hasattr(sys.stderr, "reconfigure"):
        sys.stderr.reconfigure(encoding="utf-8", errors="backslashreplace")
    ap = argparse.ArgumentParser(description="由结果目录生成自包含 HTML 报告")
    ap.add_argument("--result-dir-utf8-base64", required=True,
                    help="结果目录的 UTF-8 Base64 编码（与现有生成器同款传参）")
    args = ap.parse_args()
    try:
        folder = Path(base64.b64decode(args.result_dir_utf8_base64, validate=True).decode("utf-8"))
    except (ValueError, UnicodeDecodeError) as e:
        print(f"[错误] --result-dir-utf8-base64 参数无效：{e}", file=sys.stderr)
        raise SystemExit(2)
    if not folder.is_dir():
        print(f"[错误] 结果目录不存在：{folder}", file=sys.stderr)
        raise SystemExit(2)
    branch = detect_branch(folder)
    if branch is None:
        print(f"[错误] 未识别的结果目录（既无 stats 的 stats_report_zh.md/00_prep_*，也无 CTT 的 01_cleaning_summary.csv，"
              f"也无 IRT 的 *_model_comparison.csv 等产物）：{folder}；不猜测分支，已退出。", file=sys.stderr)
        raise SystemExit(3)
    try:
        if branch == "stats":
            doc, out_name = build_stats(folder), "stats_report_zh.html"
        elif branch == "ctt":
            doc, out_name = build_ctt(folder), "ctt_report_zh.html"
        else:
            doc, out_name = build_irt(folder)
    except Exception:
        print("[错误] HTML 报告生成失败：\n" + traceback.format_exc(), file=sys.stderr)
        raise SystemExit(1)
    out = folder / out_name
    tmp = out.with_name(out.name + ".tmp")
    try:
        with open(tmp, "w", encoding="utf-8", newline="\n") as f:  # UTF-8 无 BOM + 统一 \n
            f.write(doc)
        os.replace(tmp, out)  # 原子替换：要么完整成功，要么目标文件保持原样
    except Exception:
        if tmp.exists():
            tmp.unlink()
        print("[错误] HTML 写盘失败：\n" + traceback.format_exc(), file=sys.stderr)
        raise SystemExit(1)
    print("HTML_REPORT_OK")


if __name__ == "__main__":
    main()
