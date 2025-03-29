import Foundation

print("macResource-Holocubic Swift版本")
print("启动系统资源监控服务器...")

// 获取当前用户是否有管理员权限
func isRunningAsRoot() -> Bool {
    return getuid() == 0
}

// 检查必要的工具是否已安装
func checkRequiredTools() -> Bool {
    let tools = ["osx-cpu-temp", "istats"]
    var allInstalled = true
    
    for tool in tools {
        let task = Process()
        task.launchPath = "/usr/bin/which"
        task.arguments = [tool]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus != 0 {
                print("警告: \(tool) 未安装。部分功能可能无法正常工作。")
                allInstalled = false
            }
        } catch {
            print("警告: 无法检查 \(tool) 是否已安装。")
            allInstalled = false
        }
    }
    
    return allInstalled
}

// 显示本机IP地址
func printIPAddresses() {
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    
    guard getifaddrs(&ifaddr) == 0 else {
        print("无法获取网络接口信息")
        return
    }
    
    defer { freeifaddrs(ifaddr) }
    
    print("可用IP地址:")
    var ptr = ifaddr
    while ptr != nil {
        let interface = ptr!.pointee
        let family = interface.ifa_addr.pointee.sa_family
        
        if family == UInt8(AF_INET) || family == UInt8(AF_INET6) {
            let name = String(cString: interface.ifa_name)
            if name.hasPrefix("en") || name.hasPrefix("wl") {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                            &hostname, socklen_t(hostname.count),
                            nil, 0, NI_NUMERICHOST)
                let address = String(cString: hostname)
                print("  - \(name): \(address)")
            }
        }
        
        ptr = interface.ifa_next
    }
}

// 主程序
if !isRunningAsRoot() {
    print("警告: 该程序需要管理员权限来绑定80端口。")
    print("请使用 'sudo swift run' 或 'sudo .build/release/MacResourceMonitor' 运行。")
}

let toolsInstalled = checkRequiredTools()
if !toolsInstalled {
    print("请按照README.md中的说明安装必要的工具。")
}

printIPAddresses()
print("Holocubic设备可以通过 http://[mac电脑IP地址]/sse 访问资源监控")
print("服务器启动中...")

let server = HTTPServer(port: 80)
server.start() 