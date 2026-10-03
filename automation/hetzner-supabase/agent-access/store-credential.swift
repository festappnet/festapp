#!/usr/bin/env swift
// Feed JSON on stdin. No secrets in argv, subprocess output or repository.
import Foundation
import Security
let input = FileHandle.standardInput.readDataToEndOfFile()
guard let credentials = try? JSONSerialization.jsonObject(with: input) as? [String: String],
      Set(credentials.keys) == Set(["client_id", "client_secret", "broker_token"]),
      credentials.values.allSatisfy({ !$0.isEmpty }) else {
    fputs("Invalid credential input\n", stderr)
    exit(1)
}
let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "festapp-agent-diagnostics",
    kSecAttrAccount as String: "festapp-workstation"
]
var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: input] as CFDictionary)
if status == errSecItemNotFound {
    var entry = query
    entry[kSecValueData as String] = input
    entry[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    status = SecItemAdd(entry as CFDictionary, nil)
}
guard status == errSecSuccess else {
    fputs("Keychain write failed (\(status))\n", stderr)
    exit(1)
}
print("Agent credential stored in Keychain.")
