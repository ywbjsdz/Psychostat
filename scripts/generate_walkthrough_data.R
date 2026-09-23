# 生成「手动走查」用的模拟数据：把 CTT 与 IRT 的每一个功能各配一份可直接加载的数据文件。
#
# 与 examples/simulated_datasets/ 的区别：那一套是**校对用**的（配真值文件与固定配置，走 --config）；
# 这一套是**手跑用**的（在图形界面里"选择我的数据文件"直接加载），每个文件只针对一组功能，
# 并在数据里带上该功能需要的辅助列（注意检验、作答用时、校标、已知组、维度对照表）。
#
# 用法（Windows）：
#   Rscript --vanilla scripts/generate_walkthrough_data.R
# 输出：桌面上的「Psychostat 模拟数据」文件夹（数据 + 对照表）。
# 本脚本只写文件，不改动工具的任何代码与既有数据。

set.seed(20260918)
OUT <- file.path(Sys.getenv("USERPROFILE"), "Desktop", "Psychostat 模拟数据")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

## ── 工具函数 ────────────────────────────────────────────────────────────────
w <- function(df, name) {                      # 统一写 LF 换行，避免 Windows 的 CRLF
  # 列名重复是静默杀手：write.csv 会照写重复表头，工具读进来只会认到第一组同名题，
  # 报错却指向"某题找不到"（曾因此让 CTT-04 的 18 题只认到 6 题）。这里直接拦住。
  dup <- unique(names(df)[duplicated(names(df))])
  if (length(dup)) stop(sprintf("列名重复（%s）：%s", name, paste(dup, collapse = ", ")))
  p <- file.path(OUT, name)
  con <- file(p, open = "wb")
  utils::write.csv(df, con, row.names = FALSE, fileEncoding = "UTF-8")
  close(con)
  raw <- readBin(p, "raw", file.size(p))
  raw <- raw[!(raw == as.raw(13))]
  writeBin(raw, p)
  cat(sprintf("  %-44s n=%4d  列=%2d\n", name, nrow(df), ncol(df)))
}
sig <- function(z) 1 / (1 + exp(-z))
items <- function(k) sprintf("Item%02d", seq_len(k))

# Anderson–Rubin 式离散化：给定载荷 λ 生成 1..cats 的作答（CTT 用）
sim_ctt <- function(n, load, cats = 5L, cross = NULL) {
  k <- length(load); th <- rnorm(n)
  z <- sapply(seq_len(k), function(j) load[j] * th + sqrt(1 - load[j]^2) * rnorm(n))
  if (!is.null(cross)) z <- z + cross                      # 交叉载荷
  cuts <- seq(-2.0, 2.0, length.out = cats - 1L)
  out <- sapply(seq_len(k), function(j) as.integer(cut(z[, j], c(-Inf, cuts, Inf))) )
  as.data.frame(matrix(pmax(1L, pmin(cats, out)), n, k, dimnames = list(NULL, items(k))))
}

# 同上去掉"自带 θ"，改为按给定潜变量 lat（方差为 1）生成
sim_ctt_lat <- function(n, load, lat, cats = 5L) {
  k <- length(load)
  z <- sapply(seq_len(k), function(j) load[j] * lat + sqrt(1 - load[j]^2) * rnorm(n))
  cuts <- seq(-2.0, 2.0, length.out = cats - 1L)
  out <- sapply(seq_len(k), function(j) as.integer(cut(z[, j], c(-Inf, cuts, Inf))))
  as.data.frame(matrix(pmax(1L, pmin(cats, out)), n, k, dimnames = list(NULL, items(k))))
}

# 二分反应（IRT 用；c 为猜测参数）
sim_bin <- function(n, a, b, c = rep(0, length(a)), theta = NULL) {
  k <- length(a); if (is.null(theta)) theta <- rnorm(n)
  m <- sapply(seq_len(k), function(j) c[j] + (1 - c[j]) * sig(a[j] * (theta - b[j])))
  as.data.frame(matrix(rbinom(n * k, 1L, as.vector(m)), n, k, dimnames = list(NULL, items(k))))
}

