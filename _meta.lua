local _ = require("gettext")
return {
    name = "morningpaper",
    fullname = _("Morning Paper"),
    description = _("Build an automatically delivered EPUB newspaper with a consensus lead-first AI newsroom: fresh public headlines from major paywalled publications are clustered into priority signals, Wide Coverage Net finds accessible corroborating reporting of the same events, and the AI newsroom publishes original evidence-weighted Morning Paper stories. Delivery can run every morning, weekdays, weekly, or manually. v0.12.3 directly wires the runtime scheduler, adds on-device system diagnostics, and fixes lead consensus so repeated feeds from one publication cannot masquerade as independent editorial agreement."),
    version = "0.12.3",
}
