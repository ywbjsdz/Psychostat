# 二维二分类 MIRT-2PL CIFA：预期核对结果

- 数据：400 名被试、12 个二分题；F1 与 F2 各 6 题。
- 生成方式：mirt::simdata()；随机种子 20260815。
- 运行命令：

```powershell
.\run_irt_analysis.ps1 -Data ".\examples\simulated_mirt_2pl_binary.csv" -m mirt -cifa -loading_matrix ".\examples\simulated_mirt_2pl_binary_loading_matrix.csv"
```

固定随机种子、相同 mirt 版本下，CIFA 模型应优于单维 2PL 基线。2026-08-15 的已验证结果：

| 指标 | 2D CIFA-2PL | 单维 2PL |
|---|---:|---:|
| BIC | 5656.681 | 5808.759 |
| CFI | 1.000 | 0.746 |
| RMSEA | 0.000 | 0.095 |
| SRMSR | 0.033 | 0.095 |

预期差异：ΔCFI = 0.254，ΔRMSEA = -0.095，ΔBIC = -152.078。不同 R/mirt 小版本的末位小数可能略有差异。成功运行时，输出目录会包含中英文 Word 报告、模型比较、CIFA 载荷与显著性、θ/SE、ICC/IIF/TIF（300 dpi）。