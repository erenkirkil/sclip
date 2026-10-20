/// Sahte portların ortak, sıralı çağrı günlüğü; çağrı sırası testlerinde kullanılır.
final class CallLog {
    private(set) var entries: [String] = []

    func add(_ call: String) { entries.append(call) }

    func index(of call: String) -> Int? { entries.firstIndex(of: call) }

    func count(of call: String) -> Int { entries.filter { $0 == call }.count }
}
