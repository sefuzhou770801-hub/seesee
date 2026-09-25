import Foundation

@main
struct LanPlayerCommand {
    static func main() {
        do {
            let options = try Options.parse(CommandLine.arguments)
            if options.help {
                FileHandle.standardOutput.write(Data(Options.usage.utf8))
                return
            }
            guard FileManager.default.fileExists(atPath: options.queueFile.path) else {
                fputs("找不到队列文件\n", stderr)
                exit(1)
            }
            let token = try LanAccess.loadOrCreate(at: options.tokenFile)
            let runtime = LanPlayerRuntime(queueFile: options.queueFile, token: token)
            let hosts = options.bind.map { [$0] } ?? LanNet.defaultHosts()
            try runtime.start(hosts: hosts, port: options.port)
            var printed = Set<String>()
            for host in hosts {
                let display = host == "0.0.0.0" ? (LanNet.lanIPv4() ?? "127.0.0.1") : host
                let line = "打开：http://\(display):\(runtime.port)/?k=\(token)\n"
                if printed.insert(line).inserted {
                    FileHandle.standardOutput.write(Data(line.utf8))
                }
            }
            dispatchMain()
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

private struct Options {
    var help = false
    var port: UInt16 = 18780
    var bind: String?
    var queueFile: URL
    var tokenFile: URL

    static var usage: String {
        """
        用法：scripts/lan_player.sh [--port 18780] [--bind 地址]
        在 iPad Safari 打开启动时打印的地址。

        """
    }

    static func parse(_ arguments: [String]) throws -> Options {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Replay", isDirectory: true)
        var options = Options(
            queueFile: support.appendingPathComponent("queue.json"),
            tokenFile: support.appendingPathComponent("lan-player-access-code")
        )
        var index = 1
        while index < arguments.count {
            let arg = arguments[index]
            switch arg {
            case "-h", "--help":
                options.help = true
            case "--port":
                index += 1
                guard index < arguments.count, let value = UInt16(arguments[index]) else {
                    throw NSError(domain: "LanPlayer", code: 6, userInfo: [NSLocalizedDescriptionKey: "端口无效"])
                }
                options.port = value
            case "--bind":
                index += 1
                guard index < arguments.count else {
                    throw NSError(domain: "LanPlayer", code: 7, userInfo: [NSLocalizedDescriptionKey: "缺少绑定地址"])
                }
                options.bind = arguments[index]
            case "--queue":
                index += 1
                guard index < arguments.count else {
                    throw NSError(domain: "LanPlayer", code: 8, userInfo: [NSLocalizedDescriptionKey: "缺少队列路径"])
                }
                options.queueFile = URL(fileURLWithPath: arguments[index])
            case "--token-file":
                index += 1
                guard index < arguments.count else {
                    throw NSError(domain: "LanPlayer", code: 9, userInfo: [NSLocalizedDescriptionKey: "缺少访问码路径"])
                }
                options.tokenFile = URL(fileURLWithPath: arguments[index])
            default:
                throw NSError(domain: "LanPlayer", code: 10, userInfo: [NSLocalizedDescriptionKey: "未知参数"])
            }
            index += 1
        }
        return options
    }
}
