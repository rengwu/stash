import Foundation
import SQLite3

package struct ArchiveError: LocalizedError {
    package let errorDescription: String?
    package init(_ message: String) { errorDescription = message }
}

enum SQLValue {
    case text(String), int(Int64)
}

struct Row {
    let statement: OpaquePointer
    func text(_ i: Int32) -> String { sqlite3_column_text(statement, i).map { String(cString: $0) } ?? "" }
    func int(_ i: Int32) -> Int64 { sqlite3_column_int64(statement, i) }
}

// Used synchronously inside Store. A row is valid only during its query callback.
final class Database {
    private let handle: OpaquePointer
    private var error: ArchiveError { ArchiveError(String(cString: sqlite3_errmsg(handle))) }

    init(_ url: URL) throws {
        var connection: OpaquePointer?
        let rc = sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard let connection else { throw ArchiveError("SQLite could not allocate a connection.") }
        guard rc == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(connection))
            sqlite3_close(connection)
            throw ArchiveError(message)
        }
        handle = connection
        try execute("PRAGMA busy_timeout=10000; PRAGMA journal_mode=WAL")
    }

    deinit { sqlite3_close(handle) }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw error }
    }

    func query<T>(_ sql: String, _ bindings: [SQLValue] = [], _ read: (Row) throws -> T) throws -> [T] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw error }
        defer { sqlite3_finalize(stmt) }
        for (index, binding) in bindings.enumerated() {
            let i = Int32(index + 1)
            let rc = switch binding {
            case .text(let text): sqlite3_bind_text(stmt, i, text, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case .int(let value): sqlite3_bind_int64(stmt, i, value)
            }
            guard rc == SQLITE_OK else { throw error }
        }
        var result: [T] = []
        while true {
            switch sqlite3_step(stmt) {
            case SQLITE_ROW: result.append(try read(Row(statement: stmt)))
            case SQLITE_DONE: return result
            default: throw error
            }
        }
    }

    @discardableResult
    func run(_ sql: String, _ bindings: [SQLValue]) throws -> (changes: Int, lastRowID: Int64) {
        _ = try query(sql, bindings) { _ in () }
        return (Int(sqlite3_changes(handle)), sqlite3_last_insert_rowid(handle))
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }
}
