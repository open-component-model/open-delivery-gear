// Plausible analytics (cookieless, no PII), same setup as gardener/documentation and ironcore.dev.
// The tracker itself is loaded async from plausible.io via html_js_files in conf.py.

/**
 * Report each page under the URL Sphinx links to: pages as `/foo.html`, folders as `/foo/`,
 * so `/foo`, `/foo.html` and `/foo/index.html` do not split metrics. GitHub Pages serves
 * `/foo` as `/foo.html`, so an extensionless path without a trailing slash is a page.
 */
function normalizeEventUrl(rawUrl) {
  try {
    const parsed = new URL(rawUrl)
    if (parsed.pathname.endsWith('/index.html')) {
      parsed.pathname = parsed.pathname.slice(0, -'index.html'.length)
    } else if (!parsed.pathname.endsWith('/') && !/\.[a-z0-9]+$/i.test(parsed.pathname)) {
      parsed.pathname += '.html'
    }
    return parsed.toString()
  } catch {
    return rawUrl
  }
}

window.plausible = window.plausible || function () { (plausible.q = plausible.q || []).push(arguments) }
plausible.init = plausible.init || function (i) { plausible.o = i || {} }
plausible.init({
  outboundLinks: true,
  transformRequest: (payload) => ({ ...payload, u: normalizeEventUrl(payload.u) }),
})
