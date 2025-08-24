# k60screen_overclocker

⚠️ 风险自担

超频可能损坏屏幕、系统或失去保修。继续即视为接受全部风险。

---

一键超频 K60 屏幕  
理论兼容 其他机型。

在线启动（MT 管理器终端）

```bash
curl -sSfL https://raw.githubusercontent.com/ptcry/k60screen_overclocker/main/k60screen_overclocker.sh \
  -o /data/local/tmp/k60screen_overclocker.sh && \
chmod +x /data/local/tmp/k60screen_overclocker.sh && \
bash /data/local/tmp/k60screen_overclocker.sh || echo "网络错误或下载失败"
```

离线启动
1. 下载 [ZIP](https://github.com/ptcry/k60screen_overclocker/archive/refs/heads/main.zip) 并解压。
2. 将解压后的全部文件复制到 `/data/local/tmp`。
3. 终端执行：
   
```bash
   cd /data/local/tmp
   chmod +x k60screen_overclocker.sh
   ./k60screen_overclocker.sh
   ```

---

常见问题

现象	解决	
黑屏 / 花屏	时钟过高，选择 1. 刷入预制 DTBO → dtbo_origin.img 恢复原厂	

---

后续计划
- 增加 / 删除刷新率档位

有任何问题请先查看 [Issues](https://github.com/ptcry/k60screen_overclocker/issues)。