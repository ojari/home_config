local wibox = require("wibox")
local gears = require("gears")
local beautiful = require("beautiful")

local system_monitor = {}

local COLOR_GREEN = "#277927"
local COLOR_RED = "#d63a3a"
local COLOR_ORANGE = "#FFAA00"

-- Factory function to create progressbar widgets
local function create_progressbar(color, warning_threshold, critical_threshold)
    warning_threshold = warning_threshold or 60
    critical_threshold = critical_threshold or 80
    
    local bar = wibox.widget {
        max_value = 100,
        value = 0,
        forced_width = 80,
        forced_height = 20,
        paddings = 1,
        border_width = 1,
        border_color = beautiful.border_normal,
        background_color = "#00000088",
        color = color,
        widget = wibox.widget.progressbar,
    }
    
    -- Store thresholds for later use
    bar.warning_threshold = warning_threshold
    bar.critical_threshold = critical_threshold
    
    return bar
end

-- Helper function to update progressbar with value and color
local function update_progressbar(bar, value)
    bar.value = value
    if value > bar.critical_threshold then
        bar.color = COLOR_RED
    elseif value > bar.warning_threshold then
        bar.color = COLOR_ORANGE
    else
        bar.color = COLOR_GREEN
    end
end

local function update_progressbar_rev(bar, value)
    bar.value = value
    if value < bar.critical_threshold then
        bar.color = COLOR_RED
    elseif value < bar.warning_threshold then
        bar.color = COLOR_ORANGE
    else
        bar.color = COLOR_GREEN
    end
end

-- Factory function to create monitor widgets
local function create_monitor_widget(label, progressbar)
    local text_widget = wibox.widget {
        text = label,
        widget = wibox.widget.textbox,
    }
    
    return wibox.widget {
        text_widget,
        progressbar,
        layout = wibox.layout.fixed.horizontal,
        spacing = 5,
    }, text_widget
end

-- Create progressbars
local bat_bar = create_progressbar(COLOR_GREEN, 35, 20)
local ram_bar = create_progressbar(COLOR_GREEN, 80, 90)
local hd_bar = create_progressbar(COLOR_GREEN, 70, 90)
local cpu_bar = create_progressbar(COLOR_ORANGE, 50, 80)

-- Create monitor widgets
local bat_widget, bat_text = create_monitor_widget("BAT", bat_bar)
local ram_widget = create_monitor_widget("RAM", ram_bar)
local hd_widget = create_monitor_widget("HD", hd_bar)
local cpu2_widget = create_monitor_widget("CPU", cpu_bar)

-- Using df command and parsing output
function get_partition_usage(mount_point)
    local handle = io.popen("df --output=pcent " .. mount_point .. " | tail -n 1")
    local result = handle:read("*a")
    handle:close()
    
    return tonumber(result:match("(%d+)"))
end

local prev_total = 0
local prev_idle = 0
function get_cpu_percentage()
    local f = io.open("/proc/stat", "r")
    local line = f:read("*l")
    f:close()
    local user, nice, system, idle, iowait, irq, softirq, steal = line:match("cpu%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)")
    local idle_now = idle + iowait
    local total_now = (user + nice + system + idle + iowait + irq + softirq + steal)
    local diff_idle = idle_now - prev_idle
    local diff_total = total_now - prev_total
    local usage = (1 - diff_idle / diff_total) * 100
    prev_total = total_now
    prev_idle = idle_now
    return usage
end

function get_ram_percentage()
    local meminfo = {}
    for line in io.lines("/proc/meminfo") do
        local key, value = line:match("(%w+):%s+(%d+)")
        if key and value then
            meminfo[key] = tonumber(value)
        end
    end

    -- Values are in kB
    local total = meminfo.MemTotal
    local free = meminfo.MemFree
    local buff = meminfo.Buffers
    local cache = meminfo.Cached

    -- Linux considers buffers+cache as reclaimable, so subtract them from used
    local used = total - free - buff - cache
    local percent = (used / total) * 100

    return percent
end

-- Function to read CPU usage
local function update_cpu()
    update_progressbar(cpu_bar, get_cpu_percentage())
end

-- Function to update slow changing widgets
local function update_slow()
    -- read battery info
    local bat_path = "/sys/class/power_supply/BAT0/"
    local bat_capacity_file = bat_path .. "capacity"
    local bat_status_file = bat_path .. "status"
    local bat_capacity = 0
    local bat_status = "Unknown"
    local f = io.open(bat_capacity_file, "r")
    if f then
        bat_capacity = tonumber(f:read("*l")) or 0
        f:close()
    end
    local f = io.open(bat_status_file, "r")
    if f then
        bat_status = f:read("*l") or "Unknown"
        f:close()
    end

    update_progressbar(ram_bar, get_ram_percentage())
    update_progressbar(hd_bar, get_partition_usage("/"))

    -- Update battery bar
    bat_bar.value = bat_capacity
    bat_text.text = bat_status
    
    -- Hide widgets when charging
    if bat_status == "Charging" then
        bat_bar.visible = false
        bat_text.visible = false
        update_progressbar_rev(bat_bar, bat_capacity)
    else
        bat_bar.visible = true
        bat_text.visible = true
    end
end

-- Initialize the module and start timers
function system_monitor.init()
    -- Update every second
    gears.timer { timeout = 1, autostart = true, callback = update_cpu }
    
    -- Update every 10 seconds
    gears.timer { timeout = 10, autostart = true, callback = update_slow }
    
    return {
        battery = bat_widget,
        ram = ram_widget,
        hd = hd_widget,
        cpu = cpu2_widget
    }
end

return system_monitor
