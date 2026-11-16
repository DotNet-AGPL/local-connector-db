#!/usr/bin/env bash
# 把 seed.sql 灌进 MySQL 容器。
# 之所以写成脚本文件：wsl.exe 传参时反斜杠会被吃掉，重定向语法无法直接拼在命令行里。
set -euo pipefail

name="$1"
seed_path="$2"
password="$3"

nerdctl exec -i "$name" mysql --default-character-set=utf8mb4 -uroot -p"$password" < "$seed_path"
