//
//  NatifPostStyle.swift
//  HFRswift
//
//  "Natif calme" styling of the topic WebView (Design/natif/post.css adapted to the HTML
//  produced by LinkItem / templatev2.htm). Injected on top of style-liste-light.css:
//  the DOM contract used by the JS bridge (.message#index, .header > .left2/.left/.right/.leftdate,
//  table.citation*, span.signature...) is left untouched.
//

import SwiftUI

enum NatifPostStyle {
    static let styleElementID = "natif-styles"

    /// Every rule is scoped to `html[data-natif]` and marked `!important` to win over the legacy
    /// stylesheet (which resets `* { margin/padding: 0 !important }`).
    static let css = """
    html[data-natif="light"] {
      --n-bg: #FFFFFF; --n-text: #151618; --n-text2: #606369; --n-text3: #A2A5AA;
      --n-surface: #F2F3F5; --n-surface2: #E6E8EB; --n-sep: rgba(60, 60, 67, .18);
      --n-mode: rgba(226, 53, 50, .07);
    }
    html[data-natif="dark"] {
      --n-bg: #111213; --n-text: #F0F2F4; --n-text2: #A1A5AB; --n-text3: #606369;
      --n-surface: #202224; --n-surface2: #2F3033; --n-sep: rgba(255, 255, 255, .12);
      --n-mode: rgba(255, 91, 87, .10);
    }
    html[data-natif="oled"] {
      --n-bg: #000000; --n-text: #F0F2F4; --n-text2: #A1A5AB; --n-text3: #606369;
      --n-surface: #151618; --n-surface2: #232426; --n-sep: rgba(255, 255, 255, .12);
      --n-mode: rgba(255, 91, 87, .10);
    }

    html[data-natif], html[data-natif] body, html[data-natif] body.ios7 {
      background: var(--n-bg) !important;
    }
    html[data-natif] body, html[data-natif] body * {
      font-family: -apple-system, system-ui, sans-serif !important;
    }
    html[data-natif] body .bunselected {
      max-width: 680px; margin: 0 auto !important;
    }

    /* Message */
    html[data-natif] body .message {
      background: var(--n-bg) !important;
      border-bottom: .5px solid var(--n-sep) !important;
      padding: 14px 20px 16px !important;
    }
    html[data-natif] body .message.mode { background: var(--n-mode) !important; }
    html[data-natif] body .separator1 { border-top: 2px solid var(--n-accent) !important; }

    /* Header: avatar | pseudo / date | ••• */
    html[data-natif] body .message .header,
    html[data-natif] body.ios7 .message .header,
    html[data-natif] body.ios7 .message.me .header,
    html[data-natif] body.ios7 .message.whitelist .header,
    html[data-natif] body.ios7 .message.mode .header,
    html[data-natif] body.ios7 .message.blacklist .header {
      display: grid !important;
      grid-template-columns: 36px minmax(0, 1fr) 44px;
      grid-template-rows: auto auto;
      column-gap: 10px;
      align-items: center;
      height: auto !important;
      min-height: 44px;
      margin: 0 !important;
      padding: 0 !important;
      border: none !important;
      background: transparent !important;
    }
    html[data-natif] body .message .header .left2 {
      grid-column: 1; grid-row: 1 / span 2;
      float: none !important;
      width: 36px !important; height: 36px !important;
      border: none !important;
      border-radius: 50%;
      background-color: var(--n-surface2);
    }
    html[data-natif] body .message.me .header .left2 {
      box-shadow: 0 0 0 2px var(--n-bg), 0 0 0 3.5px var(--n-accent);
    }
    html[data-natif] body .message .header .left {
      grid-column: 2; grid-row: 1;
      float: none !important; display: block !important;
      margin: 0 !important; height: auto !important;
      align-self: end;
      font-size: 15px !important; font-weight: 600 !important; line-height: 1.25 !important;
      color: var(--n-text) !important; text-shadow: none !important;
      overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
    }
    html[data-natif] body .message .header .leftdate {
      grid-column: 2; grid-row: 2;
      float: none !important; display: block !important;
      margin: 2px 0 0 !important; height: auto !important;
      align-self: start; text-align: left !important;
      font-size: 12.5px !important; font-weight: 400 !important; line-height: 1.25 !important;
      color: var(--n-text2) !important; text-shadow: none !important;
    }
    html[data-natif] body .message .header .right {
      grid-column: 3; grid-row: 1 / span 2;
      float: none !important;
      width: 44px !important; height: 44px !important;
      margin: 0 -8px 0 0 !important;
      position: relative;
      font-size: 0 !important; color: transparent !important;
      justify-self: end;
    }
    html[data-natif] body .message .header .right::before {
      content: ""; position: absolute; left: 7px; top: 7px;
      width: 30px; height: 30px; border-radius: 50%;
      background: var(--n-surface);
    }
    html[data-natif] body .message .header .right::after {
      content: "\\2022\\2022\\2022"; position: absolute; left: 0; right: 0; top: 0;
      line-height: 44px; text-align: center;
      font-size: 10px; letter-spacing: 1px; color: var(--n-text);
    }
    html[data-natif] body .message .header .clear { display: none !important; }

    /* Body */
    html[data-natif] body .message .content,
    html[data-natif] body .message.me .content,
    html[data-natif] body .message.whitelist .content,
    html[data-natif] body .message.mode .content {
      background: transparent !important;
      border: none !important;
      padding: 10px 0 0 !important;
    }
    html[data-natif] body .message .content .right {
      float: none !important;
      width: 100% !important;
      line-height: 1.45 !important;
      color: var(--n-text) !important;
      overflow-wrap: anywhere;
    }
    html[data-natif] body .message .content .right * { color: inherit; }
    html[data-natif] body div[id^=para] { padding: 0 !important; }
    html[data-natif] body .message .content .right a { color: var(--n-accent) !important; text-underline-offset: 3px; }

    /* Smileys stay inline */
    html[data-natif] body .message .content .right img[src*="/icones/"],
    html[data-natif] body .message .content .right img.smileycustom {
      vertical-align: -3px;
    }

    /* Images and link rows */
    html[data-natif] body .message .content .right img.hfrplusimg {
      max-width: 100% !important; height: auto; border-radius: 12px;
    }
    html[data-natif] body .message .content .right > a.cLink {
      border: none !important; border-radius: 12px;
      background-color: var(--n-surface) !important;
      padding: 0 12px !important; margin: 8px 0 !important;
    }

    /* Quotes: level 1 = surface / radius 12, nested = surface2 / radius 9 */
    html[data-natif] body table.citation,
    html[data-natif] body table.oldcitation,
    html[data-natif] body table.quote,
    html[data-natif] body table.citation_me_quoted,
    html[data-natif] body table.citation_whitelist,
    html[data-natif] body table.citation_blacklist {
      width: 100%;
      border: none !important;
      border-collapse: separate; border-spacing: 0;
      border-radius: 12px;
      background: var(--n-surface) !important;
      margin: 10px 0 !important;
    }
    html[data-natif] body table.citation_me_quoted { box-shadow: inset 3px 0 0 var(--n-accent); }
    html[data-natif] body table.citation td,
    html[data-natif] body table.oldcitation td,
    html[data-natif] body table.quote td,
    html[data-natif] body table.citation_me_quoted td,
    html[data-natif] body table.citation_whitelist td,
    html[data-natif] body table.citation_blacklist td {
      padding: 10px 12px !important;
      font-size: .9em !important; line-height: 1.4;
    }
    html[data-natif] body td > b.s1 { display: block; margin-bottom: 5px !important; }
    html[data-natif] body td > b.s1 ~ br { display: none; }
    html[data-natif] body td > p > br:first-child,
    html[data-natif] body td > p > br:last-child { display: none; }
    html[data-natif] body td > p:last-child { margin-bottom: 0 !important; }
    html[data-natif] body b.s1, html[data-natif] body b.s1 a, html[data-natif] body b.s1 a.Topic {
      font-size: 13px !important; font-weight: 600 !important;
      color: var(--n-accent) !important; text-decoration: none !important;
    }
    html[data-natif] body table table.citation,
    html[data-natif] body table table.oldcitation,
    html[data-natif] body table table.citation_me_quoted,
    html[data-natif] body table table.citation_whitelist {
      background: var(--n-surface2) !important;
      border-radius: 9px;
      margin: 6px 0 !important;
    }
    html[data-natif] body table table td { padding: 8px 10px !important; }

    /* Code */
    html[data-natif] body table.code, html[data-natif] body table.fixed {
      border: none !important; border-radius: 9px;
      background: var(--n-surface) !important;
    }
    html[data-natif] body table.code td, html[data-natif] body table.fixed td { padding: 8px 10px !important; }

    /* Signature, edits, quote counter */
    html[data-natif] body span.signature {
      display: block;
      margin-top: 10px !important; padding-top: 8px !important;
      border-top: .5px solid var(--n-sep);
      font-size: 12.5px !important; line-height: 1.35;
      color: var(--n-text2) !important;
    }
    html[data-natif] body .message .content .right p.editedhfrlink {
      font-size: 12.5px !important; font-style: normal;
      color: var(--n-text2) !important; text-align: left;
      margin: 8px 0 0 !important;
    }
    html[data-natif] body .message .content .right a.quotedhfrlink {
      background: var(--n-surface) !important;
      color: var(--n-accent) !important;
      width: auto !important; height: 22px !important;
      padding: 0 8px !important; border-radius: 11px;
      line-height: 22px !important; font-size: 12px !important;
    }
    """

