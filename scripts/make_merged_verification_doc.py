"""把三份验证材料合并为一份《Psychostat 输出验证文档.docx》。

三份来源（均在项目根目录）：
    SPSS与Psychostat心理统计模块输出对应.docx   心理统计分支：与 SPSS 的输出对应
    CTT与IRT校对记录.docx                      CTT / IRT 分支：输出校对记录
    GLM核对结果.txt                            第三方独立复核（GLM-5.3 原始报告）

做法：前言与附录由本脚本渲染成临时 docx；三份来源文档作为整体**原文并入**
（用 docxcompose，图片、表格、样式完整保留）；各部分之间插入分页符。
合并完成后删除临时文件，只留下最终的 `Psychostat 输出验证文档.docx`。

依赖：python-docx、docxcompose（`py -3 -m pip install docxcompose`）。
用法（Windows）：py -3 scripts/make_merged_verification_doc.py
"""
from __future__ import annotations
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

from docx import Document                                        # noqa: E402
from docx.shared import Pt                                       # noqa: E402
from docx.oxml.ns import qn                                      # noqa: E402
from docxcompose.composer import Composer                        # noqa: E402
from merge_manuals import add_md, style_doc, save_docx            # noqa: E402

OUT_NAME = "Psychostat 输出验证文档.docx"
SOURCES = [
    ("SPSS与Psychostat心理统计模块输出对应.docx", "第一部分　心理统计分支：与 SPSS 的输出对应"),
    ("CTT与IRT校对记录.docx", "第二部分　CTT 与 IRT 分支：输出校对记录"),
]
GLM = "GLM核对结果.txt"

HEAD_MD = """
# Psychostat 输出验证文档

**心理统计 · CTT · IRT 三分支的输出正确性验证**　｜　版本 v0.1.0（2026-09-18，尚未对外发布）

## 一、这份文档是什么

本文件把三份来源不同的验证材料合成一份，供审阅者一次读完。三部分均为**原文并入**，
各自的排版、编号与表格保持原样，因此风格不统一属正常。

| 部分 | 内容 | 原始来源 |
|---|---|---|
| 第一部分 | 心理统计分支：与 SPSS 的输出对应 | `SPSS与Psychostat心理统计模块输出对应.docx` |
| 第二部分 | CTT 与 IRT 分支：输出校对记录 | `CTT与IRT校对记录.docx` |
| 第三部分 | 第三方独立复核（GLM-5.3 的原始报告） | `GLM核对结果.txt` |

## 二、总体结论

- **心理统计分支**：与 SPSS 的输出逐项对照，结论为一致（见第一部分）。
- **CTT / IRT 分支**：按三层判据复核——**闭式复算**（用教科书公式从原始数据或参数表重算每个输出量）、
  **已知真值恢复**（与模拟数据的生成参数比对）、**独立实现对照**（换 `ltm` / `TAM` 等第二实现重跑），
  并由两个外部模型（GLM-5.3、GPT-5.6 Terra）以**实跑**方式独立复核三轮。
  **未发现任何已证实的数值错误**（见第二部分与第三部分）。
- **尚未独立验证的区域共三条**，原因均已查明并写入用户说明书
  （`Psychostat完整使用说明书.docx` §11.1 第 10 条）：
  ① 三维及以上多维 GPCM（可用的第二引擎 TAM 在 3 维 × 24 题规模下不收敛）；
  ② 有序题 CFA（lavaan 的 WLSMV 在本机无等价第二实现，`OpenMx::mxFitFunctionWLS` 只提供 WLS/DWLS/ULS）；
  ③ `M2*` 及其 df、`TLI`、`CFI`（TAM 不输出这些量，仅 SRMSR 可作数值对照，差 5.0e-05）。
- 全部已发现的问题都落在**校对脚本与材料清单**层面（第一轮 5 处、第二轮 1 处），
  **核心分析代码没有因此改动一行**。

## 三、怎么复现

```powershell
# 1) 生成结果目录（每个配置新建一个带时间戳的 outputs/ 子目录）
Rscript --vanilla scripts/ctt_pipeline.R --config examples/simulated_datasets/ctt_A_config.yaml
Rscript --vanilla scripts/irt_generic_pipeline.R --config examples/simulated_datasets/irt_A_config.yaml

# 2) 跑 CTT/IRT 校对脚本（--vanilla + 位置参数；本机 Rscript -f 会崩）
Rscript --vanilla tests/verify_l1_irt.R <IRT结果目录>
Rscript --vanilla tests/verify_l1_ctt.R <CTT结果目录>

# 3) 回归套件
powershell -ExecutionPolicy Bypass -File tests\\smoke_test.ps1 -Full
powershell -ExecutionPolicy Bypass -File tests\\run_numeric_tests.ps1
```

> R 与依赖包：本包为**免安装版**，随包附 `Psychostat-R` 文件夹（内含 R 与全部所需 R 包，
> 已装入其自带 `library`）。解压位置见包内 `先读我（必读）.txt` 与 `免安装版-测试方法.md`。
"""

