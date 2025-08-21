#k60screen_overclocker  
⚠️ 免责声明  
本项目仅供学习交流使用，超频操作可能导致屏幕损坏、系统不稳定或失去保修，所有风险由使用者自行承担。作者对因使用本工具造成的任何直接或间接损失概不负责。继续操作即视为已充分理解并接受上述风险。

---

这是一键超频 K60 屏幕的脚本。

使用方法  
1. 点击仓库右上角 Code → Download ZIP，下载并解压。
2. 将解压后的所有文件完整复制到手机目录：

   `/data/local/tmp`

3. 手机必须已 Root。在终端中执行：  
   
```bash
   cd /data/local/tmp
   chmod +x k60screen_overclocker.sh
   ./k60screen_overclocker.sh
   ```

4. 操作完重启手机，检查刷新率是否已生效。


常见问题
- 黑屏/花屏？ 时钟频率不对，若仍异常请刷回原厂固件。  
- 想恢复默认？ 选择   ```1.刷入预制DTBO选项   ```，选择   ```dtbo_origin.img   ```输入就行
- 既要又要？ 爪巴

5. Future

- 估计会加一个刷新率档位增加

如有疑问，请先阅读 [Issues](https://github.com/ptcry/k60screen_overclocker/issues) 再提问。