# Samejima 等级反应模型：给定 a 与各阈值 b（长度 cats-1），生成 1..cats
sim_grm <- function(n, a, B, theta = NULL) {
  k <- length(a); if (is.null(theta)) theta <- rnorm(n)
  out <- matrix(1L, n, k)
  for (j in seq_len(k)) {
    S <- sapply(B[[j]], function(bb) sig(a[j] * (theta - bb)))    # P(X>=2..cats)
    P <- cbind(1, S) - cbind(S, 0)                                 # 各类别概率
    out[, j] <- apply(P, 1, function(p) sample.int(length(p), 1L, prob = pmax(p, 1e-12)))
  }
  as.data.frame(matrix(out, n, k, dimnames = list(NULL, items(k))))
}

# Muraki 部分 credit 模型：给定 a 与台阶难度 b（相邻截距差），生成 1..cats
sim_gpcm <- function(n, a, B, theta = NULL) {
  k <- length(a); if (is.null(theta)) theta <- rnorm(n)
  out <- matrix(1L, n, k)
  for (j in seq_len(k)) {
    d <- cumsum(c(0, -a[j] * B[[j]]))                     # 累积截距（第 1 类为 0）
    eta <- sapply(0:(length(d) - 1L), function(kk) kk * a[j] * theta + d[kk + 1L])
    pr <- exp(eta - apply(eta, 1, max)); pr <- pr / rowSums(pr)
    out[, j] <- apply(pr, 1, function(p) sample.int(length(p), 1L, prob = pmax(p, 1e-12)))
  }
  as.data.frame(matrix(out, n, k, dimnames = list(NULL, items(k))))
}
pid <- function(n) sprintf("P%03d", seq_len(n))

cat("CTT 分支：\n")

## 1) 单维 + EFA：最基本的一条路（α、CITC、CR、KMO、Bartlett、碎石图、载荷表）
d1 <- sim_ctt(500, runif(15, .55, .80))
d1 <- cbind(participant_id = pid(500), d1); w(d1, "CTT-01_单维EFA_n500_15题.csv")

## 2) 数据清洗全要素：反向题 2 道 + 注意检验 + 作答用时 + 直线作答 + 极端作答 + 缺失
n2 <- 600; d2 <- sim_ctt(n2, c(rep(.65, 18), .6, .6))
d2$Item03 <- 6L - d2$Item03; d2$Item11 <- 6L - d2$Item11        # 两题反向计分
straight <- sample.int(n2, round(n2 * .05)); for (i in straight) d2[i, 1:20] <- sample(1:5, 1)
extreme <- sample(setdiff(seq_len(n2), straight), round(n2 * .03))
for (i in extreme) d2[i, 1:20] <- sample(c(1L, 5L), 20, TRUE)
att <- rep(3L, n2); att[sample.int(n2, round(n2 * .08))] <- sample(c(1L, 2L, 4L, 5L), round(n2 * .08), TRUE)
rt <- round(pmax(8, rnorm(n2, 320, 120))); rt[sample.int(n2, round(n2 * .10))] <- round(runif(round(n2 * .10), 8, 44))
# 缺失分两类，好让两条清洗规则都能被触发：
#   ① 4 道题各缺 3%（题目缺失率 < 5% → 走中位数插补）
#   ② 5% 的个案有 30% 单元格缺失（个案缺失率 > 20% → 走整行删除）
dm <- as.matrix(d2)
for (j in c(4L, 9L, 14L, 18L)) dm[sample.int(n2, round(n2 * .03)), j] <- NA
heavy <- sample.int(n2, round(n2 * .05))
for (i in heavy) dm[i, sample.int(20, 6)] <- NA
d2 <- data.frame(participant_id = pid(n2), dm, attention_check = att, response_time_sec = rt)
w(d2, "CTT-02_清洗全要素_n600_20题.csv")

