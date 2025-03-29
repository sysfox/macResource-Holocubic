import Foundation
import SystemConfiguration
import Darwin // 添加Darwin导入，包括socket相关API
import IOKit // 添加IOKit导入，包括系统硬件信息

// 用于存储上一次网络计数，以计算速率
struct NetworkCounters {
    var bytesReceived: UInt64 = 0
    var bytesSent: UInt64 = 0
    var timestamp: Date = Date()
}

class ResourceMonitor {
    private var lastNetworkCounters = NetworkCounters()
    
    // 获取CPU使用率
    func getCPUUsage() -> Double {
        var cpuInfo = host_cpu_load_info_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &cpuInfo) { infoPointer in
            infoPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, intPointer, &count)
            }
        }
        
        if result != KERN_SUCCESS {
            return 0.0
        }
        
        let userTicks = cpuInfo.cpu_ticks.0
        let systemTicks = cpuInfo.cpu_ticks.1
        let idleTicks = cpuInfo.cpu_ticks.2
        let niceTicks = cpuInfo.cpu_ticks.3
        
        let totalTicks = userTicks + systemTicks + idleTicks + niceTicks
        let usedTicks = userTicks + systemTicks + niceTicks
        
        return Double(usedTicks) / Double(totalTicks) * 100.0
    }
    
    // 获取CPU温度（使用外部工具osx-cpu-temp）
    func getCPUTemperature() -> String {
        let task = Process()
        task.launchPath = "/usr/bin/env"
        task.arguments = ["osx-cpu-temp"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                return output
            }
        } catch {
            print("Error getting CPU temperature: \(error)")
        }
        
        return "0°C"
    }
    
    // 获取CPU频率
    func getCPUFrequency() -> Double {
        let task = Process()
        task.launchPath = "/usr/bin/env"
        task.arguments = ["sysctl", "-n", "hw.cpufrequency"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let frequency = Double(output) {
                return frequency / 1_000_000 // 转换为MHz
            }
        } catch {
            print("Error getting CPU frequency: \(error)")
        }
        
        return 0.0
    }
    
    // 获取GPU信息（使用iStats）
    func getGPUInfo() -> (usage: Double, temperature: Double) {
        let task = Process()
        task.launchPath = "/usr/bin/env"
        task.arguments = ["istats", "extra"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                if let tempRange = output.range(of: "GPU: ") {
                    let tempSubstring = output[tempRange.upperBound...]
                    if let endRange = tempSubstring.range(of: "°") {
                        let tempString = tempSubstring[..<endRange.lowerBound]
                        if let temperature = Double(tempString) {
                            return (60.0, temperature * 10) // 模拟GPU使用率，温度扩大10倍
                        }
                    }
                }
            }
        } catch {
            print("Error getting GPU info: \(error)")
        }
        
        return (60.0, 550.0) // 默认值
    }
    
    // 获取内存使用情况
    func getMemoryUsage() -> (usagePercent: Double, usedMB: Double) {
        var stats = vm_statistics64_t.allocate(capacity: 1)
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &stats.pointee) { statsPointer in
            statsPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPointer, &count)
            }
        }
        
        if result != KERN_SUCCESS {
            stats.deallocate()
            return (0.0, 0.0)
        }
        
        let freeMemory = Double(stats.pointee.free_count) * Double(vm_page_size)
        let activeMemory = Double(stats.pointee.active_count) * Double(vm_page_size)
        let inactiveMemory = Double(stats.pointee.inactive_count) * Double(vm_page_size)
        let wiredMemory = Double(stats.pointee.wire_count) * Double(vm_page_size)
        let compressedMemory = Double(stats.pointee.compressor_page_count) * Double(vm_page_size)
        
        let usedMemory = activeMemory + inactiveMemory + wiredMemory + compressedMemory
        
        // 获取总内存
        var totalMemory: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &totalMemory, &size, nil, 0)
        
        let usagePercent = (Double(usedMemory) / Double(totalMemory)) * 100.0
        let usedMB = usedMemory / 1024.0 / 1024.0
        
        stats.deallocate()
        return (usagePercent, usedMB)
    }
    
    // 获取网络使用情况
    func getNetworkUsage() -> (upload: Double, download: Double) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0 else {
            return (0, 0)
        }
        
        var currentBytesReceived: UInt64 = 0
        var currentBytesSent: UInt64 = 0
        
        var ptr = ifaddr
        while ptr != nil {
            let addr = ptr!.pointee
            let name = String(cString: addr.ifa_name)
            
            if name.hasPrefix("en") || name.hasPrefix("lo") {
                if let data = addr.ifa_data?.assumingMemoryBound(to: if_data.self) {
                    currentBytesReceived += UInt64(data.pointee.ifi_ibytes)
                    currentBytesSent += UInt64(data.pointee.ifi_obytes)
                }
            }
            
            ptr = addr.ifa_next
        }
        
        freeifaddrs(ifaddr)
        
        let now = Date()
        let timeInterval = now.timeIntervalSince(lastNetworkCounters.timestamp)
        
        // 避免除以零
        guard timeInterval > 0 else {
            lastNetworkCounters = NetworkCounters(bytesReceived: currentBytesReceived, bytesSent: currentBytesSent, timestamp: now)
            return (0, 0)
        }
        
        let uploadSpeed = Double(currentBytesSent - lastNetworkCounters.bytesSent) / timeInterval / 1024.0 // KB/s
        let downloadSpeed = Double(currentBytesReceived - lastNetworkCounters.bytesReceived) / timeInterval / 1024.0 // KB/s
        
        lastNetworkCounters = NetworkCounters(bytesReceived: currentBytesReceived, bytesSent: currentBytesSent, timestamp: now)
        
        return (uploadSpeed, downloadSpeed)
    }
    
    // 获取完整的资源信息
    func getAllResources() -> String {
        let cpuUsage = getCPUUsage()
        let cpuTemp = getCPUTemperature()
        let cpuFreq = getCPUFrequency()
        let cpuPower = 15.0 // 模拟值
        
        let gpuInfo = getGPUInfo()
        let gpuUsage = gpuInfo.usage
        let gpuTemp = gpuInfo.temperature
        let gpuPower = 45.0 // 模拟值
        
        let memInfo = getMemoryUsage()
        let ramUsage = memInfo.usagePercent
        let ramUsed = memInfo.usedMB
        
        let netInfo = getNetworkUsage()
        let uploadSpeed = netInfo.upload
        let downloadSpeed = netInfo.download
        
        return """
        CPU usage \(String(format: "%.1f", cpuUsage))%
        CPU temp \(cpuTemp)
        CPU freq \(String(format: "%.1f", cpuFreq))MHz
        CPU power \(String(format: "%.1f", cpuPower))W
        GPU usage \(String(format: "%.1f", gpuUsage))%
        GPU temp \(String(format: "%.1f", gpuTemp))C
        GPU power \(String(format: "%.1f", gpuPower))W
        RAM usage \(String(format: "%.1f", ramUsage))%
        RAM use \(String(format: "%.1f", ramUsed))MB
        NET upload speed \(String(format: "%.1f", uploadSpeed))KB/s
        NET download speed \(String(format: "%.1f", downloadSpeed))KB/s
        """
    }
}

