# 安装 Termux
Github 官方下载地址：https://github.com/termux/termux-app/releases

# 在  Termux 中输入以下命令，等待运行完毕...
pkg update

pkg install wget -y

wget -N https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.2.5/CloudflareST_linux_arm64.tar.gz

tar -zxf CloudflareST_linux_arm64.tar.gz

chmod +x CloudflareST

./CloudflareST -n 500 -tll 20 -sl 5 -dn 2 -tl 250 -url https://cfst.bin -f hk.txt
