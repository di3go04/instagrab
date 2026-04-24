import 'dart:io';

/// Lifts Instagram session cookies from the user's Firefox profile.
///
/// Linux-only. Shells out to the system `sqlite3` CLI rather than embedding
/// a Dart SQLite binding — Firefox's `cookies.sqlite` is the only store we
/// read from, and the CLI dependency is trivially satisfied on any desktop
/// distro.
class FirefoxCookieJar {
  /// Reads all `instagram.com` cookies from the first Firefox profile that
  /// has any, and returns them formatted as a ready-to-use `Cookie:` header
  /// value. Returns null if no profile has Instagram cookies (user not
  /// logged in) or Firefox isn't installed.
  ///
  /// Throws [CookieReadException] on unexpected I/O or `sqlite3` failures.
  static Future<String?> readInstagramCookieHeader() async {
    final home = Platform.environment['HOME'];
    if (home == null) {
      throw const CookieReadException('HOME environment variable not set');
    }

    final firefoxDir = Directory('$home/.mozilla/firefox');
    if (!await firefoxDir.exists()) {
      return null;
    }

    await _checkSqlite3Available();

    // Enumerate all profile cookie DBs. Prefer the one with the most
    // recently modified DB (= most recent login / browsing activity).
    final candidates = <_ProfileCookies>[];
    await for (final entry in firefoxDir.list()) {
      if (entry is! Directory) continue;
      final db = File('${entry.path}/cookies.sqlite');
      if (!await db.exists()) continue;
      final cookies = await _readCookies(db);
      if (cookies.containsKey('sessionid')) {
        candidates.add(_ProfileCookies(db.path, cookies));
      }
    }

    if (candidates.isEmpty) return null;

    candidates.sort((a, b) {
      final ma = File(a.dbPath).statSync().modified;
      final mb = File(b.dbPath).statSync().modified;
      return mb.compareTo(ma);
    });

    return _formatCookieHeader(candidates.first.cookies);
  }

  static Future<void> _checkSqlite3Available() async {
    try {
      final result = await Process.run('sqlite3', ['--version']);
      if (result.exitCode != 0) {
        throw const CookieReadException(
          'sqlite3 CLI is required. Install it with your package manager '
          '(e.g. `sudo dnf install sqlite` or `sudo apt install sqlite3`).',
        );
      }
    } on ProcessException {
      throw const CookieReadException(
        'sqlite3 CLI not found on PATH. Install it with your package '
        'manager (e.g. `sudo dnf install sqlite` or `sudo apt install sqlite3`).',
      );
    }
  }

  /// Copies the DB to a temp path first (Firefox holds a WAL lock while
  /// running) and then queries it for all instagram.com cookies.
  static Future<Map<String, String>> _readCookies(File db) async {
    final tmp = File(
      '${Directory.systemTemp.path}/instagrab_cookies_${db.hashCode}.sqlite',
    );
    try {
      await db.copy(tmp.path);
      final result = await Process.run('sqlite3', [
        '-separator',
        '\t',
        tmp.path,
        "SELECT name, value FROM moz_cookies WHERE host LIKE '%instagram%';",
      ]);
      if (result.exitCode != 0) {
        throw CookieReadException('sqlite3 query failed: ${result.stderr}');
      }
      final out = <String, String>{};
      for (final line in (result.stdout as String).split('\n')) {
        if (line.isEmpty) continue;
        final sep = line.indexOf('\t');
        if (sep < 0) continue;
        out[line.substring(0, sep)] = line.substring(sep + 1);
      }
      return out;
    } finally {
      if (await tmp.exists()) {
        await tmp.delete();
      }
    }
  }

  static String _formatCookieHeader(Map<String, String> cookies) {
    return cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }
}

class _ProfileCookies {
  final String dbPath;
  final Map<String, String> cookies;
  _ProfileCookies(this.dbPath, this.cookies);
}

/// Exception thrown when reading Firefox cookies fails unexpectedly.
///
/// "Not logged in" is signalled by a null return from
/// [FirefoxCookieJar.readInstagramCookieHeader], not by this exception.
class CookieReadException implements Exception {
  final String message;
  const CookieReadException(this.message);
  @override
  String toString() => 'CookieReadException: $message';
}