class HTTPServer {
    private let port: UInt16
    private var server: HTTPServer?
    private var connections: [FileHandle: Data] = [:]
    private let resourceMonitor = ResourceMonitor()
    private var keepRunning = true
    
    init(port: UInt16 = 80) {
        self.port = port
    }
    
    func start() {
        let socket = socket(AF_INET, SOCK_STREAM, 0)
        if socket == -1 {
            print("Error creating socket")
            return
        }
        
        var reuse = 1
        if setsockopt(socket, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int>.size)) == -1 {
            print("Error setting socket options")
            close(socket)
            return
        }
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY.bigEndian
        
        let addrSize = MemoryLayout<sockaddr_in>.size
        let bindResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(socket, sockPtr, socklen_t(addrSize))
            }
        }
        
        if bindResult == -1 {
            print("Error binding socket")
            close(socket)
            return
        }
        
        if listen(socket, 5) == -1 {
            print("Error listening on socket")
            close(socket)
            return
        }
        
        print("Server started on port \(port)")
        
        DispatchQueue.global(qos: .background).async {
            self.acceptConnections(socket: socket)
        }
        
        // 启动SSE事件生成
        DispatchQueue.global(qos: .background).async {
            self.generateSSEEvents()
        }
        
        // 保持主线程运行
        RunLoop.main.run()
    }
    
    private func acceptConnections(socket: Int32) {
        while keepRunning {
            var addr = sockaddr_in()
            var addrSize = socklen_t(MemoryLayout<sockaddr_in>.size)
            
            let clientSocket = withUnsafeMutablePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    accept(socket, sockPtr, &addrSize)
                }
            }
            
            if clientSocket == -1 {
                print("Error accepting connection")
                continue
            }
            
            let fileHandle = FileHandle(fileDescriptor: clientSocket, closeOnDealloc: true)
            
            DispatchQueue.global(qos: .background).async {
                self.handleConnection(fileHandle: fileHandle)
            }
        }
    }
    
    private func handleConnection(fileHandle: FileHandle) {
        do {
            if let data = try fileHandle.readToEnd() {
                if let request = String(data: data, encoding: .utf8) {
                    print("Received request: \(request)")
                    
                    if request.contains("GET /sse HTTP/1.1") {
                        // 处理SSE连接请求
                        connections[fileHandle] = Data()
                        
                        let response = """
                        HTTP/1.1 200 OK
                        Content-Type: text/event-stream
                        Cache-Control: no-cache
                        Connection: keep-alive
                        Access-Control-Allow-Origin: *
                        
                        
                        """
                        
                        if let responseData = response.data(using: .utf8) {
                            try fileHandle.write(contentsOf: responseData)
                        }
                    } else {
                        // 对于其他请求，返回404
                        let response = """
                        HTTP/1.1 404 Not Found
                        Content-Type: text/plain
                        Content-Length: 9
                        
                        Not Found
                        """
                        
                        if let responseData = response.data(using: .utf8) {
                            try fileHandle.write(contentsOf: responseData)
                            fileHandle.closeFile()
                        }
                    }
                }
            }
        } catch {
            print("Error handling connection: \(error)")
            fileHandle.closeFile()
        }
    }
    
    private func generateSSEEvents() {
        while keepRunning {
            let resourceData = resourceMonitor.getAllResources()
            let sseEvent = "data: \(resourceData)\n\n"
            
            // 向所有连接发送SSE事件
            for (fileHandle, _) in connections {
                do {
                    if let eventData = sseEvent.data(using: .utf8) {
                        try fileHandle.write(contentsOf: eventData)
                    }
                } catch {
                    print("Error sending SSE event: \(error)")
                    fileHandle.closeFile()
                    connections.removeValue(forKey: fileHandle)
                }
            }
            
            Thread.sleep(forTimeInterval: 1.0)
        }
    }
    
    func stop() {
        keepRunning = false
        for (fileHandle, _) in connections {
            fileHandle.closeFile()
        }
        connections.removeAll()
    }
}

// 启动服务器
let server = HTTPServer(port: 80)
server.start() 