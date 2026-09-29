import Darwin
import Foundation
import IOKit

struct MemorySample {
    var used: Int64
    var total: Int64
    var compressed: Int64
    var swapUsed: Int64
}

struct ProcessSample: Identifiable {
    var id: String { name + "\(cpu)" }
    var name: String
    var cpu: Double
    var memory: Int64
}

enum SystemMetrics {
    static func diskFree() -> Int64 {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? Int64(values?.volumeAvailableCapacity ?? 0)
    }

    static func diskTotal() -> Int64 {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return Int64((try? home.resourceValues(forKeys: [.volumeTotalCapacityKey]).volumeTotalCapacity) ?? 0)
    }

    static func memory() -> MemorySample {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let page = Int64(vm_kernel_page_size)
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        guard result == KERN_SUCCESS else { return MemorySample(used: 0, total: total, compressed: 0, swapUsed: 0) }
        let used = (Int64(stats.active_count) + Int64(stats.wire_count) + Int64(stats.compressor_page_count)) * page
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swap, &size, nil, 0)
        return MemorySample(used: used, total: total, compressed: Int64(stats.compressor_page_count) * page,
                            swapUsed: Int64(swap.xsu_used))
    }

    /// GPU Apple Silicon: IOAccelerator › PerformanceStatistics › "Device Utilization %".
    static func gpuUtilization() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        var best: Double?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
               let value = stats["Device Utilization %"] as? NSNumber {
                best = max(best ?? 0, value.doubleValue)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return best.map { $0 / 100 }
    }

    static func topProcesses(limit: Int = 8) -> [ProcessSample] {
        guard let data = try? Shell.run("/bin/ps", ["-Aceo", "pcpu=,rss=,comm=", "-r"]),
              let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").prefix(limit).compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let cpu = Double(parts[0].replacingOccurrences(of: ",", with: ".")), let rss = Int64(parts[1]) else { return nil }
            return ProcessSample(name: String(parts[2]), cpu: cpu / 100, memory: rss * 1024)
        }
    }
}

/// Tải CPU tính từ hiệu hai lần đọc `host_processor_info`.
final class CPUMeter {
    private var previous: [(busy: UInt64, total: UInt64)] = []

    func sample() -> Double {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return 0 }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        var current: [(busy: UInt64, total: UInt64)] = []
        for cpu in 0..<Int(count) {
            let base = cpu * Int(CPU_STATE_MAX)
            let user = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]))
            let system = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]))
            let nice = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
            let idle = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]))
            current.append((user + system + nice, user + system + nice + idle))
        }
        defer { previous = current }
        guard previous.count == current.count else { return 0 }
        let busy = zip(current, previous).reduce(0.0) { $0 + Double($1.0.busy &- $1.1.busy) }
        let total = zip(current, previous).reduce(0.0) { $0 + Double($1.0.total &- $1.1.total) }
        return total > 0 ? busy / total : 0
    }
}
