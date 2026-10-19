# Image processing ownership

Flutter image upload entry points send original supported bytes and a named
`ImageUploadProfile` through `DbImages` and `ImageControlClient`. The Image
Worker owns dimensions, encoding quality, byte budgets, validation and storage.
Ticket backgrounds use `ticket-background`: longest edge at most 1080 px,
output at most 800 KiB, JPEG quality 85. PNG stays PNG to preserve transparency;
print artwork is static. Processing failure never stores an unprocessed original
for a profile-based upload. Existing stored images are not rewritten.

The numeric-options request parser is a boundary adapter for already installed
Festapp clients and independent AKH consumers that do not yet send `profile`.
It is not used by current Flutter callers. Remove that adapter only after the
supported installed-client floor and the AKH producers have migrated, confirmed
by the producer inventory and request telemetry. It delegates processing to the
same `processUploadImage` implementation.

Client compression helpers are obsolete. Do not reintroduce
`ImageCompressionHelper`, `TicketBackgroundImage`, numeric processing overrides,
or a second ticket-background upload path.
