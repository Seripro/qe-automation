# k点パスを手動で決める場合のQE計算実行手順

1. ~/DownloadsにPWscf.zipを配置
2. qe1.sh, qe2.shのDIR_NAMEを計算したい物質名に変更
3. nohup bash qe1.sh > run1.log 2>&1 &
4. PWscfディレクトリで/home/app/xcrysden-1.5.60-bin-semishared/xcrysden --pwi pwscf.inを実行
5. nohup bash qe2.sh > run2.log 2>&1 &

# k点パスをseekpathで自動で決める場合のQE計算実行手順

1. ~/DownloadsにPWscf.zipを配置
2. qe_auto_kp.shのDIR_NAMEを計算したい物質名に変更
3. bash run.shを実行

# コマンド一覧

qstat
qdel
jobs
kill %1
