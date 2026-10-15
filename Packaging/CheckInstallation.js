function checkExistingInstallation() {
    var mount = my.target.mountpoint || "/";
    var prefix = mount === "/" ? "" : mount.replace(/\/$/, "");
    var app = prefix + "/Applications/右键助手.app";
    if (!system.files.fileExistsAtPath(app)) {
        return true;
    }
    var info = system.files.plistAtPath(app + "/Contents/Info.plist");
    if (!info || info.CFBundleIdentifier !== "local.kingdee.RightClickAssistant") {
        my.result.type = "Fatal";
        my.result.title = "安装位置已被其他应用占用";
        my.result.message = "“应用程序”中已有同名项目，无法确认其属于右键助手。请先检查该项目，安装程序不会覆盖它。";
        return false;
    }
    var version = String(info.CFBundleShortVersionString || "0");
    var build = String(info.CFBundleVersion || "0");
    var versionOrder = system.compareVersions(version, "@VERSION@");
    var buildOrder = system.compareVersions(build, "@BUILD_NUMBER@");
    if (versionOrder > 0 || buildOrder > 0) {
        my.result.type = "Fatal";
        my.result.title = "已安装更新版本";
        my.result.message = "当前已安装 " + version + "（构建 " + build + "），本安装包为 @VERSION@（构建 @BUILD_NUMBER@）。为避免降级，请使用更新的安装包。";
        return false;
    }
    var repair = versionOrder === 0 && buildOrder === 0;
    my.result.type = "Warning";
    my.result.title = repair ? "检测到相同版本，可重新安装修复" : "检测到旧版本，将覆盖升级";
    my.result.message = "当前已安装 " + version + "，本次安装 @VERSION@。继续后将在原位置替换应用，保留用户配置和自定义模板。程序正在运行时，安装器会先要求退出。";
    return false;
}
