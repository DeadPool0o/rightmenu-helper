import Foundation
import JavaScriptCore

let source = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
    .replacingOccurrences(of: "@VERSION@", with: "1.2.3")
    .replacingOccurrences(of: "@BUILD_NUMBER@", with: "123")
let context = JSContext()!
var failure: String?
context.exceptionHandler = { _, exception in failure = exception?.toString() ?? "JavaScript error" }
context.evaluateScript("""
var fixture, requestedPath;
var my = {target: {mountpoint: '/'}, result: {}};
var system = {
    files: {
        fileExistsAtPath: function(path) { requestedPath = path; return fixture !== null; },
        plistAtPath: function(path) { return fixture; }
    },
    compareVersions: function(a, b) {
        var left = a.split('.').map(Number), right = b.split('.').map(Number);
        for (var i = 0; i < Math.max(left.length, right.length); i++) {
            var x = left[i] || 0, y = right[i] || 0;
            if (x !== y) return x > y ? 1 : -1;
        }
        return 0;
    }
};
""" + source + """
var passed = 0;
function check(name, info, expected, kind, mount) {
    fixture = info;
    my = {target: {mountpoint: mount || '/'}, result: {}};
    var result = checkExistingInstallation();
    if (result !== expected || my.result.type !== kind) throw new Error(name);
    passed++;
}
function app(version, build) {
    return {CFBundleIdentifier: 'local.kingdee.RightClickAssistant',
            CFBundleShortVersionString: version, CFBundleVersion: build};
}
check('fresh install', null, true, undefined);
check('upgrade requires confirmation', app('1.2.2', '122'), false, 'Warning');
check('repair allows same version', app('1.2.3', '123'), false, 'Warning');
check('blocks newer release', app('1.3.0', '124'), false, 'Fatal');
check('blocks newer build', app('1.2.3', '124'), false, 'Fatal');
check('blocks newer release with lower build', app('1.3.0', '100'), false, 'Fatal');
check('protects another application', {CFBundleIdentifier: 'other.app'}, false, 'Fatal');
check('protects unreadable app', false, false, 'Fatal');
check('checks selected system volume', null, true, undefined, '/Volumes/Other');
if (requestedPath !== '/Volumes/Other/Applications/右键助手.app') throw new Error('wrong target');
""")
if let failure { throw NSError(domain: "InstallerChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: failure]) }
print("Installer version and replacement checks passed: \(context.objectForKeyedSubscript("passed")!.toInt32())")