    /// JavaScript that tags the document with the theme and accent and installs the stylesheet.
    /// Safe to run at document start (before <head> exists) and again on every theme change.
    static func installationScript(themeName: String, accent: String, accentFill: String, accentSoft: String) -> String {
        let cssLiteral = javascriptStringLiteral(css)
        return """
        (function() {
          var root = document.documentElement;
          if (!root) { return; }
          root.setAttribute('data-natif', '\(themeName)');
          root.style.setProperty('--n-accent', '\(accent)');
          root.style.setProperty('--n-accent-fill', '\(accentFill)');
          root.style.setProperty('--n-accent-soft', '\(accentSoft)');
          function install() {
            var style = document.getElementById('\(styleElementID)');
            if (!style) {
              style = document.createElement('style');
              style.id = '\(styleElementID)';
            }
            style.textContent = \(cssLiteral);
            (document.head || root).appendChild(style);
          }
          install();
          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', install, { once: true });
          }
        })();
        """
    }

    static func installationScript(tokens: NatifTokens) -> String {
        installationScript(
            themeName: tokens.variant.rawValue,
            accent: tokens.uiAccent.natifCSSHex,
            accentFill: tokens.uiAccentFill.natifCSSHex,
            accentSoft: tokens.uiAccentSoft.natifCSSHex
        )
    }

    private static func javascriptStringLiteral(_ value: String) -> String {
        guard
            let data = try? JSONSerialization.data(withJSONObject: [value]),
            let array = String(data: data, encoding: .utf8)
        else {
            return "''"
        }
        // ["..."] -> "..."
        return String(array.dropFirst().dropLast())
    }
}
