# Automatic links added by email clients

The server must not turn ordinary substitutions into anchors. The scoped
Country bál confirmation template and its wrapper were checked read-only on
2026-10-19: both contain zero anchors. The contact block likewise emits plain
escaped text. The former preview fix removed application-side linkification;
it does not control how a recipient's email client processes received HTML.

`renderEmail` now protects contact, URL and long numeric text outside authored
anchors after composing the final body. Inline spans scope a stylesheet that
preserves inherited appearance and disables pointer interaction for descendant
anchors added later by a client. Authored links, attributes, subjects, delivery
addresses and attachments stay intact. No invisible characters are inserted:
copying a bank account or email preserves its exact value.

This is a client CSS mitigation, not a guarantee that a client will never add an
anchor. Clients can strip CSS or apply different interaction/accessibility
behavior. The tests verify our final HTML and unchanged text; no live customer
emails were sent, and this change has not been verified in a delivered Gmail
message. Do not claim cross-client prevention without a real client check.

Background: [Litmus on client-added links](https://www.litmus.com/blog/how-to-remove-blue-links-in-html-emails).