TAIL_MD = """
# 附录 A　其余复核材料（均在本包内）

| 材料 | 位置 |
|---|---|
| 第三方复核提示词（第一轮，通用版） | `docs/第三方AI复核提示词_CTT与IRT.md` |
| 第三方复核提示词（第二轮，换靶子 G1–G5） | `docs/第三方AI复核提示词_第二轮_CTT与IRT.md` |
| 第三方复核提示词（第三轮，补作业 G1–G3）＋我方对第二轮的复核结论 | `docs/第三方AI复核提示词_第三轮_CTT与IRT.md` |
| 第二轮审查报告（GPT-5.6 Terra） | `docs/第三轮_CTT与IRT审查报告.md` |
| 第三轮补充审查报告（GPT-5.6 Terra） | `docs/第三轮_G1-G3补充审查报告.md` |
| 复核复算脚本与文本证据（两轮） | `tests/thirdparty/round2/`、`tests/thirdparty/round3/` |
| 校对方法与判据清单 | `docs/CTT与IRT校对方案.md` |
| 输出校对记录（本文件第二部分的可编辑源） | `docs/CTT与IRT校对记录.md` |

> 注：为控制包体积，复核方生成的 `.rds` 拟合对象（约 13 MB）未随包分发；
> 需要时用 `tests/thirdparty/round3/review_round3.R` 重新生成。

# 附录 B　本合并文档的生成方式

- 合并方式：前言与本附录由 `scripts/make_merged_verification_doc.py` 渲染；
  三个来源文档作为整体**原文插入**（`docxcompose`），图片、表格与样式完整保留，各部分之间分页。
- 生成日期：2026-09-18。
- 三份来源文档各自的结论与措辞**未作改动**；如有冲突，以来源文档为准。
"""


def main() -> int:
    head = ROOT / "_merge_head.docx"
    tail = ROOT / "_merge_tail.docx"
    out = ROOT / OUT_NAME

    for name, _ in SOURCES:
        if not (ROOT / name).exists():
            print(f"缺少来源文件：{name}")
            return 1
    if not (ROOT / GLM).exists():
        print(f"缺少来源文件：{GLM}")
        return 1

    doc = Document(); style_doc(doc); add_md(doc, HEAD_MD, base_level=1)
    save_docx(doc, head)

    doc = Document(); style_doc(doc)
    add_md(doc, TAIL_MD, base_level=1)
    save_docx(doc, tail)
    # 第三部分放在附录之前：GLM 报告原文，等宽排版保留原始缩进
    glm_lines = (ROOT / GLM).read_text(encoding="utf-8-sig").replace("\r\n", "\n").split("\n")
    body = Document(); style_doc(body)
    body.add_heading("第三部分　第三方独立复核（GLM-5.3 原始报告）", level=1)
    body.add_paragraph("以下为第一轮第三方复核报告原文（ZCode／内置 GLM-5.3，A 实跑模式，约 50 分钟），未作改动。")
    for line in glm_lines:
        p = body.add_paragraph(); r = p.add_run(line)
        r.font.name = "Consolas"
        r._element.rPr.rFonts.set(qn("w:eastAsia"), "Microsoft YaHei")
        r.font.size = Pt(8.5)
    glm_doc = ROOT / "_merge_glm.docx"; save_docx(body, glm_doc)

    master = Document(str(head))
    composer = Composer(master)
    for name, label in SOURCES:
        master.add_page_break()
        composer.append(Document(str(ROOT / name)))
        print(f"已并入：{label}")
    master.add_page_break()
    composer.append(Document(str(glm_doc)))
    print("已并入：第三部分　第三方独立复核（GLM-5.3 原始报告）")
    master.add_page_break()
    composer.append(Document(str(tail)))
    print("已并入：附录 A / B")

    composer.save(str(out))
    for tmp in (head, glm_doc, tail):
        tmp.unlink(missing_ok=True)

    chk = Document(str(out))
    print(f"完成：{out.name}（{out.stat().st_size} 字节，段落 {len(chk.paragraphs)}，表格 {len(chk.tables)}）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
