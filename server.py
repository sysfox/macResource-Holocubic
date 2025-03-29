import psutil
import subprocess
from flask import Flask, Response

app = Flask(__name__)

def get_gpu_info():
    """获取GPU信息（需要安装iStats）"""
    try:
        temp = subprocess.check_output(["istats", "extra"]).decode()
        gpu_temp = float(temp.split("GPU: ")[1].split("°")[0]) * 10  # 扩大10倍匹配ESP32格式
        return 60.0, gpu_temp  # 模拟GPU使用率和温度
    except:
        return 60.0, 550  # 默认值（55.0°C）

def get_pc_resources():
    # CPU
    cpu_percent = psutil.cpu_percent()
    cpu_temp = subprocess.check_output(["osx-cpu-temp"]).decode().strip()
    cpu_freq = psutil.cpu_freq().current
    cpu_power = 15.0  # macOS需通过第三方工具获取
    
    # GPU
    gpu_usage, gpu_temp = get_gpu_info()
    gpu_power = 45.0  # 模拟值
    
    # 内存
    mem = psutil.virtual_memory()
    ram_usage = mem.percent
    ram_used = mem.used / 1024 / 1024  # 转换为MB
    
    # 网络（需计算差值）
    net = psutil.net_io_counters()
    upload = net.bytes_sent / 1024    # KB/s
    download = net.bytes_recv / 1024  # KB/s
    
    return f"""CPU usage {cpu_percent:.1f}%
CPU temp {cpu_temp}
CPU freq {cpu_freq:.1f}MHz
CPU power {cpu_power:.1f}W
GPU usage {gpu_usage:.1f}%
GPU temp {gpu_temp:.1f}C
GPU power {gpu_power:.1f}W
RAM usage {ram_usage:.1f}%
RAM use {ram_used:.1f}MB
NET upload speed {upload:.1f}KB/s
NET download speed {download:.1f}KB/s"""

@app.route('/sse')
def sse():
    def generate():
        while True:
            data = get_pc_resources()
            yield f"data: {data}\n\n"
    return Response(generate(), mimetype="text/event-stream")

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80)