## 3) 反向题 + 效标 + 已知组：校标关联效度、已知组差异、两个分量表
n3 <- 400
# 两个分量表共享一个一般因子（权重各 1/√2），于是：分量表 α 高、总量表 α 中等偏上——
# 这正是真实多维量表的形态；若让两个分量表完全独立，总量表 α 会低到 0.58，容易被误读成"数据坏了"
g <- rnorm(n3); lat1 <- (g + rnorm(n3)) / sqrt(2); lat2 <- (g + rnorm(n3)) / sqrt(2)
sub1 <- sim_ctt_lat(n3, runif(8, .60, .80), lat1); sub2 <- sim_ctt_lat(n3, runif(8, .60, .80), lat2)
d3 <- cbind(sub1, sub2); names(d3) <- items(16L)
d3$Item05 <- 6L - d3$Item05; d3$Item13 <- 6L - d3$Item13
tot <- rowSums(d3)
d3 <- data.frame(participant_id = pid(n3), d3,
                 criterion = round(as.numeric(scale(tot)) * .55 + rnorm(n3, sd = .84), 2),
                 known_group = as.integer(cut(tot, c(-Inf, median(tot), Inf))) - 1L)
w(d3, "CTT-03_反向题_校标_已知组_n400_16题.csv")

## 4) 三因子 + CFA 对照表：走 CFA 路线（含路径图、修正指数）
n4 <- 500
d4 <- cbind(sim_ctt(n4, runif(6, .60, .78), cross = matrix(rnorm(n4 * 6, 0, .18), n4, 6)),
            sim_ctt(n4, runif(6, .60, .78), cross = matrix(rnorm(n4 * 6, 0, .18), n4, 6)),
            sim_ctt(n4, runif(6, .60, .78), cross = matrix(rnorm(n4 * 6, 0, .18), n4, 6)))
d4 <- cbind(participant_id = pid(n4), d4)
names(d4)[-1] <- items(18L)          # 三个因子块原本各自叫 Item01..Item06，必须整体重命名
w(d4, "CTT-04_三因子CFA_n500_18题.csv")
w(data.frame(item = items(18L), dimension = rep(c("F1", "F2", "F3"), each = 6)),
  "CTT-04_CFA维度对照表.csv")

## 5) 质量差的量表：低 α、低 CITC、负向题、交叉载荷 → 看"建议删题"标记与各类警示
n5 <- 300
d5 <- cbind(sim_ctt(n5, c(runif(6, .60, .80), runif(3, .12, .25), .20, .18, .15)))
d5$Item10 <- 6L - d5$Item10
d5 <- cbind(participant_id = pid(n5), d5); w(d5, "CTT-05_质量差_建议删题_n300_12题.csv")

## 6) 边界：含一道零方差题（所有人都选 3）→ 看工具是否显式排除并提示
n6 <- 120; d6 <- cbind(participant_id = pid(n6), sim_ctt(n6, runif(9, .55, .75)), Item10 = 3L)
w(d6, "CTT-06_边界_含零方差题_n120_10题.csv")

## 7) 边界：0–4 编码却按 1–5 设置 → 反向计分会被安全拦截（这是设计好的保护，不是 bug）
n7 <- 150; d7 <- sim_ctt(n7, runif(10, .55, .75)) - 1L; d7 <- cbind(participant_id = pid(n7), d7)
w(d7, "CTT-07_边界_0到4编码_n150_10题.csv")

cat("\nIRT 分支：\n")

## 1) Rasch（1PL）：所有题区分度固定为 1
d <- cbind(participant_id = pid(500), sim_bin(500, rep(1, 20), seq(-1.6, 1.6, length.out = 20)))
w(d, "IRT-01_二分Rasch_n500_20题.csv")

## 2) 2PL：区分度与难度都自由估计
d <- cbind(participant_id = pid(800), sim_bin(800, round(exp(rnorm(20, 0, .25)), 3), rnorm(20)))
w(d, "IRT-02_二分2PL_n800_20题.csv")

