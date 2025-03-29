# macResource-Holocubic
一款用于将Holocubic电脑性能监控与mac结合的软件

## Swift版本
这是使用Swift编写的macOS系统资源监控服务器，用于与Holocubic设备通信，显示Mac电脑的性能数据。

### 功能
- 实时监控CPU使用率、温度、频率和功耗
- 获取GPU温度和模拟使用率（需要安装iStats工具）
- 监控内存使用情况
- 监控网络上传下载速度
- 通过Server-Sent Events (SSE)提供数据流

### 安装前提
1. 安装[osx-cpu-temp](https://github.com/lavoiesl/osx-cpu-temp)工具：用于获取CPU温度
   ```
   brew install osx-cpu-temp
   ```

2. 安装[iStats](https://github.com/Chris911/iStats)工具：用于获取GPU温度
   ```
   gem install iStats
   ```

### 编译与运行
```bash
# 克隆仓库
git clone https://github.com/yourusername/macResource-Holocubic.git
cd macResource-Holocubic

# 编译项目
swift build -c release

# 运行服务器（需要管理员权限绑定80端口）
sudo .build/release/MacResourceMonitor
```

或者直接使用Swift运行:
```bash
sudo swift run
```

### 使用方法
服务器启动后，Holocubic设备可以连接到服务器的SSE端点获取资源数据：
```
http://[mac电脑IP地址]/sse
```

### 系统要求
- macOS 11.0 或更高版本
- Swift 5.5 或更高版本
