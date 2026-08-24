@echo off
echo 正在编译 Linux 版本...
set GOOS=linux
set GOARCH=amd64
go build -o aichat-api .