## 3) 3PL：含猜测参数（注意：c 是弱识别参数，逐题排序不可解读）
d <- cbind(participant_id = pid(1500),
           sim_bin(1500, round(runif(20, .8, 1.8), 3), rnorm(20), c = round(runif(20, .08, .25), 3)))
w(d, "IRT-03_二分3PL_n1500_20题.csv")

## 4) GRM：多级有序（5 类），阈值递增
B <- lapply(seq_len(15), function(j) sort(rnorm(4, 0, .8)))
d <- cbind(participant_id = pid(600), sim_grm(600, round(runif(15, .9, 1.8), 3), B))
w(d, "IRT-04_多级GRM_n600_15题.csv")

## 5) GPCM：多级有序，台阶难度递增（工具输出的 b 即台阶口径）
B <- lapply(seq_len(15), function(j) sort(runif(4, -1.6, 1.6)))
d <- cbind(participant_id = pid(600), sim_gpcm(600, round(runif(15, .8, 1.6), 3), B))
w(d, "IRT-05_多级GPCM_n600_15题.csv")

## 6) 多维二分（2 维，探索性 EIFA）：不用对照表，让工具自己找维度
th2 <- cbind(rnorm(800), .4 * rnorm(800) + sqrt(1 - .16) * rnorm(800))
d <- cbind(participant_id = pid(800),
           sim_bin(800, round(runif(10, .8, 1.6), 3), rnorm(10), theta = th2[, 1]),
           sim_bin(800, round(runif(10, .8, 1.6), 3), rnorm(10), theta = th2[, 2]))
names(d)[-1] <- items(20L)
w(d, "IRT-06_多维二分EIFA_n800_20题.csv")

## 7) 多维多级（3 维，验证性 CIFA）：**必须**同时选配套的维度对照表
th3 <- cbind(rnorm(900), .45 * rnorm(900) + sqrt(1 - .2) * rnorm(900),
             .45 * rnorm(900) + sqrt(1 - .2) * rnorm(900))
Bm <- lapply(seq_len(24), function(j) sort(rnorm(4, 0, .8)))
d3m <- cbind(sim_grm(900, round(runif(8, .9, 1.6), 3), Bm[1:8],  theta = th3[, 1]),
             sim_grm(900, round(runif(8, .9, 1.6), 3), Bm[9:16], theta = th3[, 2]),
             sim_grm(900, round(runif(8, .9, 1.6), 3), Bm[17:24], theta = th3[, 3]))
d3m <- cbind(participant_id = pid(900), d3m); names(d3m)[-1] <- items(24L)
w(d3m, "IRT-07_多维多级CIFA_n900_24题.csv")
w(data.frame(item = items(24L), dimension = rep(c("F1", "F2", "F3"), each = 8)),
  "IRT-07_维度对照表.csv")

## 8) 缺失数据：比较 none / pairwise / listwise 三种策略
n8 <- 800; d8 <- cbind(participant_id = pid(n8), sim_bin(n8, round(runif(20, .8, 1.8), 3), rnorm(20)))
m8 <- as.matrix(d8[, -1]); m8[sample(length(m8), round(length(m8) * .08))] <- NA
d8 <- data.frame(participant_id = d8$participant_id, m8); w(d8, "IRT-08_缺失数据_n800_20题.csv")

## 9) 小样本边界：n=40 → 触发"样本量仅 40，参数估计极不稳定"的警告
d <- cbind(participant_id = pid(40), sim_bin(40, round(runif(10, .8, 1.6), 3), rnorm(10)))
w(d, "IRT-09_小样本边界_n40_10题.csv")

