#!/usr/bin/env python3
from prometheus_client import start_http_server, Gauge
import amdsmi
import time

amdsmi.amdsmi_init()

g_temp = Gauge("amd_gpu_temperature_celsius", "GPU temperature", ["gpu"])
g_util = Gauge("amd_gpu_utilization_percent", "GPU utilization", ["gpu"])
g_mem_used = Gauge("amd_gpu_vram_used_bytes", "VRAM used", ["gpu"])
g_mem_total = Gauge("amd_gpu_vram_total_bytes", "VRAM total", ["gpu"])
g_power = Gauge("amd_gpu_power_watts", "Power draw", ["gpu"])

start_http_server(9835)

while True:
    handles = amdsmi.amdsmi_get_processor_handles()
    for i, h in enumerate(handles):
        temp = amdsmi.amdsmi_get_temp_metric(h, amdsmi.AMDSMI_TEMPERATURE_TYPE_EDGE)
        util = amdsmi.amdsmi_get_gpu_activity(h)
        mem = amdsmi.amdsmi_get_gpu_memory_usage(h)
        power = amdsmi.amdsmi_get_power_info(h)

        g_temp.labels(gpu=i).set(temp)
        g_util.labels(gpu=i).set(util["gfx_activity"])
        g_mem_used.labels(gpu=i).set(mem["vram_usage"])
        g_mem_total.labels(gpu=i).set(mem["vram_total"])
        g_power.labels(gpu=i).set(power["average_socket_power"])

    time.sleep(5)

