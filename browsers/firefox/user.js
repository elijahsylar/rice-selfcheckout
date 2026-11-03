// SelfCheckout rice: Firefox prefs needed for the theme.
// user.js is read at startup and copied into prefs.js.

// Honor userChrome.css / userContent.css (Firefox 69+).
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// Draw the tab strip into the titlebar so userChrome.css can paint it black.
user_pref("browser.tabs.inTitlebar", 1);
// Legacy GTK-decoration pref (pre-Firefox 106); harmless on newer builds.
user_pref("browser.tabs.drawInTitlebar", false);

// Draw the window opaque instead of compositing it against the desktop;
// without this the top of the chrome shows other windows through it.
user_pref("widget.gtk.rounded-bottom-corners.enabled", false);
user_pref("mozilla.widget.use-argb-visuals", false);
user_pref("widget.compositor.force-composite", true);

// The built-in new tab wallpapers bleed through userContent.css backgrounds.
user_pref("browser.newtabpage.activity-stream.newtabWallpapers.enabled", false);
user_pref("browser.newtabpage.activity-stream.newtabWallpapers.v2.enabled", false);

// Tab hover previews render on a transparent surface with this theme.
user_pref("browser.tabs.hoverPreview.enabled", false);
user_pref("browser.tabs.cardPreview.enabled",  false);

// Use the default theme so no installed theme extension overrides userChrome.css.
user_pref("extensions.activeThemeID", "default-theme@mozilla.org");

// Optional: GNOME text-scaling-factor (1.2 in gnome-dconf/interface.dconf) also
// scales Firefox through GDK. 0.85 x 1.2 is roughly native size.
user_pref("layout.css.devPixelsPerPx", "0.85");
