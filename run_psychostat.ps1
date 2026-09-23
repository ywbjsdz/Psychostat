param([ValidateSet('stats','ctt','irt')][string]$Framework)
$root=$PSScriptRoot
if(-not $Framework){Write-Host "`nPsychostat：请选择要运行的任务" -ForegroundColor Cyan;Write-Host '  1. 心理统计（平时的统计课内容：t检验/方差分析/相关回归/卡方/非参数/中介调节，含SPSS对照教学）';Write-Host '  2. CTT（经典测量理论：量表项目分析/信效度/EFA/CFA）';Write-Host '  3. IRT（项目反应理论：Rasch/2PL/GRM/MIRT）';do{$choice=Read-Host '输入 1、2 或 3'}until($choice -in '1','2','3');$Framework=if($choice -eq '1'){'stats'}elseif($choice -eq '2'){'ctt'}else{'irt'}}
if($Framework -eq 'stats'){& (Join-Path $root 'run_stats_analysis.ps1')}elseif($Framework -eq 'ctt'){& (Join-Path $root 'run_ctt_analysis.ps1')}else{& (Join-Path $root 'run_irt_analysis.ps1')}
