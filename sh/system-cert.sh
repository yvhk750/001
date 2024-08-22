# 解决面具白名单挂证书总是不能用
set -e # Fail on error
# 创建一个单独的临时目录，用于保存当前证书
mkdir -m 700 /data/local/tmp/ca-copy
# 复制现有的证书
cp /system/etc/security/cacerts/* /data/local/tmp/ca-copy/
# 创建内存挂载
mount -t tmpfs tmpfs /system/etc/security/cacerts
# 将现有证书复制回 tmpfs 挂载，以便我们继续信任它们
mv /data/local/tmp/ca-copy/* /system/etc/security/cacerts/
# 复制我们的新证书，这样我们也相信它。243f0bfb.0 改为自己证书。可先安装用户证书 /data/misc/user/0/ 复制过来。
cp /data/local/tmp/243f0bfb.0 /system/etc/security/cacerts/
# 使所有内容都像以前一样可读
chown root:root /system/etc/security/cacerts/*
chmod 644 /system/etc/security/cacerts/*
chcon u:object_r:system_file:s0 /system/etc/security/cacerts/*
# 删除临时证书目录
rm -r /data/local/tmp/ca-copy

echo "证书已搞定，可以愉快的抓包啦。。"
