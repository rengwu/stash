enum InjectScript {
    static let source = #"""
// Runs inside x.com in the sync window. It passes the bookmark and like data
// the site loads to Go, and carries out the scroll or navigation Go asks for.
(() => {
  if (window.top !== window || !/(^|\.)x\.com$/.test(location.hostname)) return;

  const xsCapture = (op, status, body) => window.webkit.messageHandlers.xsCapture.postMessage({op, status, body});
  const xsTick = (path, handle, signedIn) => window.webkit.messageHandlers.xsTick.postMessage({path, handle, signedIn});

  const timeline = /\/graphql\/[^/]+\/(Bookmarks|Likes)\b/;

  const open = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (method, url) {
    const m = timeline.exec(String(url));
    if (m) this.addEventListener('load', () => xsCapture(m[1], this.status, this.responseText));
    return open.apply(this, arguments);
  };

  const fetch_ = window.fetch;
  window.fetch = async function (input) {
    const res = await fetch_.apply(this, arguments);
    const m = timeline.exec(String(input && input.url || input));
    if (m) res.clone().text().then(body => xsCapture(m[1], res.status, body));
    return res;
  };

  // Scroll at an uneven, human pace rather than as fast as the page allows.
  const tick = async () => {
    const profile = document.querySelector('a[data-testid="AppTabBar_Profile_Link"]');
    // X sets the twid cookie only for a signed-in account.
    const signedIn = !!profile || /(^|; )twid=/.test(document.cookie);
    const action = await xsTick(location.pathname, profile ? profile.getAttribute('href').slice(1) : '', signedIn);
    if (action.go) location.href = action.go;
    else if (action.scroll) {
      // Step back before going to the bottom: x.com loads the next page on
      // scroll movement, and there is none when the page is already at the end.
      window.scrollBy(0, -800);
      setTimeout(() => window.scrollTo(0, document.documentElement.scrollHeight), 250);
    }
    setTimeout(tick, 1200 + Math.random() * 1300);
  };
  setTimeout(tick, 1500);
})();
"""#
}