note <- c(
  "Psychostat 模拟数据（手动走查用）",
  "",
  "用法：双击 启动Psychostat界面.bat → 选择分支 → 在「选择数据文件」里选本文件夹中的 CSV。",
  "带 * 的文件还需在同一向导里选择配套的对照表文件。",
  "",
  "── CTT 分支 ──────────────────────────────────────────────",
  "CTT-01_单维EFA_n500_15题.csv        最基础的一条路：清洗→项目分析→α→EFA（碎石图/载荷表）。实测 α≈0.91",
  "                                     量表最高分填 5，无需勾反向题。",
  "CTT-02_清洗全要素_n600_20题.csv      清洗功能全套（实测 600 人 → 保留 468）。需要在向导里设置：",
  "                                     最高分 5；反向题 = Item03、Item11；",
  "                                     注意检验列 = attention_check，正确值 = 3；",
  "                                     作答用时列 = response_time_sec，最少 = 45 秒；",
  "                                     直线作答 = 标记；极端值 = 标记；缺失中间区间按默认。",
  "CTT-03_反向题_校标_已知组_n400_16题.csv  反向题 = Item05、Item13（不勾反向题 α 会明显偏低）；校标列 = criterion（正向）；",
  "                                     已知组列 = known_group（0/1）；可看效标关联效度与已知组差异。",
  "CTT-04_三因子CFA_n500_18题.csv  *    先跑 EFA 看三因子结构，再走 CFA 路线；",
  "                                     配套对照表 = CTT-04_CFA维度对照表.csv（F1/F2/F3 各 6 题）。",
  "CTT-05_质量差_建议删题_n300_12题.csv  故意做差（实测 α≈0.63）：低载荷、负向题、交叉载荷 → 看「建议删除题目」标记。",
  "CTT-06_边界_含零方差题_n120_10题.csv  Item10 所有人都是 3 → 工具应显式提示并排除该列（不是静默丢掉）。",
  "CTT-07_边界_0到4编码_n150_10题.csv    0–4 编码。若把最高分设成 5 又勾反向题，工具会拒绝并说明原因",
  "                                     （这是设计好的保护）；改最高分为 4 即可正常跑。",
  "",
  "── IRT 分支 ──────────────────────────────────────────────",
  "IRT-01_二分Rasch_n500_20题.csv       选 Rasch（1PL）；真值：所有题区分度都是 1。",
  "IRT-02_二分2PL_n800_20题.csv         选 2PL，或交给自动选模。",
  "IRT-03_二分3PL_n1500_20题.csv        选 3PL。注意：猜测参数 c 是弱识别参数，逐题排序不可解读。",
  "IRT-04_多级GRM_n600_15题.csv         多级 1–5，选 GRM。",
  "IRT-05_多级GPCM_n600_15题.csv        多级 1–5，选 GPCM（输出里的 b 是台阶难度）。",
  "IRT-06_多维二分EIFA_n800_20题.csv     多维 + 探索（EIFA）：让工具自己找维度，2 维最合适。",
  "IRT-07_多维多级CIFA_n900_24题.csv  *  多维 + 验证（CIFA）：**必须**同时选对照表",
  "                                     IRT-07_维度对照表.csv（F1/F2/F3 各 8 题），3 维。",
  "IRT-08_缺失数据_n800_20题.csv         缺失策略对比：分别用 无/pairwise/listwise 跑一次。实测：无与 pairwise 都是
                                     800 人；listwise 只剩 151 人（删掉 649）——正是手册里「分散缺失下 listwise
                                     删除比例极高」那条警告的实例。",
  "IRT-09_小样本边界_n40_10题.csv        n=40 → 体检应给出「样本量仅 40，参数估计极不稳定」的警告。",
  "",
  "说明：所有数据都是模拟的（随机种子 20260918），只用于练手；",
  "     题目编码一律为连续整数（1–5 或二分 0/1），IRT 的题目列所有文件都从 Item01 开始。"
)
con <- file(file.path(OUT, "对照表_每个文件该勾什么选项.txt"), open = "wb")
writeLines(enc2utf8(note), con, useBytes = TRUE); close(con)
cat(sprintf("\n输出目录：%s\n共 %d 个文件（含 _对照表）\n", OUT, length(list.files(OUT))))
