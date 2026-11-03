/* SelfCheckout new-tab dashboard: personal settings.
   Everything here is optional; the page works with these defaults. */
window.HOME_CONFIG = {
  // Used in the time-of-day greeting ("good morning, operator").
  name: "operator",

  // The four PROJECTS cards, in order. Icons stay as drawn; change the text
  // and links to point at your own things.
  launchers: [
    { title: "GITHUB",  tagline: "repositories",  href: "https://github.com" },
    { title: "DEVDOCS", tagline: "API reference", href: "https://devdocs.io" },
    { title: "HABITS",  tagline: "habit tracker", href: "https://example.com" },
    { title: "CLOCK",   tagline: "world clock",   href: "https://time.is" },
  ],

  // Badge on the weather card.
  weatherLabel: "LOCAL // 7-DAY",

  // News widget: RSS or Atom feeds, fetched through the rss2json.com proxy
  // (browsers block direct cross-origin feed requests). The newest items
  // across all feeds are shown, three at a time. Empty list = widget idle.
  // Example: { label: "example", url: "https://example.com/feed.xml" }
  newsFeeds: [],
};
