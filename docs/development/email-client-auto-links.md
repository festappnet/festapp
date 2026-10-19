# Automatic links added by email clients

The server must not turn ordinary substitutions into anchors. The scoped
Country bál confirmation template and its wrapper were checked read-only on
2026-10-19: both contain zero anchors. The contact block likewise emits plain
escaped text. The former preview fix removed application-side linkification;
it does not control how a recipient's email client processes received HTML.

`renderEmail` applies consistent appearance to contact, URL and long numeric text
outside authored anchors after composing the final body. Inline spans scope a
stylesheet using Gmail-supported color, text-decoration and font properties.
Client-generated links inherit the surrounding text style. Explicitly authored
links retain their original styling and destination, including the order status
action.

This changes appearance only. Gmail can still recognize the text and make it
clickable. No invisible characters are inserted: copied bank details and email
addresses stay exact. Subjects, delivery addresses and attachments are unchanged.
Do not add unsupported pointer-events CSS or claim that this prevents links.

Tests cover the final HTML and unchanged text. A local browser simulation of
client-added anchors verifies computed appearance and selected text. No customer
emails are sent; actual delivery rendering remains a separate verification.

References: [Gmail CSS support](https://developers.google.com/workspace/gmail/design/css),
[Litmus on client-added links](https://www.litmus.com/blog/how-to-remove-blue-links-in-html-emails).
