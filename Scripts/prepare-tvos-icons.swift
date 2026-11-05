#!/usr/bin/env swift
import Foundation

// tvOS declares alternate icons as an array of asset names. Asset catalog
// compilation can emit the iOS dictionary form; normalize it before export signs the app.
guard CommandLine.arguments.count == 2 else {
    fatalError("usage: prepare-tvos-icons.swift <app Info.plist>")
}
let file = URL(fileURLWithPath: CommandLine.arguments[1])
var format = PropertyListSerialization.PropertyListFormat.binary
let data = try Data(contentsOf: file)
guard var plist = try PropertyListSerialization.propertyList(from: data, format: &format) as? [String: Any] else {
    fatalError("Invalid app property list")
}
if plist["DTPlatformName"] as? String == "appletvos",
   var icons = plist["CFBundleIcons"] as? [String: Any],
   let alternates = icons["CFBundleAlternateIcons"] as? [String: [String: Any]] {
    let names = alternates.keys.sorted()
    guard names.allSatisfy({ alternates[$0]?["CFBundleIconName"] as? String == $0 }) else {
        fatalError("Alternate icon names do not match their assets")
    }
    icons["CFBundleAlternateIcons"] = names
    plist["CFBundleIcons"] = icons
    try PropertyListSerialization.data(fromPropertyList: plist, format: format, options: 0)
        .write(to: file, options: .atomic)
    print("Prepared \(names.count) tvOS alternate icon declarations")
}
